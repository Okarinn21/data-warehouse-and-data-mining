USE DataWarehouse;
GO

-- 1. LOAD DIM_TIME
DECLARE @StartDate DATE = '2010-01-01';
DECLARE @EndDate DATE = '2035-12-01';

WITH Months AS (
    SELECT DATEFROMPARTS(YEAR(@StartDate), MONTH(@StartDate), 1) AS MonthStart
    UNION ALL
    SELECT DATEADD(MONTH, 1, MonthStart)
    FROM Months
    WHERE MonthStart < @EndDate
)
INSERT INTO Dim_Time (TimeID, Year, Quarter, Month)
SELECT 
    YEAR(MonthStart) * 100 + MONTH(MonthStart),
    YEAR(MonthStart),
    DATEPART(QUARTER, MonthStart),
    MONTH(MonthStart)
FROM Months
OPTION (MAXRECURSION 0);

-- 2. LOAD DIM_CUSTOMER
INSERT INTO Dim_Customer (CustomerID, TenKH, LoaiKH, ThanhPho)
SELECT 
    kh.MaKH,
    kh.TenKH,
    kh.LoaiKH,
    vp.TenTP
FROM DatabaseMock.dbo.KHACHHANG kh
LEFT JOIN DatabaseMock.dbo.VANPHONGDAIDIEN vp 
    ON kh.MaTP = vp.MaTP
WHERE NOT EXISTS (
    SELECT 1 
    FROM Dim_Customer dc
    WHERE dc.CustomerID = kh.MaKH
);

-- 3. LOAD DIM_PRODUCT
INSERT INTO Dim_Product (ProductID, MoTa, Size, Weight, Gia)
SELECT 
    MaMH,
    MoTa,
    KichCo,
    TrongLuong,
    Gia
FROM DatabaseMock.dbo.MATHANG m
WHERE NOT EXISTS (
    SELECT 1 
    FROM Dim_Product dp
    WHERE dp.ProductID = m.MaMH
);

-- 4. LOAD FACT_SALES
INSERT INTO Fact_Sales (
    CustomerID,
    ProductID,
    TimeID,
    Quantity,
    Price,
    TotalAmount
)
SELECT 
    ddh.MaKH,
    mhdd.MaMH,
    dt.TimeID,
    mhdd.SoLuongDat,
    mhdd.GiaDat,
    mhdd.SoLuongDat * mhdd.GiaDat
FROM DatabaseMock.dbo.MHDUOCDAT mhdd
JOIN DatabaseMock.dbo.DONDATHANG ddh 
    ON mhdd.MaDon = ddh.MaDon
JOIN Dim_Time dt
    ON dt.TimeID = YEAR(ddh.NgayDatHang) * 100 + MONTH(ddh.NgayDatHang)
WHERE NOT EXISTS (
    SELECT 1
    FROM Fact_Sales fs
    WHERE fs.CustomerID = ddh.MaKH
      AND fs.ProductID = mhdd.MaMH
      AND fs.TimeID = dt.TimeID
      AND fs.Quantity = mhdd.SoLuongDat
);
