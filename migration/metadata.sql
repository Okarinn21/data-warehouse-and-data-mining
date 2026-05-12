-- =============================================================================
-- METADATA REPOSITORY — DataWarehouse
-- =============================================================================
--
-- Lý thuyết:
--   Metadata ("dữ liệu về dữ liệu") trong Data Warehouse chia thành 3 loại:
--
--   1. Technical Metadata  — mô tả cấu trúc vật lý:
--        bảng, cột, kiểu dữ liệu, ràng buộc, quan hệ FK.
--
--   2. Business Metadata   — mô tả ngữ nghĩa nghiệp vụ:
--        tên nghiệp vụ, định nghĩa KPI, từ điển thuật ngữ.
--        Giúp người dùng cuối (analyst, manager) hiểu dữ liệu
--        mà không cần biết cấu trúc kỹ thuật.
--
--   3. Operational Metadata — mô tả quá trình vận hành:
--        lịch sử ETL, thời gian chạy, số dòng xử lý, trạng thái job.
--        Dùng để giám sát, debug, và audit pipeline.
--
-- Nguồn lý thuyết:
--   W.H. Inmon — "Building the Data Warehouse" (4th ed.)
--   Ralph Kimball — "The Data Warehouse Toolkit" (3rd ed.)
-- =============================================================================

USE DataWarehouse;
GO


-- =============================================================================
-- PHẦN 1 — CẤU TRÚC KHO METADATA (Metadata Repository Schema)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1.1  TECHNICAL METADATA — Danh mục bảng (Table Catalog)
-- -----------------------------------------------------------------------------
-- Lưu siêu dữ liệu cấp bảng: loại bảng, chính sách làm tươi, mô tả grain.
-- Grain = mức chi tiết nhỏ nhất mà một dòng trong bảng đại diện.
-- -----------------------------------------------------------------------------
CREATE TABLE Meta_Table (
    TableID          INT IDENTITY(1,1) PRIMARY KEY,
    SchemaName       NVARCHAR(128) NOT NULL DEFAULT 'dbo',
    TableName        NVARCHAR(128) NOT NULL,
    TableType        VARCHAR(20)   NOT NULL
                         CHECK (TableType IN ('FACT', 'DIMENSION', 'STAGING')),
    PrimaryKeyColumn NVARCHAR(256),
    GrainDescription NVARCHAR(500),              -- mô tả độ hạt (grain) của bảng
    RefreshPolicy    VARCHAR(30)   NOT NULL DEFAULT 'FULL_RELOAD'
                         CHECK (RefreshPolicy IN
                               ('FULL_RELOAD', 'INCREMENTAL', 'SCD_TYPE2', 'APPEND_ONLY')),
    SourceSystem     NVARCHAR(256),              -- hệ thống nguồn: OLTP, CRM, ERP…
    Owner            NVARCHAR(128),
    CreatedAt        DATETIME      NOT NULL DEFAULT GETDATE(),
    UpdatedAt        DATETIME      NOT NULL DEFAULT GETDATE(),
    IsActive         BIT           NOT NULL DEFAULT 1,
    TechnicalNotes   NVARCHAR(MAX)
);
GO


-- -----------------------------------------------------------------------------
-- 1.2  TECHNICAL METADATA — Danh mục cột (Column Catalog)
-- -----------------------------------------------------------------------------
-- Lưu siêu dữ liệu cấp cột: kiểu dữ liệu, vai trò trong Star Schema
-- (PK / FK / Measure / Attribute / Surrogate Key), và mapping với hệ thống nguồn.
-- -----------------------------------------------------------------------------
CREATE TABLE Meta_Column (
    ColumnID     INT IDENTITY(1,1) PRIMARY KEY,
    TableID      INT NOT NULL REFERENCES Meta_Table(TableID),
    ColumnName   NVARCHAR(128) NOT NULL,
    DataType     NVARCHAR(64)  NOT NULL,         -- INT, NVARCHAR, DECIMAL…
    MaxLength    INT,                            -- NULL nếu không áp dụng
    Precision    INT,
    Scale        INT,
    IsNullable   BIT NOT NULL DEFAULT 0,
    ColumnRole   VARCHAR(20)   NOT NULL
                     CHECK (ColumnRole IN
                           ('PK', 'FK', 'MEASURE', 'ATTRIBUTE',
                            'DEGENERATE', 'SURROGATE_KEY')),
    BusinessName NVARCHAR(256),                  -- tên hiển thị nghiệp vụ
    BusinessDesc NVARCHAR(500),                  -- mô tả nghiệp vụ của cột
    SourceColumn NVARCHAR(256),                  -- cột tương ứng ở hệ thống nguồn
    SampleValues NVARCHAR(500),                  -- ví dụ giá trị thực tế
    SortOrder    INT NOT NULL DEFAULT 0
);
GO


