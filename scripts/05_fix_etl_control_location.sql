-- Script 05: Fix ETL_Control to support multiple locations
-- Issue: Primary key only includes TableName, not Location
-- This script handles the table structure properly

USE [FTDIAG];
GO

-- Step 1: Check if Location column exists
IF NOT EXISTS (
    SELECT 1 
    FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'ETL_Control' 
    AND COLUMN_NAME = 'Location'
)
BEGIN
    ALTER TABLE [dbo].[ETL_Control] ADD [Location] NVARCHAR(50) NOT NULL DEFAULT 'ALL';
    PRINT 'Added Location column to ETL_Control table';
END
ELSE
BEGIN
    PRINT 'Location column already exists';
END;
GO

-- Step 2: Drop old primary key if exists
DECLARE @PKConstraintName NVARCHAR(200);
SELECT @PKConstraintName = name 
FROM sys.indexes 
WHERE object_id = OBJECT_ID('ETL_Control') AND is_primary_key = 1;

IF @PKConstraintName IS NOT NULL
BEGIN
    EXEC('ALTER TABLE [dbo].[ETL_Control] DROP CONSTRAINT [' + @PKConstraintName + ']');
    PRINT 'Dropped old primary key constraint';
END
ELSE
BEGIN
    PRINT 'No primary key constraint found';
END;
GO

-- Step 3: Add new composite primary key
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE object_id = OBJECT_ID('ETL_Control') 
    AND name = 'PK_ETL_Control' 
    AND is_primary_key = 1
)
BEGIN
    ALTER TABLE [dbo].[ETL_Control]
    ADD CONSTRAINT PK_ETL_Control PRIMARY KEY ([TableName], [Location]);
    PRINT 'Created composite primary key on TableName and Location';
END
ELSE
BEGIN
    PRINT 'Primary key already exists';
END;
GO

-- Step 4: Clear existing data
DELETE FROM [dbo].[ETL_Control] WHERE [TableName] = 'Diagnostic';
PRINT 'Cleared existing Diagnostic records';

-- Step 5: Insert records for all locations
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

PRINT 'Inserted control records for all locations';
GO

-- Verify
SELECT * FROM [dbo].[ETL_Control] WHERE [TableName] = 'Diagnostic' ORDER BY [Location];
GO

PRINT 'ETL_Control table fix completed';
GO
