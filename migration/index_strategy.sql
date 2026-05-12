-- =============================================================================
-- INDEX STRATEGY — DataWarehouse (Star Schema)
-- =============================================================================
--
-- PHÂN LOẠI INDEX TRONG SQL SERVER (áp dụng cho DW):
--
--   ┌────────────────────────────────────┬─────────────────────────────────────────────────┐
--   │ Loại Index                         │ Đặc điểm                                        │
--   ├────────────────────────────────────┼─────────────────────────────────────────────────┤
--   │ Clustered B-Tree                   │ Quyết định thứ tự vật lý dữ liệu trên đĩa.      │
--   │                                    │ Mỗi bảng chỉ có 1. Auto-tạo qua PRIMARY KEY.    │
--   ├────────────────────────────────────┼─────────────────────────────────────────────────┤
--   │ Non-Clustered B-Tree               │ Cấu trúc B-Tree riêng biệt, trỏ về data page.   │
--   │  └─ Covering (INCLUDE)             │ Thêm cột vào leaf → tránh Key Lookup.            │
--   │  └─ Composite (multi-key)          │ Nhiều cột key → tối ưu filter đa chiều (Dice).  │
--   │  └─ Filtered (WHERE clause)        │ Chỉ index tập con dòng → mô phỏng Bitmap Index. │
--   ├────────────────────────────────────┼─────────────────────────────────────────────────┤
--   │ Non-Clustered Columnstore (NCCI)   │ Lưu dữ liệu theo CỘT (column-store).            │
--   │                                    │ Nén tốt hơn ~10×. Batch mode execution.          │
--   │                                    │ Lý tưởng cho scan + aggregate lớn (OLAP).        │
--   │                                    │ Tồn tại song song với Clustered B-Tree.          │
--   ├────────────────────────────────────┼─────────────────────────────────────────────────┤
--   │ Clustered Columnstore (CCI)        │ Thay thế hoàn toàn Clustered B-Tree.             │
--   │                                    │ Tối ưu nhất cho Fact Table lớn trong DW.         │
--   │                                    │ (Không áp dụng ở đây vì schema đã có PK.)        │
--   └────────────────────────────────────┴─────────────────────────────────────────────────┘
--
-- Chiến lược áp dụng cho schema này:
--   Fact_Sales  : NCCI (primary analytics) + B-Tree FK (selective lookups)
--   Dim_Time    : Composite B-Tree (hierarchy: Year, Quarter, Month)
--   Dim_Customer: Covering B-Tree (ThanhPho) + Filtered B-Tree (LoaiKH)
--   Dim_Product : Không cần thêm — Clustered B-Tree trên ProductID đã đủ
--
-- Nguồn lý thuyết:
--   Ralph Kimball — "The Data Warehouse Toolkit" (3rd ed.), Chương 12
--   Microsoft — "SQL Server Index Architecture and Design Guide"
--   Microsoft — "Columnstore Indexes: Overview" (docs.microsoft.com)
-- =============================================================================

USE DataWarehouse;
GO


