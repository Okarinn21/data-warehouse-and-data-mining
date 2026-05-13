# Chiến lược Index — DataWarehouse (Star Schema + MOLAP)

## Bối cảnh kiến trúc

Hệ thống sử dụng **MOLAP (Multidimensional OLAP)** với SSAS Cube.

| Thành phần | Vai trò |
|---|---|
| SQL Server (DataWarehouse) | Lưu trữ dữ liệu gốc — Fact_Sales, Dim_Time, Dim_Customer, Dim_Product |
| SSAS Cube | Xử lý trước (pre-aggregate) và lưu kết quả dưới dạng cube |
| Ứng dụng / Dashboard | Query MDX vào cube — **không query thẳng SQL Server** |

**Vì vậy**, index trên SQL Server **không** phục vụ truy vấn OLAP của người dùng cuối.  
Index phục vụ **2 mục đích chính**:
1. **Cube Processing** — SSAS đọc SQL Server để xây dựng / làm mới cube
2. **ETL** — nạp dữ liệu từ staging vào DataWarehouse

---

## Phân loại Index trong SQL Server

| Loại | Lưu trữ | Tốt nhất cho | Ghi chú |
|---|---|---|---|
| Clustered B-Tree | Theo hàng (row-store), quyết định thứ tự vật lý | Tra cứu điểm (point lookup), range scan theo PK | Mỗi bảng chỉ có đúng 1 |
| Non-Clustered B-Tree | B-Tree riêng biệt, trỏ về data page | JOIN selective, filter có chọn lọc cao | Có thể thêm INCLUDE columns (Covering) hoặc WHERE (Filtered) |
| Non-Clustered Columnstore (NCCI) | Theo cột (column-store), nén 5–10× | Scan toàn bộ bảng + aggregate lớn | Tồn tại song song với Clustered B-Tree — dùng khi SSAS scan Fact_Sales để process cube |

---

## Danh sách Index

### Fact_Sales

| Tên Index | Loại | Cột Key | Cột Include | Filter | Mục đích |
|---|---|---|---|---|---|
| PK__Fact_Sales | Clustered B-Tree | SalesID | — | — | Thứ tự vật lý theo IDENTITY. INSERT tuần tự, không page split. Fact table chỉ APPEND. |
| ncci_fact_sales | Non-Clustered Columnstore | CustomerID, ProductID, TimeID, Quantity, Price, TotalAmount | — | — | **Quan trọng nhất với MOLAP**: SSAS scan toàn bộ Fact_Sales khi process cube → NCCI tăng tốc đọc cột TotalAmount, Quantity mà không cần đọc toàn dòng. Nén 5–10×, batch mode. |
| idx_sales_time | Non-Clustered B-Tree | TimeID | TotalAmount, Quantity | — | SSAS filter theo tháng khi process incremental cube partition. Covering → không cần Key Lookup. |
| idx_sales_customer | Non-Clustered B-Tree | CustomerID | TotalAmount, Quantity | — | SSAS JOIN Fact_Sales với Dim_Customer khi build dimension member. |
| idx_sales_product | Non-Clustered B-Tree | ProductID | TotalAmount, Quantity | — | SSAS JOIN Fact_Sales với Dim_Product khi build dimension member. |
| idx_sales_dice_customer_time | Non-Clustered B-Tree | CustomerID, TimeID | TotalAmount, Quantity, ProductID | — | Dùng khi có query SQL trực tiếp (báo cáo ad-hoc ngoài cube). Composite: Equality (CustomerID) trước, Range (TimeID) sau. |
| idx_sales_dice_product_time | Non-Clustered B-Tree | ProductID, TimeID | TotalAmount, Quantity, CustomerID | — | Tương tự idx_sales_dice_customer_time nhưng theo chiều Product + Time. |

---

### Dim_Time

| Tên Index | Loại | Cột Key | Cột Include | Filter | Mục đích |
|---|---|---|---|---|---|
| PK__Dim_Time | Clustered B-Tree | TimeID | — | — | TimeID dạng YYYYMM tăng dần → range scan theo tháng hiệu quả. |
| idx_time_hierarchy | Non-Clustered B-Tree | Year, Quarter, Month | — | — | SSAS đọc phân cấp thời gian khi build Time dimension trong cube. Prefix (Year) → cấp Year; (Year, Quarter) → cấp Quarter; full key → cấp Month. |

---

### Dim_Customer

| Tên Index | Loại | Cột Key | Cột Include | Filter | Mục đích |
|---|---|---|---|---|---|
| PK__Dim_Customer | Clustered B-Tree | CustomerID | — | — | Business key — SSAS JOIN từ fact dùng equality seek. |
| idx_customer_city | Non-Clustered B-Tree | ThanhPho | CustomerID, LoaiKH, TenKH | — | SSAS build Geography hierarchy trong cube (Thành phố là level). Covering → không cần Key Lookup. |
| idx_customer_type_KL | Non-Clustered B-Tree | LoaiKH | CustomerID, ThanhPho | LoaiKH = 'KL' | Filtered Index cho Khách lẻ — mô phỏng Bitmap Index (SQL Server không có Bitmap Index native). Index nhỏ hơn toàn bảng → ít I/O khi SSAS lấy member list theo loại khách. |
| idx_customer_type_KB | Non-Clustered B-Tree | LoaiKH | CustomerID, ThanhPho | LoaiKH = 'KB' | Tương tự idx_customer_type_KL nhưng cho Khách buôn. |

---

### Dim_Product

| Tên Index | Loại | Cột Key | Cột Include | Filter | Mục đích |
|---|---|---|---|---|---|
| PK__Dim_Product | Clustered B-Tree | ProductID | — | — | Business key — JOIN từ Fact_Sales dùng equality seek. Không cần index bổ sung vì SSAS không filter theo attribute text (MoTa, Size, Weight). |

---

## Tại sao có index mà trông "lạ" với MOLAP?

Một số index như `idx_sales_dice_customer_time` được thiết kế cho **ROLAP pattern** (query thẳng SQL).  
Với MOLAP, chúng **vẫn có ích** trong 2 trường hợp:

| Trường hợp | Index liên quan |
|---|---|
| SSAS dùng **ROLAP storage mode** cho một số partition (dữ liệu cũ) | Composite index trên Fact_Sales |
| **Ad-hoc SQL query** từ báo cáo hoặc debug ngoài cube | Tất cả Non-Clustered B-Tree |
| **Cube processing** đọc dữ liệu từ SQL Server | ncci_fact_sales, idx_time_hierarchy, idx_customer_city |

---

## Mapping OLAP Operation → Index được dùng khi Process Cube

| Phép toán OLAP | Index SSAS dùng khi process | Ghi chú |
|---|---|---|
| Roll-Up (Month → Year) | idx_time_hierarchy, ncci_fact_sales | SSAS đọc hierarchy Year/Quarter/Month và aggregate TotalAmount |
| Drill-Down (Year → Month) | idx_time_hierarchy, ncci_fact_sales | Cùng index, khác chiều truy xuất |
| Slice (1 chiều) | idx_customer_city, idx_customer_type_KL/KB, ncci_fact_sales | SSAS build member list theo ThanhPho / LoaiKH |
| Dice (nhiều chiều) | idx_sales_dice_customer_time, idx_sales_dice_product_time | Dùng khi SSAS process sub-cube theo nhiều filter |
| Pivot (Cross-tab) | ncci_fact_sales | Cube tự xoay trục — không cần index riêng |
