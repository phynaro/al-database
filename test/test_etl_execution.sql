-- Test Script: Validate ETL Functionality
-- Purpose: Test and validate the ETL process to ensure it works correctly
-- Run this script to verify the ETL implementation

USE [FTDIAG];
GO

PRINT '========================================';
PRINT 'ETL Test Suite';
PRINT '========================================';
PRINT '';

-- Test 1: Verify ETL_Control table structure
PRINT 'Test 1: Verify ETL_Control table structure';
IF EXISTS (
    SELECT 1 
    FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'ETL_Control' 
    AND COLUMN_NAME = 'Location'
)
    PRINT '  PASS: Location column exists in ETL_Control';
ELSE
    PRINT '  FAIL: Location column missing in ETL_Control';

IF EXISTS (
    SELECT 1 
    FROM sys.indexes 
    WHERE name = 'PK_ETL_Control' 
    AND is_primary_key = 1
)
    PRINT '  PASS: Primary key exists on TableName and Location';
ELSE
    PRINT '  FAIL: Primary key missing on ETL_Control';
GO

-- Test 2: Verify stored procedure exists
PRINT '';
PRINT 'Test 2: Verify stored procedure exists';
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sp_ETL_DiagnosticToStaging_v2')
    PRINT '  PASS: Stored procedure sp_ETL_DiagnosticToStaging_v2 exists';
ELSE
    PRINT '  FAIL: Stored procedure sp_ETL_DiagnosticToStaging_v2 not found';
GO

-- Test 3: Check ETL_Control initialization
PRINT '';
PRINT 'Test 3: Check ETL_Control initialization';
DECLARE @ControlCount INT;
SELECT @ControlCount = COUNT(*) 
FROM [dbo].[ETL_Control]
WHERE [TableName] = 'Diagnostic';

IF @ControlCount > 0
BEGIN
    PRINT '  PASS: ETL_Control has ' + CAST(@ControlCount AS VARCHAR(10)) + ' location(s) configured';
    
    -- Display the configured locations
    SELECT 
        [Location] AS 'Location',
        [LastProcessedTime] AS 'Last Processed',
        [LastUpdated] AS 'Last Updated'
    FROM [dbo].[ETL_Control]
    WHERE [TableName] = 'Diagnostic'
    ORDER BY [Location];
END
ELSE
    PRINT '  FAIL: ETL_Control has no records for Diagnostic table';
GO

-- Test 4: Verify source data exists
PRINT '';
PRINT 'Test 4: Verify source data in Diagnostic table';
DECLARE @SourceCount INT;
SELECT @SourceCount = COUNT(*) 
FROM [dbo].[Diagnostic]
WHERE [MessageText] LIKE 'Write%to%'
  AND [UserID] <> 'FactoryTalk Service';

IF @SourceCount > 0
    PRINT '  PASS: Found ' + CAST(@SourceCount AS VARCHAR(10)) + ' "Successful Write" records in Diagnostic table';
ELSE
    PRINT '  WARNING: No "Successful Write" records found in Diagnostic table';
GO

-- Test 5: Check for distinct locations
PRINT '';
PRINT 'Test 5: Check distinct locations in Diagnostic table';
SELECT 
    COUNT(DISTINCT [Location]) AS 'Number of Locations',
    STRING_AGG([Location], ', ') AS 'Locations'
FROM [dbo].[Diagnostic]
WHERE [Location] IS NOT NULL;
GO

-- Test 6: Manual ETL execution test
PRINT '';
PRINT 'Test 6: Manual ETL execution';
PRINT '  Executing sp_ETL_DiagnosticToStaging_v2...';
GO

DECLARE @BeforeCount INT;
DECLARE @AfterCount INT;
SELECT @BeforeCount = COUNT(*) FROM [dbo].[DiagnosticStaging];

EXEC [dbo].[sp_ETL_DiagnosticToStaging_v2];

SELECT @AfterCount = COUNT(*) FROM [dbo].[DiagnosticStaging];

IF @AfterCount > @BeforeCount
    PRINT '  PASS: ETL inserted ' + CAST(@AfterCount - @BeforeCount AS VARCHAR(10)) + ' new records';
ELSE IF @AfterCount = @BeforeCount
    PRINT '  WARNING: No new records were inserted (data may be up to date)';