-- -----------------------------------------------------------------------------
-- 1.3  BUSINESS METADATA — Từ điển nghiệp vụ (Business Glossary)
-- -----------------------------------------------------------------------------
-- Chuẩn hoá thuật ngữ dùng trong kho dữ liệu.
-- Giúp người dùng nghiệp vụ và kỹ thuật nói cùng một ngôn ngữ.
-- -----------------------------------------------------------------------------
CREATE TABLE Meta_BusinessGlossary (
    GlossaryID   INT IDENTITY(1,1) PRIMARY KEY,
    Term         NVARCHAR(256) NOT NULL UNIQUE,
    Definition   NVARCHAR(MAX) NOT NULL,
    Category     NVARCHAR(128),                  -- 'KPI' | 'Dimension' | 'Measure' | 'Policy'
    Owner        NVARCHAR(128),
    RelatedTerms NVARCHAR(500),                  -- thuật ngữ liên quan, phân cách bởi ','
    CreatedAt    DATETIME NOT NULL DEFAULT GETDATE()
);
GO


-- -----------------------------------------------------------------------------
-- 1.4  TECHNICAL METADATA — Danh mục quan hệ (Relationship Catalog)
-- -----------------------------------------------------------------------------
-- Ghi nhận toàn bộ quan hệ Fact → Dimension trong Star Schema.
-- Cardinality luôn là N:1 (nhiều dòng fact → một dòng dimension).
-- -----------------------------------------------------------------------------
CREATE TABLE Meta_Relationship (
    RelationshipID INT IDENTITY(1,1) PRIMARY KEY,
    FactTableID    INT           NOT NULL REFERENCES Meta_Table(TableID),
    DimTableID     INT           NOT NULL REFERENCES Meta_Table(TableID),
    FactFKColumn   NVARCHAR(128) NOT NULL,       -- cột FK trên fact table
    DimPKColumn    NVARCHAR(128) NOT NULL,       -- cột PK trên dimension table
    JoinType       VARCHAR(10)   NOT NULL DEFAULT 'INNER'
                       CHECK (JoinType IN ('INNER', 'LEFT', 'RIGHT')),
    Cardinality    VARCHAR(10)   NOT NULL DEFAULT 'N:1'
                       CHECK (Cardinality IN ('1:1', 'N:1', 'N:M')),
    Description    NVARCHAR(500)
);
GO


-- -----------------------------------------------------------------------------
-- 1.5  OPERATIONAL METADATA — Nhật ký ETL (ETL Audit Log)
-- -----------------------------------------------------------------------------
-- Ghi lại mỗi lần chạy ETL: thời gian, số dòng, trạng thái, lỗi.
-- DurationSeconds là Computed Persisted Column — tính từ StartTime và EndTime.
-- BatchID nhóm các bước ETL thuộc cùng một lần chạy (pipeline run).
-- -----------------------------------------------------------------------------
CREATE TABLE Meta_ETL_Log (
    LogID            INT IDENTITY(1,1) PRIMARY KEY,
    TableID          INT           NOT NULL REFERENCES Meta_Table(TableID),
    ProcessName      NVARCHAR(256) NOT NULL,     -- tên job ETL / stored procedure
    StartTime        DATETIME      NOT NULL,
    EndTime          DATETIME,
    DurationSeconds  AS DATEDIFF(SECOND, StartTime, EndTime) PERSISTED,
    RowsExtracted    INT,
    RowsTransformed  INT,
    RowsLoaded       INT,
    RowsRejected     INT,
    Status           VARCHAR(20)   NOT NULL DEFAULT 'RUNNING'
                         CHECK (Status IN ('RUNNING', 'SUCCESS', 'FAILED', 'PARTIAL')),
    ErrorMessage     NVARCHAR(MAX),
    ExecutedBy       NVARCHAR(128) DEFAULT SYSTEM_USER,
    BatchID          UNIQUEIDENTIFIER DEFAULT NEWID()
);
GO


