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
FROM 'D:\Code\PTIT\data-warehouse-and-data-mining\cleaned_data_final.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIELDQUOTE = '"',
    CODEPAGE = '65001',
    TABLOCK
);

-- 3. CLEAN DATA (remove rows where no customer ID)
DELETE FROM STG_OnlineRetail
WHERE TRY_CAST(Quantity AS INT) IS NULL
   OR TRY_CAST(UnitPrice AS DECIMAL(10,2)) IS NULL
   OR CustomerID IS NULL;


-- 4. CREATE CITIES
DROP TABLE IF EXISTS TMP_CITY;

CREATE TABLE TMP_CITY (
    MaTP VARCHAR(100) PRIMARY KEY,
    TenTP NVARCHAR(100),
    Bang NVARCHAR(100)
);

INSERT INTO TMP_CITY VALUES
('LON', N'London', N'England South'),
('MAN', N'Manchester', N'England North'),
('BIR', N'Birmingham', N'Midlands'),
('LEE', N'Leeds', N'England North');

-- 5. VANPHONGDAIDIEN
INSERT INTO VANPHONGDAIDIEN (MaTP, TenTP, DiaChiVP, Bang, ThoiGianThanhLap)
SELECT 
    MaTP,
    TenTP,
    TenTP + N' Central Office, UK',
    Bang,
    DATEADD(YEAR, -ABS(CHECKSUM(MaTP)) % 20, GETDATE())
FROM TMP_CITY;