-- =============================================================================
-- PHẦN 1 — CLUSTERED INDEX (Tham chiếu — tự động tạo qua PRIMARY KEY)
-- =============================================================================
-- Clustered B-Tree Index quyết định thứ tự vật lý của dữ liệu trên đĩa.
-- SQL Server tự tạo khi khai báo PRIMARY KEY → không cần tạo thêm.
--
--   ┌─────────────────┬────────────────────┬──────────────────────────────────────┐
--   │ Bảng            │ Clustered Key      │ Lý do                                │
--   ├─────────────────┼────────────────────┼──────────────────────────────────────┤
--   │ Fact_Sales      │ SalesID (IDENTITY) │ Tuần tự → INSERT nhanh, không page   │
--   │                 │                    │ split. Fact table chỉ cần APPEND.     │
--   ├─────────────────┼────────────────────┼──────────────────────────────────────┤
--   │ Dim_Time        │ TimeID (YYYYMM)    │ Tăng dần theo thời gian → range scan │
--   │                 │                    │ theo tháng/năm hiệu quả.             │
--   ├─────────────────┼────────────────────┼──────────────────────────────────────┤
--   │ Dim_Customer    │ CustomerID         │ Business key — JOIN từ fact dùng     │
--   │                 │                    │ equality seek trực tiếp.             │
--   ├─────────────────┼────────────────────┼──────────────────────────────────────┤
--   │ Dim_Product     │ ProductID          │ Business key — tương tự Dim_Customer.│
--   └─────────────────┴────────────────────┴──────────────────────────────────────┘
--
-- Lưu ý quan trọng về Clustering Key và Non-Clustered Index:
--   Mọi Non-Clustered Index đều tự nhúng Clustering Key làm Row Locator
--   ở mức leaf. → Không bao giờ cần INCLUDE Clustering Key vào NONCLUSTERED INDEX.
--   VD: idx_time_hierarchy trên Dim_Time không cần INCLUDE (TimeID).
-- =============================================================================


-- =============================================================================
-- PHẦN 2 — NON-CLUSTERED COLUMNSTORE INDEX (NCCI) TRÊN Fact_Sales
-- =============================================================================
-- Lý thuyết Columnstore Index:
--   B-Tree Index lưu dữ liệu theo HÀNG (row-store):
--     [SalesID | CustomerID | ProductID | TimeID | Quantity | Price | TotalAmount]
--   Columnstore Index lưu dữ liệu theo CỘT (column-store):
--     [TotalAmount segment] [Quantity segment] [TimeID segment] …
--
--   Ưu điểm Columnstore cho OLAP:
--     (1) Nén: dữ liệu cùng cột có phân phối giống nhau → nén 5–10× tốt hơn.
--     (2) I/O: query SUM(TotalAmount) chỉ đọc đúng cột TotalAmount, không đọc
--         toàn bộ dòng như B-Tree.
--     (3) Batch mode: SQL Server xử lý 64–900 dòng/lần thay vì từng dòng,
--         tăng tốc aggregate 10–100× so với Row mode của B-Tree.
--     (4) Segment Elimination: mỗi Column Segment lưu Min/Max → optimizer bỏ
--         qua segment không chứa giá trị cần tìm (tương đương partition pruning).
--
--   NCCI vs CCI:
--     CCI thay thế Clustered B-Tree → cần thiết kế lại schema (bỏ PK clustered).
--     NCCI tồn tại song song với Clustered B-Tree → áp dụng được ngay.
--     Optimizer tự chọn: scan lớn dùng NCCI, point lookup dùng B-Tree.
--
--   Cú pháp NCCI: không dùng INCLUDE — tất cả cột đều nằm trong column list.
--   Clustering Key (SalesID) tự động có trong NCCI làm Row Locator.
-- =============================================================================

DROP INDEX IF EXISTS ncci_fact_sales ON Fact_Sales;
GO

CREATE NONCLUSTERED COLUMNSTORE INDEX ncci_fact_sales
    ON Fact_Sales (CustomerID, ProductID, TimeID, Quantity, Price, TotalAmount);
-- Bao gồm toàn bộ cột phân tích: 3 FK chiều + 3 measure.
-- SalesID (Clustered Key) không cần liệt kê — tự động có trong NCCI.
-- Query bất kỳ nào SELECT/GROUP BY/SUM trên các cột này sẽ ưu tiên dùng NCCI.
GO


