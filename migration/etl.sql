USE DataWarehouse;
GO

-- 1. LOAD DIM_TIME
INSERT INTO Dim_Time (Month, Quarter, Year)
SELECT DISTINCT
    MONTH(NgayDatHang),
    DATEPART(QUARTER, NgayDatHang),
    YEAR(NgayDatHang)
FROM DatabaseMock.dbo.DONDATHANG d
WHERE NgayDatHang IS NOT NULL
AND NOT EXISTS (
    SELECT 1 
    FROM Dim_Time t
    WHERE t.Month = MONTH(d.NgayDatHang)
      AND t.Quarter = DATEPART(QUARTER, d.NgayDatHang)
      AND t.Year = YEAR(d.NgayDatHang)
);

-- thêm thời gian từ tồn kho luôn (nếu chưa có)
INSERT INTO Dim_Time (Month, Quarter, Year)
SELECT DISTINCT
    MONTH(ThoiGianLuuTru),
    DATEPART(QUARTER, ThoiGianLuuTru),
    YEAR(ThoiGianLuuTru)
FROM DatabaseMock.dbo.MHLUUTRU m
WHERE ThoiGianLuuTru IS NOT NULL
AND NOT EXISTS (
    SELECT 1 
    FROM Dim_Time t
    WHERE t.Month = MONTH(m.ThoiGianLuuTru)
      AND t.Quarter = DATEPART(QUARTER, m.ThoiGianLuuTru)
      AND t.Year = YEAR(m.ThoiGianLuuTru)
);

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
    ON dt.Month = MONTH(ddh.NgayDatHang)
   AND dt.Quarter = DATEPART(QUARTER, ddh.NgayDatHang)
   AND dt.Year = YEAR(ddh.NgayDatHang)
WHERE NOT EXISTS (
    SELECT 1
    FROM Fact_Sales fs
    WHERE fs.CustomerID = ddh.MaKH
      AND fs.ProductID = mhdd.MaMH
      AND fs.TimeID = dt.TimeID
      AND fs.Quantity = mhdd.SoLuongDat
);

-- 5. LOAD FACT_INVENTORY
INSERT INTO Fact_Inventory (
    ProductID,
    TimeID,
    StockQuantity
)
SELECT 
    mhlt.MaMH,
    dt.TimeID,
    mhlt.SoLuongTon
FROM DatabaseMock.dbo.MHLUUTRU mhlt
JOIN Dim_Time dt
    ON dt.Month = MONTH(mhlt.ThoiGianLuuTru)
   AND dt.Quarter = DATEPART(QUARTER, mhlt.ThoiGianLuuTru)
   AND dt.Year = YEAR(mhlt.ThoiGianLuuTru)
WHERE NOT EXISTS (
    SELECT 1
    FROM Fact_Inventory fi
    WHERE fi.ProductID = mhlt.MaMH
      AND fi.TimeID = dt.TimeID
);