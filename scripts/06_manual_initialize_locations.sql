-- Manual initialization script for ETL_Control locations
-- Run this in SSMS after the table structure is fixed

USE [FTDIAG];
GO

-- Step 1: Drop old primary key
DECLARE @SQL NVARCHAR(MAX);
SELECT @SQL = 'ALTER TABLE ETL_Control DROP CONSTRAINT ' + name + ';'
FROM sys.indexes 
WHERE object_id = OBJECT_ID('ETL_Control') AND is_primary_key = 1;

EXEC sp_executesql @SQL;

-- Step 2: Add new composite primary key
ALTER TABLE ETL_Control 
ADD CONSTRAINT PK_ETL_Control PRIMARY KEY (TableName, Location);

-- Step 3: Clear and insert all locations
DELETE FROM ETL_Control WHERE TableName = 'Diagnostic';

INSERT INTO ETL_Control (TableName, Location, LastProcessedTime, LastUpdated)
SELECT 
    'Diagnostic',
    d.Location,
    (SELECT MIN(TimeStmp) FROM Diagnostic d2 WHERE d2.Location = d.Location),
    GETDATE()
FROM (SELECT DISTINCT Location FROM Diagnostic WHERE Location IS NOT NULL) d;

SELECT * FROM ETL_Control WHERE TableName = 'Diagnostic' ORDER BY Location;
GO