-- -----------------------------------------------------------------------------
-- 1.6  OPERATIONAL METADATA — Snapshot thống kê bảng (Table Statistics)
-- -----------------------------------------------------------------------------
-- Chụp số dòng và dung lượng của từng bảng sau mỗi lần ETL.
-- Dùng để theo dõi tăng trưởng dữ liệu và phát hiện bất thường.
-- -----------------------------------------------------------------------------
CREATE TABLE Meta_TableStats (
    StatID       INT IDENTITY(1,1) PRIMARY KEY,
    TableID      INT      NOT NULL REFERENCES Meta_Table(TableID),
    SnapshotTime DATETIME NOT NULL DEFAULT GETDATE(),
    TotalRows    BIGINT,
    DataSizeMB   DECIMAL(10,2),
    IndexSizeMB  DECIMAL(10,2)
);
GO


-- =============================================================================
-- PHẦN 2 — NẠP DỮ LIỆU METADATA (Populate Metadata Repository)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 2.1  TECHNICAL METADATA — Nạp danh mục bảng
-- -----------------------------------------------------------------------------
INSERT INTO Meta_Table
    (SchemaName, TableName, TableType, PrimaryKeyColumn,
     GrainDescription, RefreshPolicy, SourceSystem, Owner, TechnicalNotes)
VALUES
-- Dimension: Dim_Time
('dbo', 'Dim_Time',
 'DIMENSION', 'TimeID',
 'Mỗi dòng đại diện cho một tháng cụ thể (YYYYMM). Độ hạt: tháng.',
 'FULL_RELOAD',
 'Generated (calendar)',
 'Data Engineering Team',
 'Phân cấp thời gian: Month → Quarter → Year. Không có cấp Day.'),

-- Dimension: Dim_Customer
('dbo', 'Dim_Customer',
 'DIMENSION', 'CustomerID',
 'Mỗi dòng là một khách hàng duy nhất. Độ hạt: khách hàng.',
 'SCD_TYPE2',
 'CRM System',
 'Data Engineering Team',
 'LoaiKH: KL = Khách lẻ, KB = Khách buôn. Áp dụng SCD Type 2 khi LoaiKH hoặc ThanhPho thay đổi.'),

-- Dimension: Dim_Product
('dbo', 'Dim_Product',
 'DIMENSION', 'ProductID',
 'Mỗi dòng là một sản phẩm duy nhất. Độ hạt: sản phẩm.',
 'INCREMENTAL',
 'ERP / Product Catalog',
 'Data Engineering Team',
 'Gia là giá niêm yết tại thời điểm ETL — không dùng để tính doanh thu thực tế trên fact.'),

-- Fact: Fact_Sales
('dbo', 'Fact_Sales',
 'FACT', 'SalesID',
 'Mỗi dòng là một giao dịch bán hàng (Khách hàng × Sản phẩm × Tháng). Độ hạt: giao dịch.',
 'APPEND_ONLY',
 'Sales Transaction System',
 'Data Engineering Team',
 'SalesID là Surrogate Key (IDENTITY). Chỉ APPEND — không xoá dữ liệu cũ. 3 FK: CustomerID, ProductID, TimeID.');
GO


-- -----------------------------------------------------------------------------
-- 2.2  TECHNICAL METADATA — Nạp danh mục cột
-- -----------------------------------------------------------------------------
DECLARE @tidTime     INT = (SELECT TableID FROM Meta_Table WHERE TableName = 'Dim_Time');
DECLARE @tidCustomer INT = (SELECT TableID FROM Meta_Table WHERE TableName = 'Dim_Customer');
DECLARE @tidProduct  INT = (SELECT TableID FROM Meta_Table WHERE TableName = 'Dim_Product');
DECLARE @tidFact     INT = (SELECT TableID FROM Meta_Table WHERE TableName = 'Fact_Sales');

