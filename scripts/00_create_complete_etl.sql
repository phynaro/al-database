-- Complete ETL Setup Script
-- This script creates everything from scratch: ETL_Control table and stored procedure
-- Run this in SSMS to set up the complete ETL solution

USE [FTDIAG];
GO

PRINT '========================================';
PRINT 'Creating Complete ETL Solution';
PRINT '========================================';
PRINT '';

-- Step 1: Drop existing objects if they exist
PRINT 'Step 1: Dropping existing objects...';
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sp_ETL_DiagnosticToStaging_v2')
BEGIN
    DROP PROCEDURE [dbo].[sp_ETL_DiagnosticToStaging_v2];
    PRINT '  Dropped existing stored procedure';
END
ELSE
    PRINT '  No existing stored procedure found';

IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ETL_Control')
BEGIN
    -- Drop constraints first
    DECLARE @SQL NVARCHAR(MAX);
    SELECT @SQL = COALESCE(@SQL + ', ', '') + '[' + name + ']'
    FROM sys.objects
    WHERE type = 'UQ' OR type = 'PK'
    AND parent_object_id = OBJECT_ID('ETL_Control');
    
    IF @SQL IS NOT NULL
    BEGIN
        SET @SQL = 'ALTER TABLE ETL_Control DROP CONSTRAINT ' + @SQL;
        EXEC sp_executesql @SQL;
    END
    
    DROP TABLE [dbo].[ETL_Control];
    PRINT '  Dropped existing ETL_Control table';
END
ELSE
    PRINT '  No existing ETL_Control table found';
GO

-- Step 2: Create ETL_Control table with correct structure
PRINT '';
PRINT 'Step 2: Creating ETL_Control table...';
GO

CREATE TABLE [dbo].[ETL_Control] (
    [TableName] [NVARCHAR](50) NOT NULL,
    [Location] [NVARCHAR](50) NOT NULL,
    [LastProcessedTime] [DATETIME2] NULL,
    [LastUpdated] [DATETIME2] NULL,
    CONSTRAINT [PK_ETL_Control] PRIMARY KEY ([TableName], [Location])
);
GO

PRINT '  Created ETL_Control table with composite primary key';
GO

-- Step 3: Initialize ETL_Control with all locations
PRINT '';
PRINT 'Step 3: Initializing ETL_Control with locations...';
GO

INSERT INTO [dbo].[ETL_Control] ([TableName], [Location], [LastProcessedTime], [LastUpdated])
SELECT 
    'Diagnostic' AS [TableName],
    d.[Location],
    (
        SELECT MIN([TimeStmp])
        FROM [dbo].[Diagnostic] d2
        WHERE d2.[Location] = d.[Location]
    ) AS [LastProcessedTime],
    GETDATE() AS [LastUpdated]
    FROM (
        SELECT DISTINCT [Location]
        FROM [dbo].[Diagnostic]
        WHERE [Location] IS NOT NULL
    ) d;
GO

PRINT '  Inserted control records for all locations';
GO

-- Display initialized records
SELECT * FROM [dbo].[ETL_Control] WHERE [TableName] = 'Diagnostic' ORDER BY [Location];
GO

-- Step 4: Create the ETL stored procedure
PRINT '';
PRINT 'Step 4: Creating stored procedure...';
GO

