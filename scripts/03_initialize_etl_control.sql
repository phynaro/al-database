-- Script 03: Initialize ETL_Control Table
-- Purpose: Initialize ETL_Control with current timestamp for each SCADA location
-- This sets the starting point for the ETL process

USE [FTDIAG];
GO

-- Clear any existing records for Diagnostic table
DELETE FROM [dbo].[ETL_Control]
WHERE [TableName] = 'Diagnostic';
GO

PRINT 'Cleared existing ETL_Control records for Diagnostic table';
GO

-- Insert control records for each distinct location in Diagnostic table
INSERT INTO [dbo].[ETL_Control] ([TableName], [Location], [LastProcessedTime], [LastUpdated])
SELECT 
    'Diagnostic' AS [TableName],
    [Location],
    -- Initialize with the minimum timestamp from Diagnostic for this location
    -- This ensures we start from the earliest available data
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

PRINT 'Inserted control records for all locations';
GO

-- Display summary of initialized locations
SELECT 
    [TableName],
    [Location],
    [LastProcessedTime],
    [LastUpdated]
FROM [dbo].[ETL_Control]
WHERE [TableName] = 'Diagnostic'
ORDER BY [Location];
GO

PRINT 'ETL_Control table initialization completed';
GO
