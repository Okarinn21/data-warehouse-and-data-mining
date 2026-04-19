USE DataWarehouse;
GO

-- 1. STAGING TABLE
DROP TABLE IF EXISTS STG_OnlineRetail;

CREATE TABLE STG_OnlineRetail (
    InvoiceNo VARCHAR(20),
    StockCode VARCHAR(50),
    Description NVARCHAR(255),
    Quantity VARCHAR(50),
    InvoiceDate VARCHAR(50),
    UnitPrice VARCHAR(50),
    CustomerID VARCHAR(20),
    Country NVARCHAR(100)
);

-- 2. BULK INSERT
BULK INSERT STG_OnlineRetail
FROM 'D:\Code\PTIT\data-warehouse-and-data-mining\mock_data.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIELDQUOTE = '"',
    CODEPAGE = '65001',
    TABLOCK
);

-- 3. CLEAN DATA
DELETE FROM STG_OnlineRetail
WHERE TRY_CAST(Quantity AS INT) IS NULL
   OR TRY_CAST(UnitPrice AS DECIMAL(10,2)) IS NULL;

UPDATE STG_OnlineRetail
SET CustomerID = 'UNKNOWN'
WHERE CustomerID IS NULL;

-- 4. DIMENSION TABLES

-- VANPHONGDAIDIEN
INSERT INTO VANPHONGDAIDIEN (MaTP, TenTP, DiaChiVP, Bang, ThoiGianThanhLap)
SELECT 
    s.Country,
    s.Country,
    'Unknown',
    s.Country,
    MIN(TRY_CONVERT(DATETIME, s.InvoiceDate))
FROM STG_OnlineRetail s
LEFT JOIN VANPHONGDAIDIEN v 
    ON v.MaTP = s.Country
WHERE v.MaTP IS NULL
GROUP BY s.Country;

-- CUAHANG (SAFE KEY)
INSERT INTO CUAHANG (MaCH, MaTP, SoDienThoai, ThoiGianMoCua)
SELECT 
    'CH_' + CAST(ABS(CHECKSUM(s.Country)) AS VARCHAR(20)),   -- 🔥 safe unique key
    s.Country,
    '0000000000',
    MIN(TRY_CONVERT(DATETIME, s.InvoiceDate))
FROM STG_OnlineRetail s
LEFT JOIN CUAHANG c 
    ON c.MaTP = s.Country
WHERE c.MaTP IS NULL
GROUP BY s.Country;

-- KHACHHANG (FIXED GROUPING)
INSERT INTO KHACHHANG (MaKH, TenKH, MaTP, NgayDatHangDau, LoaiKH)
SELECT 
    s.CustomerID,
    'Customer ' + s.CustomerID,
    MAX(s.Country),
    MIN(TRY_CONVERT(DATETIME, s.InvoiceDate)),
    'CA'
FROM STG_OnlineRetail s
LEFT JOIN KHACHHANG k 
    ON k.MaKH = s.CustomerID
WHERE k.MaKH IS NULL
GROUP BY s.CustomerID;

-- MATHANG
INSERT INTO MATHANG (MaMH, MoTa, KichCo, TrongLuong, Gia, ThoiGianNhapHang)
SELECT 
    s.StockCode,
    MAX(s.Description),
    'Unknown',
    0,
    AVG(TRY_CAST(s.UnitPrice AS DECIMAL(10,2))),
    MIN(TRY_CONVERT(DATETIME, s.InvoiceDate))
FROM STG_OnlineRetail s
LEFT JOIN MATHANG m 
    ON m.MaMH = s.StockCode
WHERE m.MaMH IS NULL
GROUP BY s.StockCode;

-- 5. FACT TABLES

-- DONDATHANG
INSERT INTO DONDATHANG (MaDon, NgayDatHang, MaKH)
SELECT 
    s.InvoiceNo,
    MIN(TRY_CONVERT(DATETIME, s.InvoiceDate)),
    MAX(s.CustomerID)
FROM STG_OnlineRetail s
LEFT JOIN DONDATHANG d 
    ON d.MaDon = s.InvoiceNo
WHERE d.MaDon IS NULL
GROUP BY s.InvoiceNo;

-- MHDUOCDAT (AGGREGATED)
INSERT INTO MHDUOCDAT (MaDon, MaMH, SoLuongDat, GiaDat, ThoiGianDatHang)
SELECT 
    s.InvoiceNo,
    s.StockCode,
    SUM(TRY_CAST(s.Quantity AS INT)),
    AVG(TRY_CAST(s.UnitPrice AS DECIMAL(10,2))),
    MAX(TRY_CONVERT(DATETIME, s.InvoiceDate))
FROM STG_OnlineRetail s
LEFT JOIN MHDUOCDAT d 
    ON d.MaDon = s.InvoiceNo AND d.MaMH = s.StockCode
WHERE d.MaDon IS NULL
GROUP BY s.InvoiceNo, s.StockCode;

-- MHLUUTRU
INSERT INTO MHLUUTRU (MaCH, MaMH, SoLuongTon, ThoiGianLuuTru)
SELECT
    c.MaCH,
    s.StockCode,
    SUM(TRY_CAST(s.Quantity AS INT)),
    MAX(TRY_CONVERT(DATETIME, s.InvoiceDate))
FROM STG_OnlineRetail s
JOIN CUAHANG c ON c.MaTP = s.Country
LEFT JOIN MHLUUTRU m 
    ON m.MaCH = c.MaCH AND m.MaMH = s.StockCode
WHERE m.MaCH IS NULL
GROUP BY c.MaCH, s.StockCode;

-- 6. CHECK
SELECT COUNT(*) AS STG FROM STG_OnlineRetail;
SELECT COUNT(*) AS KH FROM KHACHHANG;
SELECT COUNT(*) AS DON FROM DONDATHANG;
SELECT COUNT(*) AS CT FROM MHDUOCDAT;

-- 7. SAMPLE
SELECT TOP 20 *,
    CASE 
        WHEN TRY_CAST(Quantity AS INT) > 0 THEN 'SALE'
        ELSE 'RETURN'
    END AS TransactionType
FROM STG_OnlineRetail;