-- =============================================================================
-- PHẦN 3 — NON-CLUSTERED B-TREE COVERING INDEX TRÊN Fact_Sales (FK Indexes)
-- =============================================================================
-- Lý thuyết:
--   NCCI tối ưu cho scan lớn (hàng triệu dòng, nhiều cột).
--   B-Tree FK Index tối ưu cho lookup có chọn lọc cao (selective seek):
--     VD: JOIN Fact_Sales với Dim_Customer trên CustomerID = 'KH001' (1 khách).
--   Optimizer tự chọn loại index phù hợp dựa trên cardinality estimate.
--
--   Covering Index = Non-Clustered B-Tree + INCLUDE columns:
--     Leaf page của index chứa cả Key Column lẫn INCLUDE Columns.
--     Query chỉ cần đọc index page, không quay lại data page (Key Lookup).
--     → Loại bỏ random I/O, đặc biệt quan trọng khi Fact_Sales có hàng triệu dòng.
-- =============================================================================

DROP INDEX IF EXISTS idx_sales_time     ON Fact_Sales;
DROP INDEX IF EXISTS idx_sales_customer ON Fact_Sales;
DROP INDEX IF EXISTS idx_sales_product  ON Fact_Sales;
GO

-- ── 3.1  Covering Index trên TimeID ──────────────────────────────────────────
-- Dùng khi NCCI không đủ selective (VD: lọc đúng 1 tháng trên bảng lớn).
CREATE NONCLUSTERED INDEX idx_sales_time
    ON Fact_Sales (TimeID)
    INCLUDE (TotalAmount, Quantity);
GO

-- ── 3.2  Covering Index trên CustomerID ──────────────────────────────────────
CREATE NONCLUSTERED INDEX idx_sales_customer
    ON Fact_Sales (CustomerID)
    INCLUDE (TotalAmount, Quantity);
GO

-- ── 3.3  Covering Index trên ProductID ───────────────────────────────────────
CREATE NONCLUSTERED INDEX idx_sales_product
    ON Fact_Sales (ProductID)
    INCLUDE (TotalAmount, Quantity);
GO


-- =============================================================================
-- PHẦN 4 — NON-CLUSTERED COMPOSITE B-TREE INDEX CHO DICE (Multi-Dimension)
-- =============================================================================
-- Lý thuyết:
--   Phép Dice lọc đồng thời nhiều chiều:
--     WHERE CustomerID = 'KH001' AND TimeID BETWEEN 202401 AND 202412
--   Single-column index xử lý được 1 điều kiện → điều kiện còn lại là Residual
--   Predicate (lọc lại trên rows đã fetch) → kém hiệu quả hơn.
--   Composite Index xử lý cả hai điều kiện trong một Index Seek.
--
--   Nguyên tắc sắp xếp cột trong Composite B-Tree Index:
--     (1) Cột EQUALITY trước (Seek điểm chính xác)
--     (2) Cột RANGE sau (Range Scan tiếp theo trong B-Tree)
--
--   Hai Composite Index riêng biệt thay vì một 3-cột:
--     (CustomerID, TimeID) phục vụ tốt query Dice Customer + Time.
--     (ProductID,  TimeID) phục vụ tốt query Dice Product  + Time.
--     Index 3-cột (TimeID, CustomerID, ProductID) không phục vụ được
--     query chỉ lọc Product + Time (CustomerID ở giữa chặn Range Scan).
-- =============================================================================

DROP INDEX IF EXISTS idx_sales_dice_customer_time ON Fact_Sales;
DROP INDEX IF EXISTS idx_sales_dice_product_time  ON Fact_Sales;
GO

-- ── 4.1  Composite Dice: Customer + Time ─────────────────────────────────────
-- Pattern: "Doanh thu của KH001 trong Q1/2024"
CREATE NONCLUSTERED INDEX idx_sales_dice_customer_time
    ON Fact_Sales (CustomerID, TimeID)
    INCLUDE (TotalAmount, Quantity, ProductID);
GO

-- ── 4.2  Composite Dice: Product + Time ──────────────────────────────────────
-- Pattern: "Sản phẩm SP010 bán được bao nhiêu trong năm 2024"
CREATE NONCLUSTERED INDEX idx_sales_dice_product_time
    ON Fact_Sales (ProductID, TimeID)
    INCLUDE (TotalAmount, Quantity, CustomerID);
GO