CREATE PROCEDURE [dbo].[sp_ETL_DiagnosticToStaging_v2]
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartTime DATETIME2 = GETDATE();
    DECLARE @RowsInserted INT = 0;
    DECLARE @RowsProcessed INT = 0;
    DECLARE @Location NVARCHAR(50);
    DECLARE @LastProcessedTime DATETIME2;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Create cursor to iterate through each unique location
        DECLARE location_cursor CURSOR FOR
        SELECT DISTINCT [Location]
        FROM [dbo].[Diagnostic]
        WHERE [Location] IS NOT NULL;
        
        OPEN location_cursor;
        FETCH NEXT FROM location_cursor INTO @Location;        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Get last processed time for this location
            SELECT @LastProcessedTime = [LastProcessedTime]
            FROM [dbo].[ETL_Control]
            WHERE [TableName] = 'Diagnostic' 
              AND [Location] = @Location;
            
            -- If no record exists, initialize with timestamp 1 day ago
            IF @LastProcessedTime IS NULL
            BEGIN
                SET @LastProcessedTime = DATEADD(DAY, -1, GETDATE());
                
                -- Insert initial control record
                INSERT INTO [dbo].[ETL_Control] ([TableName], [Location], [LastProcessedTime], [LastUpdated])
                VALUES ('Diagnostic', @Location, @LastProcessedTime, GETDATE());
            END;
            
            -- CTE to parse and convert values from MessageText (only "Write" operations)
            WITH ParsedData AS (
                SELECT 
                    [TimeStmp],
                    [Location],
                    [UserID],
                    
                    -- Extract Tag (destination)
                    CASE 
                        WHEN [MessageText] LIKE 'Write%to%' 
                             AND CHARINDEX('to ''', [MessageText]) > 0 
                             AND CHARINDEX('''.', [MessageText], CHARINDEX('to ''', [MessageText])) > CHARINDEX('to ''', [MessageText])
                        THEN SUBSTRING([MessageText], 
                                      CHARINDEX('to ''', [MessageText]) + 4,
                                      CHARINDEX('''.', [MessageText], CHARINDEX('to ''', [MessageText])) - CHARINDEX('to ''', [MessageText]) - 4)
                        ELSE NULL
                    END AS [Tag],
                    
                    -- Extract NewValue text (value being written)
                    CASE 
                        WHEN [MessageText] LIKE 'Write%to%' 
                             AND CHARINDEX('Write ''', [MessageText]) > 0 
                             AND CHARINDEX(''' to', [MessageText]) > CHARINDEX('Write ''', [MessageText])
                        THEN SUBSTRING([MessageText], 
                                      CHARINDEX('Write ''', [MessageText]) + 7,
                                      CHARINDEX(''' to', [MessageText]) - CHARINDEX('Write ''', [MessageText]) - 7)
                        ELSE NULL
                    END AS [NewValueText],
                    
                    -- Extract OldValue text (previous value)
                    CASE 
                        WHEN [MessageText] LIKE '%Previous value was ''%' 
                             AND CHARINDEX('Previous value was ''', [MessageText]) > 0
                        THEN LEFT(SUBSTRING([MessageText], CHARINDEX('Previous value was ''', [MessageText]) + 20, LEN([MessageText])), 
                                 CASE 
                                     WHEN CHARINDEX('''', [MessageText], CHARINDEX('Previous value was ''', [MessageText]) + 20) > 0
                                     THEN CHARINDEX('''', [MessageText], CHARINDEX('Previous value was ''', [MessageText]) + 20) - CHARINDEX('Previous value was ''', [MessageText]) - 20
                                     ELSE LEN([MessageText]) - CHARINDEX('Previous value was ''', [MessageText]) - 19
                                 END)
                        ELSE NULL
                    END AS [OldValueText]
                FROM [dbo].[Diagnostic]
                WHERE [MessageText] LIKE 'Write%to%'  -- Only successful write operations
                  AND [Location] = @Location
                  AND [TimeStmp] > @LastProcessedTime
                  AND [UserID] <> 'FactoryTalk Service'
            ),
            ConvertedData AS (
                SELECT
                    [TimeStmp],
                    [Tag],
                    [Location],
                    [UserID],
                    -- Convert NewValue: "True"→1.0, "False"→0.0, numeric→float, else NULL
                    CASE 
                        WHEN UPPER(LTRIM(RTRIM([NewValueText]))) = 'TRUE' THEN CAST(1.0 AS FLOAT)
                        WHEN UPPER(LTRIM(RTRIM([NewValueText]))) = 'FALSE' THEN CAST(0.0 AS FLOAT)
                        WHEN ISNUMERIC(LTRIM(RTRIM([NewValueText]))) = 1 THEN CAST(LTRIM(RTRIM([NewValueText])) AS FLOAT)
                        ELSE NULL
                    END AS [NewValue],
                    -- Convert OldValue: "True"→1.0, "False"→0.0, numeric→float, else NULL
                    CASE 
                        WHEN [OldValueText] IS NULL OR LTRIM(RTRIM([OldValueText])) = '' THEN NULL
                        WHEN UPPER(LTRIM(RTRIM([OldValueText]))) = 'TRUE' THEN CAST(1.0 AS FLOAT)
                        WHEN UPPER(LTRIM(RTRIM([OldValueText]))) = 'FALSE' THEN CAST(0.0 AS FLOAT)
                        WHEN ISNUMERIC(LTRIM(RTRIM([OldValueText]))) = 1 THEN CAST(LTRIM(RTRIM([OldValueText])) AS FLOAT)
                        ELSE NULL
                    END AS [OldValue]
                FROM [ParsedData]
            )
            
            -- Insert records with NewValue not null (OldValue can be NULL for writes without previous value)
            INSERT INTO [dbo].[DiagnosticStaging] ([TimeStmp], [Tag], [OldValue], [NewValue], [Location], [UserID])
            SELECT 
                [TimeStmp],
                [Tag],
                [OldValue],
                [NewValue],
                [Location],
                [UserID]
            FROM [ConvertedData]
            WHERE [NewValue] IS NOT NULL;
            
            SET @RowsInserted = @RowsInserted + @@ROWCOUNT;
            
            -- Update ETL_Control with the latest processed timestamp for this location
            IF EXISTS (SELECT 1 FROM [dbo].[Diagnostic] WHERE [Location] = @Location AND [TimeStmp] > @LastProcessedTime)
            BEGIN
                DECLARE @MaxTime DATETIME2;
                SELECT @MaxTime = MAX([TimeStmp])
                FROM [dbo].[Diagnostic]
                WHERE [Location] = @Location;
                
                UPDATE [dbo].[ETL_Control]
                SET [LastProcessedTime] = @MaxTime,
                    [LastUpdated] = GETDATE()
                WHERE [TableName] = 'Diagnostic' 
                  AND [Location] = @Location;
            END;
            
            FETCH NEXT FROM location_cursor INTO @Location;
        END;
        
        CLOSE location_cursor;
        DEALLOCATE location_cursor;
        
        SET @RowsProcessed = @RowsInserted;
        
        -- Log execution summary
        DECLARE @DurationMs INT = DATEDIFF(MILLISECOND, @StartTime, GETDATE());
        
        PRINT '========================================';
        PRINT 'ETL Execution Summary (v2)';
        PRINT '========================================';
        PRINT 'Start Time: ' + CONVERT(VARCHAR(30), @StartTime, 120);
        PRINT 'End Time: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
        PRINT 'Duration: ' + CAST(@DurationMs AS VARCHAR(10)) + ' ms';
        PRINT 'Rows Inserted: ' + CAST(@RowsInserted AS VARCHAR(10));
        PRINT '========================================';
        
        COMMIT TRANSACTION;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        DECLARE @ErrorProcedure NVARCHAR(128) = ISNULL(ERROR_PROCEDURE(), 'sp_ETL_DiagnosticToStaging_v2');
        
        PRINT '========================================';
        PRINT 'ETL ERROR OCCURRED';
        PRINT '========================================';
        PRINT 'Error Message: ' + @ErrorMessage;
        PRINT 'Error Line: ' + CAST(@ErrorLine AS VARCHAR(10));
        PRINT 'Error Procedure: ' + @ErrorProcedure;
        PRINT '========================================';
        
        -- Re-throw error for SQL Agent to capture
        THROW;
    END CATCH
