USE DataWarehouse;

SELECT
    t.name        AS TableName,
    i.name        AS IndexName,
    i.type_desc   AS IndexType,
    i.filter_definition AS FilterCondition
FROM sys.indexes i
JOIN sys.tables  t ON i.object_id = t.object_id
WHERE t.name IN ('Fact_Sales','Dim_Time','Dim_Customer','Dim_Product')
  AND i.type > 0
ORDER BY t.name,
         CASE i.type_desc
             WHEN 'CLUSTERED'               THEN 1
             WHEN 'NONCLUSTERED COLUMNSTORE' THEN 2
             WHEN 'NONCLUSTERED'            THEN 3
         END;
