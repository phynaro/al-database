-- Diagnostic script to identify why ETL is not processing data
USE [FTDIAG];
GO

PRINT '========================================';
PRINT 'ETL Diagnostic Investigation';
PRINT '========================================';
PRINT '';

-- Test 1: Check if stored procedure exists
PRINT 'Test 1: Check stored procedure';
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sp_ETL_DiagnosticToStaging_v2')
    PRINT '  PASS: Stored procedure exists';
ELSE
    PRINT '  FAIL: Stored procedure does not exist';
GO

-- Test 2: Check ETL_Control structure
PRINT '';
PRINT 'Test 2: Check ETL_Control table structure';
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ETL_Control'
ORDER BY ORDINAL_POSITION;
GO

-- Test 3: Check ETL_Control data
PRINT '';
PRINT 'Test 3: Current ETL_Control records';
SELECT * FROM ETL_Control WHERE TableName = 'Diagnostic' ORDER BY Location;
GO

-- Test 4: Check source data
PRINT '';
PRINT 'Test 4: Source data analysis';
SELECT 
    Location,
    COUNT(*) AS TotalRecords,
    COUNT(CASE WHEN MessageText LIKE 'Write%to%' THEN 1 END) AS WriteOperations,
    COUNT(CASE WHEN MessageText LIKE 'Write%to%' AND UserID <> 'FactoryTalk Service' THEN 1 END) AS EligibleWrites
FROM Diagnostic
GROUP BY Location
ORDER BY Location;
GO

-- Test 5: Check for parseable write operations
PRINT '';
PRINT 'Test 5: Sample write operations that should be processed';
SELECT TOP 5
    Location,
    TimeStmp,
    MessageText
FROM Diagnostic
WHERE MessageText LIKE 'Write%to%'
  AND UserID <> 'FactoryTalk Service'
ORDER BY TimeStmp DESC;
GO

-- Test 6: Test parsing logic for one record
PRINT '';
PRINT 'Test 6: Parse one write operation manually';
WITH TestRecord AS (
    SELECT TOP 1
        Location,
        TimeStmp,
        MessageText,
        UserID
    FROM Diagnostic
    WHERE MessageText LIKE 'Write%to%'
      AND UserID <> 'FactoryTalk Service'
)
SELECT 
    Location,
    TimeStmp,
    MessageText,
    -- Tag
    CASE 
        WHEN MessageText LIKE 'Write%to%' AND CHARINDEX('to ''', MessageText) > 0 
        THEN SUBSTRING(MessageText, 
                      CHARINDEX('to ''', MessageText) + 4,
                      CHARINDEX('''.', MessageText, CHARINDEX('to ''', MessageText)) - CHARINDEX('to ''', MessageText) - 4)
        ELSE NULL
    END AS ExtractedTag,
    -- NewValue
    CASE 
        WHEN MessageText LIKE 'Write%to%' AND CHARINDEX('Write ''', MessageText) > 0 
        THEN SUBSTRING(MessageText, 
                      CHARINDEX('Write ''', MessageText) + 7,
                      CHARINDEX(''' to', MessageText) - CHARINDEX('Write ''', MessageText) - 7)
        ELSE NULL
    END AS ExtractedNewValue,
    -- OldValue
    CASE 
        WHEN MessageText LIKE '%Previous value was ''%' 
        THEN LEFT(SUBSTRING(MessageText, CHARINDEX('Previous value was ''', MessageText) + 20, LEN(MessageText)), 
                 CASE WHEN CHARINDEX('''', MessageText, CHARINDEX('Previous value was ''', MessageText) + 20) > 0
                      THEN CHARINDEX('''', MessageText, CHARINDEX('Previous value was ''', MessageText) + 20) - CHARINDEX('Previous value was ''', MessageText) - 20
                      ELSE LEN(MessageText) - CHARINDEX('Previous value was ''', MessageText) - 19 END)
        ELSE NULL
    END AS ExtractedOldValue
FROM TestRecord;
GO

-- Test 7: Check DiagnosticStaging structure
PRINT '';
PRINT 'Test 7: DiagnosticStaging table structure';
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'DiagnosticStaging'
ORDER BY ORDINAL_POSITION;
GO

-- Test 8: Check current DiagnosticStaging data
PRINT '';
PRINT 'Test 8: Current DiagnosticStaging records';
SELECT COUNT(*) AS RecordCount FROM DiagnosticStaging;
GO

PRINT '';
PRINT '========================================';
PRINT 'Diagnostic Complete';
PRINT '========================================';
PRINT '';
PRINT 'Recommendations:';
PRINT '1. If ETL_Control is empty, run: scripts/06_manual_initialize_locations.sql';
PRINT '2. If primary key issue, ensure composite key on (TableName, Location)';
PRINT '3. If no write operations found, check MessageText pattern matches';
PRINT '4. Try manual insert to test DiagnosticStaging table';
GO