-- ── Dim_Time ──────────────────────────────────────────────────────────────────
INSERT INTO Meta_Column
    (TableID, ColumnName, DataType, IsNullable, ColumnRole,
     BusinessName, BusinessDesc, SourceColumn, SampleValues, SortOrder)
VALUES
(@tidTime, 'TimeID',  'INT', 0, 'PK',
 'Mã thời gian',  'Khoá chính dạng YYYYMM. VD: 202501 = tháng 1/2025.',
 'N/A', '202401, 202406, 202412', 1),

(@tidTime, 'Year',    'INT', 0, 'ATTRIBUTE',
 'Năm', 'Năm dương lịch.',
 'YEAR(date)', '2023, 2024, 2025', 2),

(@tidTime, 'Quarter', 'INT', 0, 'ATTRIBUTE',
 'Quý', 'Quý trong năm (1–4).',
 'QUARTER(date)', '1, 2, 3, 4', 3),

(@tidTime, 'Month',   'INT', 0, 'ATTRIBUTE',
 'Tháng', 'Tháng trong năm (1–12).',
 'MONTH(date)', '1, 6, 12', 4);

-- ── Dim_Customer ──────────────────────────────────────────────────────────────
INSERT INTO Meta_Column
    (TableID, ColumnName, DataType, MaxLength, IsNullable, ColumnRole,
     BusinessName, BusinessDesc, SourceColumn, SampleValues, SortOrder)
VALUES
(@tidCustomer, 'CustomerID', 'VARCHAR', 20,  0, 'PK',
 'Mã khách hàng',  'Khoá chính — mã nghiệp vụ từ CRM.',
 'CUSTOMER_ID', 'KH001, KH002', 1),

(@tidCustomer, 'TenKH',      'NVARCHAR', 150, 1, 'ATTRIBUTE',
 'Tên khách hàng', 'Tên đầy đủ của khách hàng.',
 'CUSTOMER_NAME', 'Nguyễn Văn A', 2),

(@tidCustomer, 'LoaiKH',     'CHAR', 2, 0, 'ATTRIBUTE',
 'Loại khách', 'KL = Khách lẻ (mua tiêu dùng cá nhân), KB = Khách buôn (mua sỉ để phân phối).',
 'CUSTOMER_TYPE', 'KL, KB', 3),

(@tidCustomer, 'ThanhPho',   'NVARCHAR', 100, 1, 'ATTRIBUTE',
 'Thành phố', 'Thành phố / tỉnh nơi khách hàng đăng ký.',
 'CITY', 'Hà Nội, TP.HCM, Đà Nẵng', 4);

-- ── Dim_Product ───────────────────────────────────────────────────────────────
INSERT INTO Meta_Column
    (TableID, ColumnName, DataType, MaxLength, Precision, Scale, IsNullable, ColumnRole,
     BusinessName, BusinessDesc, SourceColumn, SampleValues, SortOrder)
VALUES
(@tidProduct, 'ProductID', 'VARCHAR',  50,   NULL, NULL, 0, 'PK',
 'Mã sản phẩm',    'Khoá chính — mã nghiệp vụ từ ERP.',
 'PRODUCT_ID', 'SP001, SP010', 1),

(@tidProduct, 'MoTa',      'NVARCHAR', 255,  NULL, NULL, 1, 'ATTRIBUTE',
 'Mô tả sản phẩm', 'Tên / mô tả đầy đủ của sản phẩm.',
 'PRODUCT_DESC', 'Gạo ST25 5kg', 2),

(@tidProduct, 'Size',      'VARCHAR',  50,   NULL, NULL, 1, 'ATTRIBUTE',
 'Quy cách',       'Quy cách đóng gói hoặc kích thước (VD: 5kg, 10kg, L, XL).',
 'SIZE', '5kg, 10kg, M, L', 3),

(@tidProduct, 'Weight',    'DECIMAL',  NULL, 10,   2,    1, 'ATTRIBUTE',
 'Trọng lượng',    'Trọng lượng sản phẩm (đơn vị: kg).',
 'WEIGHT_KG', '5.00, 10.00', 4),

(@tidProduct, 'Gia',       'DECIMAL',  NULL, 15,   2,    1, 'ATTRIBUTE',
 'Giá niêm yết',   'Giá niêm yết tại thời điểm ETL (VND). Không dùng để tính doanh thu thực tế.',
 'LIST_PRICE', '150000.00', 5);