END;
GO

PRINT '  Created stored procedure: sp_ETL_DiagnosticToStaging_v2';
GO

-- Step 5: Verify the setup
PRINT '';
PRINT 'Step 5: Verification...';
PRINT '';

-- Check table
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ETL_Control')
    PRINT '  ✓ ETL_Control table exists';
ELSE
    PRINT '  ✗ ETL_Control table missing';

-- Check stored procedure
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sp_ETL_DiagnosticToStaging_v2')
    PRINT '  ✓ Stored procedure exists';
ELSE
    PRINT '  ✗ Stored procedure missing';

-- Check records
DECLARE @RecordCount INT;
SELECT @RecordCount = COUNT(*) FROM ETL_Control WHERE TableName = 'Diagnostic';
PRINT '  ✓ ETL_Control has ' + CAST(@RecordCount AS VARCHAR(10)) + ' location(s)';

PRINT '';
PRINT '========================================';
PRINT 'ETL Setup Complete!';
PRINT '========================================';
PRINT '';
PRINT 'Next steps:';
PRINT '1. Run: EXEC sp_ETL_DiagnosticToStaging_v2';
PRINT '2. Check DiagnosticStaging table for results';
PRINT '3. Verify ETL_Control timestamps are updated';
PRINT '';

-- Show current state
SELECT 'ETL_Control Records' AS Info, * FROM ETL_Control WHERE TableName = 'Diagnostic' ORDER BY Location;
GO