-- =============================================================================
-- PHẦN 5 — NON-CLUSTERED COMPOSITE B-TREE INDEX TRÊN Dim_Time (Roll-Up / Drill-Down)
-- =============================================================================
-- Lý thuyết:
--   Roll-Up (Month → Quarter → Year): GROUP BY theo cấp cao hơn trong phân cấp.
--   Drill-Down (Year → Month): GROUP BY theo cấp thấp hơn.
--   Cả hai phép đều GROUP BY trên tập con {Year, Quarter, Month}.
--
--   Composite Index (Year, Quarter, Month) phản ánh thứ tự phân cấp:
--     Prefix (Year)               → GROUP BY Year
--     Prefix (Year, Quarter)      → GROUP BY Year, Quarter
--     Full key (Year, Quarter, Month) → GROUP BY Year, Quarter, Month
--   Optimizer dùng đúng prefix cho từng cấp độ Roll-Up / Drill-Down.
--
--   Lưu ý: TimeID là Clustered Key → KHÔNG INCLUDE (TimeID).
--   Mọi Non-Clustered Index đã tự nhúng Clustering Key làm Row Locator.
-- =============================================================================

DROP INDEX IF EXISTS idx_time_hierarchy ON Dim_Time;
GO

CREATE NONCLUSTERED INDEX idx_time_hierarchy
    ON Dim_Time (Year, Quarter, Month);
GO


-- =============================================================================
-- PHẦN 6 — INDEX TRÊN Dim_Customer (Slice theo địa lý và loại khách)
-- =============================================================================
-- 6a. Covering B-Tree Index trên ThanhPho (cardinality TRUNG BÌNH ~63 giá trị):
--     Phép Slice: WHERE ThanhPho = 'Hà Nội'
--     INCLUDE CustomerID, LoaiKH, TenKH → covering query "danh sách khách Hà Nội"
--     mà không cần Key Lookup về data page.
--
-- 6b. Filtered B-Tree Index trên LoaiKH (cardinality CỰC THẤP — 2 giá trị):
--     Lý thuyết Bitmap Index: lý tưởng cho cột cardinality thấp (lưu bit vector
--     cho mỗi giá trị, AND các vector để kết hợp điều kiện).
--     SQL Server không có native Bitmap Index.
--     Kỹ thuật mô phỏng: Filtered Index — mỗi giá trị tạo một index riêng.
--       idx_customer_type_KL: chỉ chứa dòng LoaiKH = 'KL' (Khách lẻ)
--       idx_customer_type_KB: chỉ chứa dòng LoaiKH = 'KB' (Khách buôn)
--     Index nhỏ hơn nhiều → ít I/O hơn khi Slice theo loại khách.
-- =============================================================================

DROP INDEX IF EXISTS idx_customer_city    ON Dim_Customer;
DROP INDEX IF EXISTS idx_customer_type    ON Dim_Customer;
DROP INDEX IF EXISTS idx_customer_type_KL ON Dim_Customer;
DROP INDEX IF EXISTS idx_customer_type_KB ON Dim_Customer;
GO

-- ── 6.1  Covering Index theo ThanhPho ────────────────────────────────────────
CREATE NONCLUSTERED INDEX idx_customer_city
    ON Dim_Customer (ThanhPho)
    INCLUDE (CustomerID, LoaiKH, TenKH);
GO

-- ── 6.2  Filtered Index LoaiKH = 'KL' (mô phỏng Bitmap — bit vector KL) ──────
CREATE NONCLUSTERED INDEX idx_customer_type_KL
    ON Dim_Customer (LoaiKH)
    INCLUDE (CustomerID, ThanhPho)
    WHERE LoaiKH = 'KL';
GO

-- ── 6.3  Filtered Index LoaiKH = 'KB' (mô phỏng Bitmap — bit vector KB) ──────
CREATE NONCLUSTERED INDEX idx_customer_type_KB
    ON Dim_Customer (LoaiKH)
    INCLUDE (CustomerID, ThanhPho)
    WHERE LoaiKH = 'KB';