ELSE
    PRINT '  FAIL: Record count decreased unexpectedly';
GO

-- Test 7: Verify no duplicates
PRINT '';
PRINT 'Test 7: Verify no duplicate records';
DECLARE @TotalCount INT;
DECLARE @DistinctCount INT;

SELECT @TotalCount = COUNT(*)
FROM [dbo].[DiagnosticStaging];

SELECT @DistinctCount = COUNT(*)
FROM (
    SELECT DISTINCT [TimeStmp], [Tag], [Location], [UserID], [OldValue], [NewValue]
    FROM [dbo].[DiagnosticStaging]
) AS DistinctData;

IF @TotalCount = @DistinctCount
    PRINT '  PASS: No duplicate records found (' + CAST(@TotalCount AS VARCHAR(10)) + ' total records)';
ELSE
    PRINT '  FAIL: Found ' + CAST(@TotalCount - @DistinctCount AS VARCHAR(10)) + ' duplicate records';
GO

-- Test 8: Verify data quality
PRINT '';
PRINT 'Test 8: Verify data quality';
DECLARE @NullOldValue INT;
DECLARE @NullNewValue INT;

SELECT @NullOldValue = COUNT(*)
FROM [dbo].[DiagnosticStaging]
WHERE [OldValue] IS NULL;

SELECT @NullNewValue = COUNT(*)
FROM [dbo].[DiagnosticStaging]
WHERE [NewValue] IS NULL;

IF @NullOldValue = 0
    PRINT '  PASS: No NULL OldValue records';
ELSE
    PRINT '  WARNING: Found ' + CAST(@NullOldValue AS VARCHAR(10)) + ' records with NULL OldValue';

IF @NullNewValue = 0
    PRINT '  PASS: No NULL NewValue records';
ELSE
    PRINT '  WARNING: Found ' + CAST(@NullNewValue AS VARCHAR(10)) + ' records with NULL NewValue';
GO

-- Test 9: Sample data verification
PRINT '';
PRINT 'Test 9: Sample data from DiagnosticStaging';
SELECT TOP 5
    [TimeStmp] AS 'Timestamp',
    [Location] AS 'Location',
    [Tag] AS 'Tag',
    [OldValue] AS 'Old Value',
    [NewValue] AS 'New Value',
    [UserID] AS 'User'
FROM [dbo].[DiagnosticStaging]
ORDER BY [TimeStmp] DESC;
GO

-- Test 10: Check SQL Server Agent Job (if accessible)
PRINT '';
PRINT 'Test 10: Check SQL Server Agent Job';
SET NOCOUNT ON;
DECLARE @JobExists BIT = 0;

BEGIN TRY
    SELECT @JobExists = 1
    FROM msdb.dbo.sysjobs
    WHERE name = 'ETL_DiagnosticToStaging_Job';
    
    IF @JobExists = 1
        PRINT '  PASS: SQL Server Agent Job exists';
    ELSE
        PRINT '  WARNING: SQL Server Agent Job not found';
END TRY
BEGIN CATCH
    PRINT '  SKIP: Cannot access SQL Server Agent (insufficient permissions or not available)';
END CATCH
GO

SET NOCOUNT OFF;

PRINT '';
PRINT '========================================';
PRINT 'Test Suite Completed';
PRINT '========================================';
GO

-- Summary report
PRINT '';
PRINT 'Summary Report:';
PRINT '===============';
GO

SELECT 
    'Diagnostic Table' AS 'Table',
    COUNT(*) AS 'Total Records',
    (SELECT COUNT(*) FROM [dbo].[Diagnostic] WHERE [MessageText] LIKE 'Write%to%' AND [UserID] <> 'FactoryTalk Service') AS 'Write Records'
FROM [dbo].[Diagnostic]
UNION ALL
SELECT 
    'DiagnosticStaging Table' AS 'Table',
    COUNT(*) AS 'Total Records',
    NULL AS 'Write Records'
FROM [dbo].[DiagnosticStaging]
UNION ALL
SELECT 
    'ETL_Control Table' AS 'Table',
    COUNT(*) AS 'Total Records',
    NULL AS 'Write Records'
FROM [dbo].[ETL_Control]
WHERE [TableName] = 'Diagnostic';
GO
