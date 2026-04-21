USE DatabaseMock;
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

-- 4. CREATE CITIES
DROP TABLE IF EXISTS TMP_CITY;

SELECT DISTINCT
    Country,
    Country + '_City1' AS City1,
    Country + '_City2' AS City2,
    Country + '_City3' AS City3
INTO TMP_CITY
FROM STG_OnlineRetail;

-- 5. VANPHONGDAIDIEN
INSERT INTO VANPHONGDAIDIEN (MaTP, TenTP, DiaChiVP, Bang, ThoiGianThanhLap)
SELECT City, City, 'Unknown', Country, GETDATE()
FROM (
    SELECT Country, City1 AS City FROM TMP_CITY
    UNION
    SELECT Country, City2 FROM TMP_CITY
    UNION
    SELECT Country, City3 FROM TMP_CITY
) t;

-- 6. CUAHANG
INSERT INTO CUAHANG (MaCH, MaTP, SoDienThoai, ThoiGianMoCua)
SELECT 
    'CH_' + City + '_' + CAST(n AS VARCHAR),
    City,
    '0000000000',
    GETDATE()
FROM (
    SELECT City FROM (
        SELECT City1 AS City FROM TMP_CITY
        UNION
        SELECT City2 FROM TMP_CITY
        UNION
        SELECT City3 FROM TMP_CITY
    ) x
) c
CROSS JOIN (VALUES (1),(2),(3)) AS nums(n);

-- 7. KHACHHANG

-- 7.1 Ensure UNKNOWN exists
IF NOT EXISTS (SELECT 1 FROM KHACHHANG WHERE MaKH = 'UNKNOWN')
BEGIN
    INSERT INTO KHACHHANG (MaKH, TenKH, MaTP, NgayDatHangDau, LoaiKH)
    VALUES ('UNKNOWN', 'Unknown Customer', NULL, NULL, 'UN');
END

-- 7.2 Insert real customers only
INSERT INTO KHACHHANG (MaKH, TenKH, MaTP, NgayDatHangDau, LoaiKH)
SELECT 
    s.CustomerID,
    'Customer ' + s.CustomerID,

    MAX(s.Country) + '_City' + 
        CAST(ABS(CHECKSUM(s.CustomerID)) % 3 + 1 AS VARCHAR),

    MIN(TRY_CONVERT(DATETIME, s.InvoiceDate)),
    'CA'
FROM STG_OnlineRetail s
LEFT JOIN KHACHHANG k 
    ON k.MaKH = s.CustomerID
WHERE k.MaKH IS NULL
  AND s.CustomerID <> 'UNKNOWN'
GROUP BY s.CustomerID;

-- 8. CUSTOMER TYPE TABLES
DROP TABLE IF EXISTS TMP_GUIDES;

CREATE TABLE TMP_GUIDES (
    GuideID INT IDENTITY(1,1),
    GuideName NVARCHAR(100)
);

INSERT INTO TMP_GUIDES (GuideName)
VALUES
('Guide A'),('Guide B'),('Guide C'),('Guide D'),('Guide E'),
('Guide F'),('Guide G'),('Guide H'),('Guide I'),('Guide J'),
('Guide K'),('Guide L'),('Guide M'),('Guide N'),('Guide O'),
('Guide P'),('Guide Q'),('Guide R'),('Guide S'),('Guide T');

INSERT INTO KHACHHANG_DULICH (MaKH, HuongDanVien, ThoiGianCuTru)
SELECT 
    k.MaKH,
    g.GuideName,
    DATEADD(DAY, ABS(CHECKSUM(k.MaKH)) % 365, '2022-01-01')
FROM KHACHHANG k
JOIN TMP_GUIDES g 
    ON g.GuideID = (ABS(CHECKSUM(k.MaKH)) % 20) + 1
WHERE ABS(CHECKSUM(k.MaKH)) % 10 < 6
  AND k.MaKH <> 'UNKNOWN';

INSERT INTO KHACHHANG_BUUDIEN (MaKH, DiaChiBuuDien, ThoiGianNhanHang)
SELECT 
    k.MaKH,
    'Address_' + k.MaKH,
    DATEADD(DAY, ABS(CHECKSUM(k.MaKH)) % 365, '2022-01-01')
FROM KHACHHANG k
WHERE ABS(CHECKSUM(k.MaKH)) % 10 >= 4
  AND k.MaKH <> 'UNKNOWN';

-- 9. MATHANG
INSERT INTO MATHANG (MaMH, MoTa, KichCo, TrongLuong, Gia, ThoiGianNhapHang)
SELECT 
    s.StockCode,
    MAX(s.Description),
    'Unknown',
    0,
    AVG(TRY_CAST(s.UnitPrice AS DECIMAL(10,2))),
    MIN(TRY_CONVERT(DATETIME, s.InvoiceDate))
FROM STG_OnlineRetail s
GROUP BY s.StockCode;

-- 10. DONDATHANG (SAFE FK)
INSERT INTO DONDATHANG (MaDon, NgayDatHang, MaKH)
SELECT 
    s.InvoiceNo,
    MIN(TRY_CONVERT(DATETIME, s.InvoiceDate)),
    MAX(CASE 
        WHEN s.CustomerID = 'UNKNOWN' THEN 'UNKNOWN'
        ELSE s.CustomerID
    END)
FROM STG_OnlineRetail s
GROUP BY s.InvoiceNo;

-- 11. MHDUOCDAT
INSERT INTO MHDUOCDAT (MaDon, MaMH, SoLuongDat, GiaDat, ThoiGianDatHang)
SELECT 
    s.InvoiceNo,
    s.StockCode,
    SUM(TRY_CAST(s.Quantity AS INT)),
    AVG(TRY_CAST(s.UnitPrice AS DECIMAL(10,2))),
    MAX(TRY_CONVERT(DATETIME, s.InvoiceDate))
FROM STG_OnlineRetail s
GROUP BY s.InvoiceNo, s.StockCode;

-- 12. MHLUUTRU (FIXED DISTRIBUTION)
INSERT INTO MHLUUTRU (MaCH, MaMH, SoLuongTon, ThoiGianLuuTru)
SELECT
    c.MaCH,
    s.StockCode,
    SUM(TRY_CAST(s.Quantity AS INT)),
    GETDATE()
FROM STG_OnlineRetail s
JOIN CUAHANG c 
    ON c.MaTP = s.Country + '_City' + 
       CAST(ABS(CHECKSUM(s.InvoiceNo)) % 3 + 1 AS VARCHAR)
GROUP BY c.MaCH, s.StockCode;

-- 13. CHECK
SELECT COUNT(*) AS STG FROM STG_OnlineRetail;
SELECT COUNT(*) AS KH FROM KHACHHANG;
SELECT COUNT(*) AS DON FROM DONDATHANG;
SELECT COUNT(*) AS CT FROM MHDUOCDAT;

-- 14. SAMPLE
SELECT TOP 20 *,
    CASE 
        WHEN TRY_CAST(Quantity AS INT) > 0 THEN 'SALE'
        ELSE 'RETURN'
    END AS TransactionType
FROM STG_OnlineRetail;