GO


-- =============================================================================
-- PHẦN 7 — Dim_Product (Không cần index bổ sung)
-- =============================================================================
-- Lý thuyết:
--   ProductID là Clustered B-Tree (PK) → JOIN từ Fact_Sales vào Dim_Product
--   dùng equality seek thẳng vào Clustered Index — không cần index thêm.
--
--   Các cột khác (MoTa, Size, Weight, Gia) là thuộc tính mô tả sản phẩm.
--   5 phép toán OLAP (Roll-Up, Drill-Down, Slice, Dice, Pivot) không lọc
--   theo nội dung text của attribute dimension → không có lý do tạo index trên đó.
--
-- Xoá index thừa nếu tồn tại từ script khác:
DROP INDEX IF EXISTS idx_product_desc ON Dim_Product;
GO


-- =============================================================================
-- PHẦN 8 — ÁNH XẠ PHÉP TOÁN OLAP → LOẠI INDEX → TÊN INDEX
-- =============================================================================
--
-- ┌───────────────┬────────────────────────────────┬────────────────────────────────────────────┐
-- │ OLAP Operation│ Loại Index Được Dùng           │ Tên Index Cụ Thể                           │
-- ├───────────────┼────────────────────────────────┼────────────────────────────────────────────┤
-- │ Roll-Up       │ Composite B-Tree (hierarchy)   │ idx_time_hierarchy                         │
-- │ Month → Year  │ NCCI (aggregate scan)          │ ncci_fact_sales                            │
-- ├───────────────┼────────────────────────────────┼────────────────────────────────────────────┤
-- │ Drill-Down    │ Composite B-Tree (prefix scan) │ idx_time_hierarchy                         │
-- │ Year → Month  │ NCCI (aggregate scan)          │ ncci_fact_sales                            │
-- ├───────────────┼────────────────────────────────┼────────────────────────────────────────────┤
-- │ Slice         │ Covering B-Tree (địa lý)       │ idx_customer_city                          │
-- │ (1 chiều)     │ Filtered B-Tree (loại khách)   │ idx_customer_type_KL / idx_customer_type_KB│
-- │               │ NCCI (scan fact sau filter dim)│ ncci_fact_sales                            │
-- ├───────────────┼────────────────────────────────┼────────────────────────────────────────────┤
-- │ Dice          │ Composite B-Tree (multi-dim)   │ idx_sales_dice_customer_time               │
-- │ (nhiều chiều) │                                │ idx_sales_dice_product_time                │
-- │               │ NCCI (khi scan toàn bộ)        │ ncci_fact_sales                            │
-- ├───────────────┼────────────────────────────────┼────────────────────────────────────────────┤
-- │ Pivot         │ (không cần index riêng)        │ Tận dụng NCCI + kết quả aggregate          │
-- └───────────────┴────────────────────────────────┴────────────────────────────────────────────┘


-- =============================================================================
-- PHẦN 9 — KIỂM TRA INDEX ĐÃ TẠO (Index Catalog Query)
-- =============================================================================
-- Lưu ý: sys.index_columns không có dữ liệu cho Columnstore Index
-- (columnstore lưu toàn bộ cột, không phân biệt key/include).
-- Dùng i.type_desc để phân biệt NONCLUSTERED COLUMNSTORE với NONCLUSTERED (B-Tree).

SELECT
    t.name          AS TableName,
    i.name          AS IndexName,
    i.type_desc     AS IndexType,
    i.filter_definition AS FilterCondition,
    STRING_AGG(
        CASE WHEN ic.is_included_column = 0 THEN c.name END, ', ')
        WITHIN GROUP (ORDER BY ic.key_ordinal)  AS KeyColumns,
    STRING_AGG(
        CASE WHEN ic.is_included_column = 1 THEN c.name END, ', ')
                                                AS IncludedColumns