-- ── Fact_Sales ────────────────────────────────────────────────────────────────
INSERT INTO Meta_Column
    (TableID, ColumnName, DataType, MaxLength, Precision, Scale, IsNullable, ColumnRole,
     BusinessName, BusinessDesc, SourceColumn, SampleValues, SortOrder)
VALUES
(@tidFact, 'SalesID',     'INT',     NULL, NULL, NULL, 0, 'SURROGATE_KEY',
 'Mã giao dịch',  'Surrogate Key sinh tự động (IDENTITY). Không có nghĩa nghiệp vụ.',
 'N/A', '1, 2, 3', 1),

(@tidFact, 'CustomerID',  'VARCHAR', 20,   NULL, NULL, 0, 'FK',
 'Mã khách hàng', 'Khoá ngoại → Dim_Customer.CustomerID.',
 'CUSTOMER_ID', 'KH001', 2),

(@tidFact, 'ProductID',   'VARCHAR', 50,   NULL, NULL, 0, 'FK',
 'Mã sản phẩm',   'Khoá ngoại → Dim_Product.ProductID.',
 'PRODUCT_ID', 'SP001', 3),

(@tidFact, 'TimeID',      'INT',     NULL, NULL, NULL, 0, 'FK',
 'Mã thời gian',  'Khoá ngoại → Dim_Time.TimeID (YYYYMM).',
 'ORDER_DATE', '202401', 4),

(@tidFact, 'Quantity',    'INT',     NULL, NULL, NULL, 0, 'MEASURE',
 'Số lượng',      'Số lượng sản phẩm trong giao dịch.',
 'QTY', '10, 50, 200', 5),

(@tidFact, 'Price',       'DECIMAL', NULL, 15,   2,    0, 'MEASURE',
 'Đơn giá',       'Đơn giá thực tế tại thời điểm giao dịch (VND). Có thể khác Dim_Product.Gia.',
 'UNIT_PRICE', '148000.00', 6),

(@tidFact, 'TotalAmount', 'DECIMAL', NULL, 18,   2,    0, 'MEASURE',
 'Tổng tiền',     'Doanh thu giao dịch = Quantity × Price (VND). Measure chính của kho.',
 'TOTAL_AMOUNT', '1480000.00', 7);
GO


-- -----------------------------------------------------------------------------
-- 2.3  TECHNICAL METADATA — Nạp quan hệ Star Schema
-- -----------------------------------------------------------------------------
-- Fact_Sales → Dim_Time
INSERT INTO Meta_Relationship
    (FactTableID, DimTableID, FactFKColumn, DimPKColumn, JoinType, Cardinality, Description)
SELECT f.TableID, d.TableID,
       'TimeID', 'TimeID', 'INNER', 'N:1',
       'Mỗi giao dịch thuộc về một tháng duy nhất. JOIN: Fact_Sales.TimeID = Dim_Time.TimeID'
FROM Meta_Table f, Meta_Table d
WHERE f.TableName = 'Fact_Sales' AND d.TableName = 'Dim_Time';

-- Fact_Sales → Dim_Customer
INSERT INTO Meta_Relationship
    (FactTableID, DimTableID, FactFKColumn, DimPKColumn, JoinType, Cardinality, Description)
SELECT f.TableID, d.TableID,
       'CustomerID', 'CustomerID', 'INNER', 'N:1',
       'Mỗi giao dịch được thực hiện bởi một khách hàng. JOIN: Fact_Sales.CustomerID = Dim_Customer.CustomerID'
FROM Meta_Table f, Meta_Table d
WHERE f.TableName = 'Fact_Sales' AND d.TableName = 'Dim_Customer';

-- Fact_Sales → Dim_Product
INSERT INTO Meta_Relationship
    (FactTableID, DimTableID, FactFKColumn, DimPKColumn, JoinType, Cardinality, Description)
SELECT f.TableID, d.TableID,
       'ProductID', 'ProductID', 'INNER', 'N:1',
       'Mỗi giao dịch bán một loại sản phẩm. JOIN: Fact_Sales.ProductID = Dim_Product.ProductID'
