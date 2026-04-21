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

-- DIM_TIME
CREATE TABLE Dim_Time (
    TimeID DATE PRIMARY KEY,
    Day INT,
    Month INT,
    Quarter INT,
    Year INT
);

-- DIM_CUSTOMER
CREATE TABLE Dim_Customer (
    CustomerID VARCHAR(20) PRIMARY KEY,
    TenKH NVARCHAR(150),
    LoaiKH CHAR(2),
    HuongDanVien NVARCHAR(150),
    DiaChiBuuDien NVARCHAR(200),
    ThanhPho NVARCHAR(100)
);

-- DIM_PRODUCT
CREATE TABLE Dim_Product (
    ProductID VARCHAR(50) PRIMARY KEY,
    MoTa NVARCHAR(255),
    KichCo VARCHAR(50),
    TrongLuong DECIMAL(10,2),
    Gia DECIMAL(15,2)
);

-- DIM_STORE
CREATE TABLE Dim_Store (
    StoreID VARCHAR(100) PRIMARY KEY,
    SoDienThoai VARCHAR(20),
    ThanhPho NVARCHAR(100),
    Bang NVARCHAR(100)
);


-- 3. FACT TABLES

-- FACT_SALES
CREATE TABLE Fact_Sales (
    SalesID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID VARCHAR(20),
    CustomerID VARCHAR(20),
    ProductID VARCHAR(50),
    StoreID VARCHAR(100),
    TimeID DATE,
    Quantity INT,
    Price DECIMAL(15,2),
    TotalAmount DECIMAL(18,2),

    FOREIGN KEY (CustomerID) REFERENCES Dim_Customer(CustomerID),
    FOREIGN KEY (ProductID) REFERENCES Dim_Product(ProductID),
    FOREIGN KEY (StoreID) REFERENCES Dim_Store(StoreID),
    FOREIGN KEY (TimeID) REFERENCES Dim_Time(TimeID)
);

-- FACT_INVENTORY
CREATE TABLE Fact_Inventory (
    InventoryID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID VARCHAR(50),
    StoreID VARCHAR(100),
    TimeID DATE,
    StockQuantity INT,

    CONSTRAINT FK_FI_PRODUCT FOREIGN KEY (ProductID)
        REFERENCES Dim_Product(ProductID),

    CONSTRAINT FK_FI_STORE FOREIGN KEY (StoreID)
        REFERENCES Dim_Store(StoreID),

    CONSTRAINT FK_FI_TIME FOREIGN KEY (TimeID)
        REFERENCES Dim_Time(TimeID)
);


-- 4. INDEXES

-- FACT_SALES INDEXES
CREATE INDEX idx_sales_customer ON Fact_Sales(CustomerID);
CREATE INDEX idx_sales_product ON Fact_Sales(ProductID);
CREATE INDEX idx_sales_time ON Fact_Sales(TimeID);
CREATE INDEX idx_sales_store ON Fact_Sales(StoreID);

CREATE INDEX idx_sales_multi
ON Fact_Sales(ProductID, TimeID, StoreID);

-- FACT_INVENTORY INDEXES
CREATE INDEX idx_inventory_product ON Fact_Inventory(ProductID);
CREATE INDEX idx_inventory_store ON Fact_Inventory(StoreID);

-- DIMENSION INDEXES
CREATE INDEX idx_customer ON Dim_Customer(CustomerID);
CREATE INDEX idx_product ON Dim_Product(ProductID);
CREATE INDEX idx_store ON Dim_Store(StoreID);
CREATE INDEX idx_time ON Dim_Time(TimeID);