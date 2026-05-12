-- 1. Table catalog (4 bảng)
SELECT TableName, TableType, RefreshPolicy, GrainDescription
FROM Meta_Table ORDER BY TableType, TableName;

-- 2. Column catalog (16 cột tổng cộng)
SELECT TableName, ColumnName, FullDataType, ColumnRole, BusinessName
FROM vw_DataDictionary ORDER BY TableType, TableName, ColOrder;

-- 3. Star schema relationships (3 quan hệ)
SELECT * FROM vw_StarSchema;

-- 4. Business glossary (10 thuật ngữ)
SELECT Term, Category, Definition
FROM Meta_BusinessGlossary ORDER BY Category, Term;
