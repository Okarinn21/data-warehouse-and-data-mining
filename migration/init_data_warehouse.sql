-- 1. DROP + CREATE DATABASE
IF DB_ID('DataWarehouse') IS NOT NULL
BEGIN
    ALTER DATABASE DataWarehouse SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DataWarehouse;
END;
GO

CREATE DATABASE DataWarehouse;
GO

USE DataWarehouse;
GO

-- 2. DIMENSION TABLES

-- DIM_TIME (chỉ Month, Quarter, Year)
CREATE TABLE Dim_Time (
    TimeID INT PRIMARY KEY,   -- YYYYMM
    Year INT,
    Quarter INT,
    Month INT
);


-- DIM_CUSTOMER
CREATE TABLE Dim_Customer (
    CustomerID VARCHAR(20) PRIMARY KEY,
    TenKH NVARCHAR(150),
    LoaiKH CHAR(2),
    ThanhPho NVARCHAR(100)
);

-- DIM_PRODUCT 
CREATE TABLE Dim_Product (
    ProductID VARCHAR(50) PRIMARY KEY,
    MoTa NVARCHAR(255),
    Size VARCHAR(50),
    Weight DECIMAL(10,2),
    Gia DECIMAL(15,2)
);


-- 3. FACT TABLES

-- FACT_SALES (chỉ measure: Price, Quantity, TotalAmount)
CREATE TABLE Fact_Sales (
    SalesID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID VARCHAR(20),
    ProductID VARCHAR(50),
    TimeID INT,

    Quantity INT,
    Price DECIMAL(15,2),
    TotalAmount DECIMAL(18,2),

    FOREIGN KEY (CustomerID) REFERENCES Dim_Customer(CustomerID),
    FOREIGN KEY (ProductID) REFERENCES Dim_Product(ProductID),
    FOREIGN KEY (TimeID) REFERENCES Dim_Time(TimeID)
);

-- 4. INDEXES

-- ── Fact_Sales ──────────────────────────────────────────────────────────
-- Lý thuyết Star Schema DW: mỗi FK trên fact table cần non-clustered covering index.
-- Key column = FK (dùng để JOIN từ dimension sang fact),
-- INCLUDE = measure columns (TotalAmount, Quantity) -> tránh key lookup khi aggregate.

CREATE INDEX idx_sales_time
    ON Fact_Sales(TimeID)
    INCLUDE (TotalAmount, Quantity);

CREATE INDEX idx_sales_customer
    ON Fact_Sales(CustomerID)
    INCLUDE (TotalAmount, Quantity);

CREATE INDEX idx_sales_product
    ON Fact_Sales(ProductID)
    INCLUDE (TotalAmount, Quantity);

-- Composite index cho Dice query lọc đồng thời nhiều chiều (TimeID range + FK join)
CREATE INDEX idx_sales_composite
    ON Fact_Sales(TimeID, CustomerID, ProductID)
    INCLUDE (TotalAmount, Quantity);

-- ── Dim_Time ────────────────────────────────────────────────────────────
-- PK (TimeID) đã có clustered index tự động -> không tạo thêm index riêng trên PK.
-- Composite index theo phân cấp thời gian để tối ưu GROUP BY Year/Quarter/Month
-- trong các phép Roll-Up / Drill-Down.

CREATE INDEX idx_time_hierarchy
    ON Dim_Time(Year, Quarter, Month)
    INCLUDE (TimeID);

-- ── Dim_Customer ────────────────────────────────────────────────────────
-- PK (CustomerID) đã có clustered index tự động -> không tạo thêm index riêng trên PK.
-- Index trên các cột filter thấp cardinality (LoaiKH) và trung bình (ThanhPho)
-- dùng trong mệnh đề WHERE của Slice / Dice.

CREATE INDEX idx_customer_city
    ON Dim_Customer(ThanhPho)
    INCLUDE (CustomerID, LoaiKH);

CREATE INDEX idx_customer_type
    ON Dim_Customer(LoaiKH)
    INCLUDE (CustomerID, ThanhPho);

-- ── Dim_Product ─────────────────────────────────────────────────────────
-- PK (ProductID) đã có clustered index tự động -> không tạo thêm index riêng trên PK.
-- Index trên MoTa để tối ưu filter / GROUP BY theo tên sản phẩm.

CREATE INDEX idx_product_desc
    ON Dim_Product(MoTa)
    INCLUDE (ProductID, Gia);