FROM Meta_Table f, Meta_Table d
WHERE f.TableName = 'Fact_Sales' AND d.TableName = 'Dim_Product';
GO


-- -----------------------------------------------------------------------------
-- 2.4  BUSINESS METADATA — Từ điển nghiệp vụ
-- -----------------------------------------------------------------------------
INSERT INTO Meta_BusinessGlossary (Term, Definition, Category, Owner, RelatedTerms)
VALUES

('Doanh thu',
 'Tổng tiền thu được từ các giao dịch bán hàng trong kỳ. '
 + 'Công thức: SUM(TotalAmount). KPI chính được theo dõi ở cấp tháng, quý, năm.',
 'KPI', 'Business Analyst', 'TotalAmount, Quantity, Price'),

('Grain (Độ hạt)',
 'Mức chi tiết nhỏ nhất mà một dòng trong fact table đại diện. '
 + 'Fact_Sales grain = (Khách hàng × Sản phẩm × Tháng). '
 + 'Xác định grain là bước bắt buộc trong Dimensional Modeling (Kimball).',
 'Policy', 'Data Engineering Team', 'Fact_Sales, Dimensional Modeling'),

('Khách lẻ (KL)',
 'Khách hàng mua số lượng nhỏ cho tiêu dùng cá nhân. '
 + 'Mã hoá: LoaiKH = ''KL'' trong Dim_Customer.',
 'Dimension', 'Business Analyst', 'LoaiKH, Khách buôn'),

('Khách buôn (KB)',
 'Khách hàng mua số lượng lớn để phân phối lại (đại lý, nhà bán sỉ). '
 + 'Mã hoá: LoaiKH = ''KB'' trong Dim_Customer.',
 'Dimension', 'Business Analyst', 'LoaiKH, Khách lẻ'),

('SCD Type 2',
 'Slowly Changing Dimension Type 2 — kỹ thuật lưu lịch sử thay đổi của dimension '
 + 'bằng cách thêm dòng mới thay vì cập nhật dòng cũ. '
 + 'Dim_Customer áp dụng SCD Type 2 khi LoaiKH hoặc ThanhPho thay đổi.',
 'Policy', 'Data Engineering Team', 'Dim_Customer, RefreshPolicy'),

('Roll-Up',
 'Phép toán OLAP tổng hợp dữ liệu lên mức ít chi tiết hơn theo phân cấp chiều. '
 + 'VD: từ Month → Quarter → Year trên Dim_Time.',
 'KPI', 'Business Analyst', 'Drill-Down, Dim_Time, Phân cấp'),

('Drill-Down',
 'Phép toán OLAP trái ngược Roll-Up — đi sâu vào mức chi tiết hơn. '
 + 'VD: từ Year → Quarter → Month.',
 'KPI', 'Business Analyst', 'Roll-Up, Dim_Time, Phân cấp'),

('Slice',
 'Phép toán OLAP lọc cố định một giá trị trên một chiều duy nhất. '
 + 'VD: WHERE ThanhPho = ''Hà Nội'' (slice chiều khách hàng theo địa lý).',
 'KPI', 'Business Analyst', 'Dice, Dim_Customer'),

('Dice',
 'Phép toán OLAP lọc đồng thời nhiều chiều với một hoặc nhiều giá trị mỗi chiều. '
 + 'VD: WHERE Year = 2024 AND LoaiKH = ''KB'' AND ThanhPho IN (''Hà Nội'', ''TP.HCM'').',
 'KPI', 'Business Analyst', 'Slice, Dim_Customer, Dim_Time'),

('Pivot (Cross-tab)',
 'Phép toán OLAP xoay trục dữ liệu — chuyển giá trị của một chiều thành cột. '
 + 'VD: mỗi tháng thành một cột, dòng là sản phẩm, ô là SUM(TotalAmount).',
 'KPI', 'Business Analyst', 'Roll-Up, Dice');
GO


-- =============================================================================
-- PHẦN 3 — VIEW HỖ TRỢ TRUY VẤN METADATA
-- =============================================================================