-- 6. CUAHANG
INSERT INTO CUAHANG (MaCH, MaTP, SoDienThoai, ThoiGianMoCua)
SELECT 
    CONCAT('STORE_', MaTP, '_', n),
    MaTP,
    CONCAT('07', RIGHT('000000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000000 AS VARCHAR), 9)),
    DATEADD(DAY, -ABS(CHECKSUM(NEWID())) % 2000, GETDATE())
FROM (
    SELECT 'LON' MaTP, n FROM (VALUES (1),(2),(3),(4)) v(n)
    UNION ALL
    SELECT 'MAN', n FROM (VALUES (1),(2),(3)) v(n)
    UNION ALL
    SELECT 'BIR', n FROM (VALUES (1),(2)) v(n)
    UNION ALL
    SELECT 'LEE', n FROM (VALUES (1)) v(n)
) x;

-- 7. KHACHHANG
WITH CTE AS (
    SELECT 
        s.CustomerID,
        ROW_NUMBER() OVER (ORDER BY s.CustomerID) AS rn,
        MIN(TRY_CONVERT(DATETIME, s.InvoiceDate)) AS FirstOrderDate
    FROM STG_OnlineRetail s
    GROUP BY s.CustomerID
)
INSERT INTO KHACHHANG (MaKH, TenKH, MaTP, NgayDatHangDau, LoaiKH)
SELECT 
    CustomerID,
    CONCAT(N'Customer ', CustomerID),

    CASE (rn % 4)
        WHEN 0 THEN 'LON'
        WHEN 1 THEN 'MAN'
        WHEN 2 THEN 'BIR'
        ELSE 'LEE'
    END,

    FirstOrderDate,

    CASE (rn % 3)
        WHEN 0 THEN 'DL'
        WHEN 1 THEN 'BD'
        ELSE 'CA'
    END
FROM CTE;

-- 8. CUSTOMER TYPE TABLES
DROP TABLE IF EXISTS TMP_GUIDES;

CREATE TABLE TMP_GUIDES (
    GuideID INT IDENTITY(1,1),
    GuideName NVARCHAR(100)
);

INSERT INTO TMP_GUIDES (GuideName)
VALUES
(N'Oliver Smith'),(N'George Brown'),(N'Jack Taylor'),
(N'Noah Wilson'),(N'Leo Harris'),(N'Oscar Clark'),
(N'Harry Lewis'),(N'James Walker'),(N'Charlie Hall'),
(N'Thomas Allen');

INSERT INTO KHACHHANG_DULICH (MaKH, HuongDanVien, ThoiGianCuTru)
SELECT 
    k.MaKH,
    g.GuideName,
    DATEADD(DAY, ABS(CHECKSUM(k.MaKH)) % 365, '2022-01-01')
FROM KHACHHANG k
JOIN TMP_GUIDES g 
    ON g.GuideID = (ABS(CHECKSUM(k.MaKH)) % 10) + 1
WHERE k.LoaiKH IN ('DL', 'CA');

INSERT INTO KHACHHANG_BUUDIEN (MaKH, DiaChiBuuDien, ThoiGianNhanHang)
SELECT 
    k.MaKH,
    CONCAT(
        CAST(ABS(CHECKSUM(k.MaKH)) % 200 + 1 AS VARCHAR),
        ' ',
        CASE ABS(CHECKSUM(k.MaKH)) % 5
            WHEN 0 THEN 'Baker Street'
            WHEN 1 THEN 'Oxford Road'
            WHEN 2 THEN 'High Street'
            WHEN 3 THEN 'King Street'
            ELSE 'Queen Avenue'
        END,
        ', UK'
    ),
    DATEADD(DAY, ABS(CHECKSUM(k.MaKH)) % 365, '2022-01-01')
FROM KHACHHANG k
WHERE k.LoaiKH IN ('BD', 'CA');

-- 9. MATHANG
INSERT INTO MATHANG (MaMH, MoTa, KichCo, TrongLuong, Gia, ThoiGianNhapHang)
SELECT 
    s.StockCode,
    MAX(s.Description),
    'Standard',
    ABS(CHECKSUM(s.StockCode)) % 5 + 0.5,
    AVG(TRY_CAST(s.UnitPrice AS DECIMAL(10,2))),
    MIN(TRY_CONVERT(DATETIME, s.InvoiceDate))
FROM STG_OnlineRetail s
GROUP BY s.StockCode;

-- 10. DONDATHANG (SAFE FK)
INSERT INTO DONDATHANG (MaDon, NgayDatHang, MaKH)
SELECT 
    s.InvoiceNo,
    MIN(TRY_CONVERT(DATETIME, s.InvoiceDate)),
    MIN(s.CustomerID)
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

-- 12. MHLUUTRU

WITH Sales AS (
    SELECT
        ch.MaCH,
        s.StockCode AS MaMH,
        SUM(TRY_CAST(s.Quantity AS INT)) AS TotalSold,
        MAX(TRY_CONVERT(DATETIME, s.InvoiceDate)) AS LastSaleDate
    FROM STG_OnlineRetail s

    JOIN DONDATHANG d 
        ON d.MaDon = s.InvoiceNo

    JOIN KHACHHANG k 
        ON k.MaKH = d.MaKH

    JOIN CUAHANG ch 
        ON ch.MaTP = k.MaTP  

    GROUP BY ch.MaCH, s.StockCode
)

INSERT INTO MHLUUTRU (MaCH, MaMH, SoLuongTon, ThoiGianLuuTru)
SELECT
    c.MaCH,
    m.MaMH,

    -- FINAL STOCK (NO NEGATIVE)
    CASE 
        WHEN 
            (
                initStock + refill - ISNULL(s.TotalSold, 0)
            ) < 0 
        THEN 0
        ELSE 
            (initStock + refill - ISNULL(s.TotalSold, 0))
    END AS SoLuongTon,

    -- SNAPSHOT DATE (REALISTIC)
    CASE 
        WHEN ABS(CHECKSUM(c.MaCH, m.MaMH)) % 2 = 0 
            THEN ISNULL(s.LastSaleDate, GETDATE()) -- last sale
        ELSE 
            DATEADD(
                DAY,
                - ABS(CHECKSUM(c.MaCH, m.MaMH, 'REFILL')) % 10,
                GETDATE()
            ) -- simulated recent refill
    END AS ThoiGianLuuTru

FROM CUAHANG c
CROSS JOIN MATHANG m

LEFT JOIN Sales s 
    ON s.MaCH = c.MaCH AND s.MaMH = m.MaMH

CROSS APPLY (
    SELECT 
        ABS(CHECKSUM(c.MaCH, m.MaMH)) % 500 + 100 AS initStock,
        CASE 
            WHEN ABS(CHECKSUM(c.MaCH, m.MaMH)) % 3 = 0 
            THEN ABS(CHECKSUM(c.MaCH, m.MaMH, 'REFILL')) % 200 + 50
            ELSE 0
        END AS refill
) calc;

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