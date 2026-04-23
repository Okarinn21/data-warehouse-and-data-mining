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
    TimeID INT IDENTITY(1,1) PRIMARY KEY,
    Month INT,
    Quarter INT,
    Year INT
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

-- FACT_INVENTORY
CREATE TABLE Fact_Inventory (
    InventoryID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID VARCHAR(50),
    TimeID INT,
    StockQuantity INT,

    FOREIGN KEY (ProductID) REFERENCES Dim_Product(ProductID),
    FOREIGN KEY (TimeID) REFERENCES Dim_Time(TimeID)
);


-- 4. INDEXES

-- FACT_SALES INDEXES
CREATE INDEX idx_sales_customer ON Fact_Sales(CustomerID);
CREATE INDEX idx_sales_product ON Fact_Sales(ProductID);
CREATE INDEX idx_sales_time ON Fact_Sales(TimeID);

-- FACT_INVENTORY INDEXES
CREATE INDEX idx_inventory_product ON Fact_Inventory(ProductID);
CREATE INDEX idx_inventory_time ON Fact_Inventory(TimeID);

-- DIMENSION INDEXES
CREATE INDEX idx_customer ON Dim_Customer(CustomerID);
CREATE INDEX idx_product ON Dim_Product(ProductID);
CREATE INDEX idx_time ON Dim_Time(TimeID);