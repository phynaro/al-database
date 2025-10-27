-- Manual ETL Test Script
-- This script can be run immediately to test the ETL logic
-- Run this in SSMS after deploying the scripts

USE [FTDIAG];
GO

-- Test 1: Check source data
PRINT 'Test 1: Source Data Analysis';
SELECT 
    Location,
    COUNT(*) AS TotalRecords,
    COUNT(CASE WHEN MessageText LIKE 'Write%to%' AND UserID <> 'FactoryTalk Service' THEN 1 END) AS WriteRecords,
    MIN(TimeStmp) AS EarliestRecord,
    MAX(TimeStmp) AS LatestRecord
FROM [dbo].[Diagnostic]
GROUP BY Location
ORDER BY Location;
GO

-- Test 2: Sample write operation parsing
PRINT '';
PRINT 'Test 2: Sample Parsing of Write Operations';
SELECT TOP 3
    Location,
    TimeStmp,
    MessageText,
    -- Extract Tag
    CASE 
        WHEN MessageText LIKE 'Write%to%' 
             AND CHARINDEX('to ''', MessageText) > 0 
             AND CHARINDEX('''.', MessageText, CHARINDEX('to ''', MessageText)) > CHARINDEX('to ''', MessageText)
        THEN SUBSTRING(MessageText, 
                      CHARINDEX('to ''', MessageText) + 4,
                      CHARINDEX('''.', MessageText, CHARINDEX('to ''', MessageText)) - CHARINDEX('to ''', MessageText) - 4)
        ELSE NULL
    END AS ExtractedTag,
    -- Extract NewValue
    CASE 
        WHEN MessageText LIKE 'Write%to%' 
             AND CHARINDEX('Write ''', MessageText) > 0 
             AND CHARINDEX(''' to', MessageText) > CHARINDEX('Write ''', MessageText)
        THEN SUBSTRING(MessageText, 
                      CHARINDEX('Write ''', MessageText) + 7,
                      CHARINDEX(''' to', MessageText) - CHARINDEX('Write ''', MessageText) - 7)
        ELSE NULL
    END AS ExtractedNewValue,
    -- Extract OldValue
    CASE 
        WHEN MessageText LIKE '%Previous value was ''%' 
             AND CHARINDEX('Previous value was ''', MessageText) > 0
        THEN LEFT(SUBSTRING(MessageText, CHARINDEX('Previous value was ''', MessageText) + 20, LEN(MessageText)), 
                 CASE 
                     WHEN CHARINDEX('''', MessageText, CHARINDEX('Previous value was ''', MessageText) + 20) > 0
                     THEN CHARINDEX('''', MessageText, CHARINDEX('Previous value was ''', MessageText) + 20) - CHARINDEX('Previous value was ''', MessageText) - 20
                     ELSE LEN(MessageText) - CHARINDEX('Previous value was ''', MessageText) - 19
                 END)
        ELSE NULL
    END AS ExtractedOldValue
FROM [dbo].[Diagnostic]
WHERE MessageText LIKE 'Write%to%'
  AND UserID <> 'FactoryTalk Service'
ORDER BY TimeStmp DESC;
GO

-- Test 3: Value conversion simulation
PRINT '';
PRINT 'Test 3: Value Conversion Test';
WITH ParsedData AS (
    SELECT 
        TimeStmp,
        Location,
        CASE 
            WHEN MessageText LIKE 'Write%to%' 
                 AND CHARINDEX('Write ''', MessageText) > 0 
                 AND CHARINDEX(''' to', MessageText) > CHARINDEX('Write ''', MessageText)
            THEN SUBSTRING(MessageText, 
                          CHARINDEX('Write ''', MessageText) + 7,
                          CHARINDEX(''' to', MessageText) - CHARINDEX('Write ''', MessageText) - 7)
            ELSE NULL
        END AS NewValueText
    FROM [dbo].[Diagnostic]
    WHERE MessageText LIKE 'Write%to%'
      AND UserID <> 'FactoryTalk Service'
)
SELECT TOP 10
    Location,
    NewValueText AS OriginalText,
    CASE 
        WHEN UPPER(LTRIM(RTRIM(NewValueText))) = 'TRUE' THEN CAST(1.0 AS FLOAT)
        WHEN UPPER(LTRIM(RTRIM(NewValueText))) = 'FALSE' THEN CAST(0.0 AS FLOAT)
        WHEN ISNUMERIC(LTRIM(RTRIM(NewValueText))) = 1 THEN CAST(LTRIM(RTRIM(NewValueText)) AS FLOAT)
        ELSE NULL
    END AS ConvertedValue
FROM ParsedData
WHERE NewValueText IS NOT NULL
ORDER BY TimeStmp DESC;
GO

-- Test 4: Current DiagnosticStaging status
PRINT '';
PRINT 'Test 4: Current DiagnosticStaging Status';
SELECT 
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT Location) AS NumberOfLocations,
    MIN(TimeStmp) AS EarliestRecord,
    MAX(TimeStmp) AS LatestRecord
FROM [dbo].[DiagnosticStaging];
GO

-- Test 5: Expected ETL behavior (simulation)
PRINT '';
PRINT 'Test 5: Expected Records to Process';
SELECT 
    Location,
    COUNT(*) AS RecordsToProcess
FROM [dbo].[Diagnostic]
WHERE MessageText LIKE 'Write%to%'
  AND UserID <> 'FactoryTalk Service'
  -- Would filter by last processed time in actual ETL
GROUP BY Location
ORDER BY Location;
GO

PRINT '';
PRINT '========================================';
PRINT 'Manual Test Completed';
PRINT '========================================';
PRINT '';
PRINT 'Next Steps:';
PRINT '1. Deploy the ETL scripts using SSMS';
PRINT '2. Run: EXEC sp_ETL_DiagnosticToStaging_v2';
PRINT '3. Verify records in DiagnosticStaging table';
PRINT '4. Check ETL_Control for timestamp updates';
GO