FROM sys.indexes       i
JOIN sys.tables        t  ON i.object_id  = t.object_id
LEFT JOIN sys.index_columns ic ON i.object_id = ic.object_id
                              AND i.index_id  = ic.index_id
LEFT JOIN sys.columns  c  ON ic.object_id = c.object_id
                          AND ic.column_id = c.column_id
WHERE t.name IN ('Fact_Sales', 'Dim_Time', 'Dim_Customer', 'Dim_Product')
  AND i.type > 0
GROUP BY t.name, i.name, i.type_desc, i.filter_definition
ORDER BY t.name,
         CASE i.type_desc
             WHEN 'CLUSTERED'              THEN 1
             WHEN 'NONCLUSTERED COLUMNSTORE' THEN 2
             WHEN 'NONCLUSTERED'           THEN 3
             ELSE 4
         END,
         i.name;
GO


-- =============================================================================
-- PHẦN 10 — BẢO TRÌ INDEX SAU ETL
-- =============================================================================
-- B-Tree Index và Columnstore Index có cơ chế bảo trì KHÁC NHAU.
--
-- ── B-Tree Index ──────────────────────────────────────────────────────────────
-- Bị phân mảnh (fragmentation) khi INSERT liên tục gây page split.
--
-- Kiểm tra phân mảnh:
-- SELECT OBJECT_NAME(ips.object_id) AS TableName,
--        i.name                     AS IndexName,
--        ips.avg_fragmentation_in_percent
-- FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
-- JOIN sys.indexes i ON ips.object_id = i.object_id
--                   AND ips.index_id  = i.index_id
-- WHERE ips.index_type_desc = 'NONCLUSTERED'
--   AND ips.avg_fragmentation_in_percent > 10
-- ORDER BY ips.avg_fragmentation_in_percent DESC;
--
--  5% – 30% fragmentation → REORGANIZE (online, nhẹ):
-- ALTER INDEX idx_sales_time     ON Fact_Sales   REORGANIZE;
-- ALTER INDEX idx_sales_customer ON Fact_Sales   REORGANIZE;
-- ALTER INDEX idx_sales_product  ON Fact_Sales   REORGANIZE;
-- ALTER INDEX idx_time_hierarchy ON Dim_Time     REORGANIZE;
-- ALTER INDEX idx_customer_city  ON Dim_Customer REORGANIZE;
--
-- > 30% fragmentation → REBUILD (offline, reset statistics):
-- ALTER INDEX idx_sales_time     ON Fact_Sales   REBUILD;
-- ALTER INDEX idx_sales_customer ON Fact_Sales   REBUILD;
-- ALTER INDEX idx_sales_product  ON Fact_Sales   REBUILD;
-- ALTER INDEX idx_time_hierarchy ON Dim_Time     REBUILD;
-- ALTER INDEX idx_customer_city  ON Dim_Customer REBUILD;
-- ALTER INDEX idx_customer_type_KL ON Dim_Customer REBUILD;
-- ALTER INDEX idx_customer_type_KB ON Dim_Customer REBUILD;
--
-- ── Columnstore Index (NCCI) ──────────────────────────────────────────────────
-- Columnstore không bị phân mảnh theo nghĩa B-Tree.
-- Vấn đề: Delta Store — dữ liệu mới INSERT vào Delta Store (B-Tree nhỏ),
--   chưa được nén vào Columnstore Segment cho đến khi đủ ~1 triệu dòng
--   (Tuple Mover chạy background) hoặc khi REBUILD/REORGANIZE.
--
-- REORGANIZE ncci_fact_sales: đóng Delta Store, flush vào Columnstore Segment.
-- ALTER INDEX ncci_fact_sales ON Fact_Sales REORGANIZE;
--
-- REBUILD ncci_fact_sales: tái tạo toàn bộ Columnstore, cập nhật statistics.
-- ALTER INDEX ncci_fact_sales ON Fact_Sales REBUILD;
--
-- Khuyến nghị: chạy REBUILD sau mỗi batch ETL lớn để đảm bảo hiệu năng.
