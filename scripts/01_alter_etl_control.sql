-- Script 01: Alter ETL_Control Table Structure
-- Purpose: Modify ETL_Control to support per-location tracking
-- This allows tracking last processed timestamp for each SCADA station separately

USE [FTDIAG];
GO

-- First, drop the old procedure if it exists (we'll replace it with v2)
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sp_ETL_DiagnosticToStaging')
BEGIN
    DROP PROCEDURE [dbo].[sp_ETL_DiagnosticToStaging];
    PRINT 'Dropped old procedure: sp_ETL_DiagnosticToStaging';
END;
GO

-- Check if ETL_Control table has the Location column
IF NOT EXISTS (
    SELECT 1 
    FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'ETL_Control' 
    AND COLUMN_NAME = 'Location'
)
BEGIN
    -- Add Location column
    ALTER TABLE [dbo].[ETL_Control]
    ADD [Location] NVARCHAR(50) NOT NULL DEFAULT 'ALL';
    
    PRINT 'Added Location column to ETL_Control table';
    
    -- Drop existing primary key if it exists
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'PK_ETL_Control')
    BEGIN
        ALTER TABLE [dbo].[ETL_Control] DROP CONSTRAINT PK_ETL_Control;
        PRINT 'Dropped existing primary key';
    END;
    
    -- Add composite primary key on TableName and Location
    ALTER TABLE [dbo].[ETL_Control]
    ADD CONSTRAINT PK_ETL_Control PRIMARY KEY ([TableName], [Location]);
    
    PRINT 'Created composite primary key on TableName and Location';
END
ELSE
BEGIN
    PRINT 'ETL_Control table already has Location column';
END;
GO

-- Remove LastProcessedRecordID column if it exists (no longer needed)
IF EXISTS (
    SELECT 1 
    FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'ETL_Control' 
    AND COLUMN_NAME = 'LastProcessedRecordID'
)
BEGIN
    ALTER TABLE [dbo].[ETL_Control]
    DROP COLUMN [LastProcessedRecordID];
    PRINT 'Dropped LastProcessedRecordID column';
END;
GO

PRINT 'ETL_Control table structure update completed';
GO
