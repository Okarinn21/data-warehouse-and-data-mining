-- USE DATA WAREHOUSE
USE DataWarehouse;
GO

-- 1. LOAD DIM_TIME
INSERT INTO Dim_Time (TimeID, Day, Month, Quarter, Year)
SELECT DISTINCT
    d.NgayDatHang,
    DAY(d.NgayDatHang),
    MONTH(d.NgayDatHang),
    DATEPART(QUARTER, d.NgayDatHang),
    YEAR(d.NgayDatHang)
FROM DatabaseMock.dbo.DONDATHANG d
WHERE d.NgayDatHang IS NOT NULL
AND d.NgayDatHang NOT IN (
    SELECT TimeID FROM Dim_Time
);

-- 2. LOAD DIM_CUSTOMER
INSERT INTO Dim_Customer (
    CustomerID,
    TenKH,
    LoaiKH,
    HuongDanVien,
    DiaChiBuuDien,
    ThanhPho
)
SELECT 
    kh.MaKH,
    kh.TenKH,
    kh.LoaiKH,
    dl.HuongDanVien,
    bd.DiaChiBuuDien,
    vp.TenTP
FROM DatabaseMock.dbo.KHACHHANG kh
LEFT JOIN DatabaseMock.dbo.KHACHHANG_DULICH dl 
    ON kh.MaKH = dl.MaKH
LEFT JOIN DatabaseMock.dbo.KHACHHANG_BUUDIEN bd 
    ON kh.MaKH = bd.MaKH
LEFT JOIN DatabaseMock.dbo.VANPHONGDAIDIEN vp
    ON kh.MaTP = vp.MaTP;


-- 3. LOAD DIM_PRODUCT
INSERT INTO Dim_Product (
    ProductID,
    MoTa,
    KichCo,
    TrongLuong,
    Gia
)
SELECT 
    mh.MaMH,
    mh.MoTa,
    mh.KichCo,
    mh.TrongLuong,
    mh.Gia
FROM DatabaseMock.dbo.MATHANG mh;


-- 4. LOAD DIM_STORE
INSERT INTO Dim_Store (
    StoreID,
    SoDienThoai,
    ThanhPho,
    Bang
)
SELECT 
    ch.MaCH,
    ch.SoDienThoai,
    vp.TenTP,
    vp.Bang
FROM DatabaseMock.dbo.CUAHANG ch
JOIN DatabaseMock.dbo.VANPHONGDAIDIEN vp
    ON ch.MaTP = vp.MaTP;


-- 5. LOAD FACT_SALES
DECLARE @BatchSize INT = 10000;

WHILE 1=1
BEGIN
    ;WITH SourceData AS (
        SELECT TOP (@BatchSize)
            md.MaDon,
            dh.MaKH,
            md.MaMH,
            ml.MaCH,
            dh.NgayDatHang,
            md.SoLuongDat,
            md.GiaDat
        FROM DatabaseMock.dbo.MHDUOCDAT md
        JOIN DatabaseMock.dbo.DONDATHANG dh 
            ON md.MaDon = dh.MaDon
        JOIN DatabaseMock.dbo.MHLUUTRU ml 
            ON md.MaMH = ml.MaMH
        WHERE dh.NgayDatHang IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 
            FROM Fact_Sales fs
            WHERE fs.OrderID = md.MaDon
              AND fs.ProductID = md.MaMH
        )
    )

    INSERT INTO Fact_Sales (
        OrderID,
        CustomerID,
        ProductID,
        StoreID,
        TimeID,
        Quantity,
        Price,
        TotalAmount
    )
    SELECT 
        MaDon,
        MaKH,
        MaMH,
        MaCH,
        NgayDatHang,
        SoLuongDat,
        GiaDat,
        SoLuongDat * GiaDat
    FROM SourceData;

    IF @@ROWCOUNT = 0 BREAK;

    CHECKPOINT; 
END

-- 6. LOAD FACT_INVENTORY
INSERT INTO Fact_Inventory (
    ProductID,
    StoreID,
    TimeID,
    StockQuantity
)
SELECT 
    mhlt.MaMH,
    mhlt.MaCH,
    CAST(mhlt.ThoiGianLuuTru AS DATE),
    mhlt.SoLuongTon
FROM DatabaseMock.dbo.MHLUUTRU mhlt;