-- View tổng hợp Data Dictionary: bảng + cột + nghiệp vụ
CREATE VIEW vw_DataDictionary AS
SELECT
    mt.TableType,
    mt.TableName,
    mt.GrainDescription,
    mc.SortOrder                                                 AS ColOrder,
    mc.ColumnName,
    mc.DataType
        + CASE
            WHEN mc.MaxLength  IS NOT NULL
                THEN '(' + CAST(mc.MaxLength  AS VARCHAR) + ')'
            WHEN mc.Precision  IS NOT NULL
                THEN '(' + CAST(mc.Precision  AS VARCHAR)
                  + ',' + CAST(mc.Scale       AS VARCHAR) + ')'
            ELSE ''
          END                                                     AS FullDataType,
    mc.ColumnRole,
    CASE mc.IsNullable WHEN 1 THEN 'NULL' ELSE 'NOT NULL' END    AS Nullability,
    mc.BusinessName,
    mc.BusinessDesc,
    mc.SourceColumn,
    mc.SampleValues
FROM Meta_Column mc
JOIN Meta_Table  mt ON mc.TableID = mt.TableID
WHERE mt.IsActive = 1;
GO

-- View Star Schema: toàn bộ quan hệ Fact → Dimension
CREATE VIEW vw_StarSchema AS
SELECT
    ft.TableName    AS FactTable,
    mr.FactFKColumn,
    mr.Cardinality,
    mr.JoinType,
    dt.TableName    AS DimensionTable,
    mr.DimPKColumn,
    mr.Description
FROM Meta_Relationship mr
JOIN Meta_Table ft ON mr.FactTableID = ft.TableID
JOIN Meta_Table dt ON mr.DimTableID  = dt.TableID;
GO


-- =============================================================================
-- PHẦN 4 — STORED PROCEDURE GHI NHẬT KÝ ETL
-- =============================================================================

-- sp_ETL_Begin: gọi đầu mỗi job ETL, trả về LogID để sp_ETL_End cập nhật.
CREATE PROCEDURE sp_ETL_Begin
    @TableName   NVARCHAR(128),
    @ProcessName NVARCHAR(256),
    @LogID       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TableID INT = (SELECT TableID FROM Meta_Table WHERE TableName = @TableName AND IsActive = 1);
    IF @TableID IS NULL
        THROW 50001, 'Table not found in Meta_Table or is inactive.', 1;

    INSERT INTO Meta_ETL_Log (TableID, ProcessName, StartTime, Status)
    VALUES (@TableID, @ProcessName, GETDATE(), 'RUNNING');

    SET @LogID = SCOPE_IDENTITY();
END;
GO

-- sp_ETL_End: gọi cuối mỗi job ETL để ghi số dòng và trạng thái.
CREATE PROCEDURE sp_ETL_End
    @LogID           INT,
    @RowsExtracted   INT,
    @RowsTransformed INT,
    @RowsLoaded      INT,
    @RowsRejected    INT,
    @Status          VARCHAR(20),   -- 'SUCCESS' | 'FAILED' | 'PARTIAL'
    @ErrorMessage    NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Meta_ETL_Log
    SET EndTime          = GETDATE(),
        RowsExtracted    = @RowsExtracted,
        RowsTransformed  = @RowsTransformed,
        RowsLoaded       = @RowsLoaded,
        RowsRejected     = @RowsRejected,
        Status           = @Status,
        ErrorMessage     = @ErrorMessage
    WHERE LogID = @LogID;
END;
GO


-- =============================================================================
-- PHẦN 5 — TRUY VẤN KIỂM TRA (Verification)
-- =============================================================================

-- Xem toàn bộ Data Dictionary:
-- SELECT * FROM vw_DataDictionary ORDER BY TableType, TableName, ColOrder;

-- Xem sơ đồ Star Schema:
-- SELECT * FROM vw_StarSchema;

-- Xem từ điển nghiệp vụ:
-- SELECT Term, Category, Definition FROM Meta_BusinessGlossary ORDER BY Category, Term;

-- Xem lịch sử ETL:
-- SELECT t.TableName, l.ProcessName, l.StartTime, l.DurationSeconds,
--        l.RowsLoaded, l.Status, l.ErrorMessage
-- FROM Meta_ETL_Log l
-- JOIN Meta_Table t ON l.TableID = t.TableID
-- ORDER BY l.StartTime DESC;
