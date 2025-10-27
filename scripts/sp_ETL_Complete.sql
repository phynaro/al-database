-- Master ETL Stored Procedure with Auto-Sync
-- This version auto-syncs missing locations before running the ETL

USE [FTDIAG];
GO

-- First ensure the sync procedure exists
IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sp_Sync_ETL_Control_Locations')
BEGIN
    PRINT 'Please create sp_Sync_ETL_Control_Locations first by running scripts/sp_Sync_ETL_Control_Locations.sql';
    RETURN;
END
GO

-- Drop and recreate the main ETL procedure with auto-sync
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sp_ETL_Complete')
BEGIN
    DROP PROCEDURE [dbo].[sp_ETL_Complete];
END
GO

CREATE PROCEDURE [dbo].[sp_ETL_Complete]
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartTime DATETIME2 = GETDATE();
    
    BEGIN TRY
        PRINT '========================================';
        PRINT 'Complete ETL Process (with Auto-Sync)';
        PRINT '========================================';
        PRINT '';
        
        -- Step 1: Sync missing locations
        PRINT 'Step 1: Syncing missing locations...';
        EXEC [dbo].[sp_Sync_ETL_Control_Locations];
        PRINT '';
        
        -- Step 2: Run the main ETL
        PRINT 'Step 2: Running ETL process...';
        EXEC [dbo].[sp_ETL_DiagnosticToStaging_v2];
        
        -- Summary
        DECLARE @DurationMs INT = DATEDIFF(MILLISECOND, @StartTime, GETDATE());
        PRINT '';
        PRINT '========================================';
        PRINT 'Complete ETL Finished';
        PRINT '========================================';
        PRINT 'Total Duration: ' + CAST(@DurationMs AS VARCHAR(10)) + ' ms';
        PRINT '========================================';
        
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        
        PRINT '';
        PRINT '========================================';
        PRINT 'ETL COMPLETE ERROR';
        PRINT '========================================';
        PRINT 'Error Message: ' + @ErrorMessage;
        PRINT 'Error Line: ' + CAST(@ErrorLine AS VARCHAR(10));
        PRINT '========================================';
        
        THROW;
    END CATCH
END;
GO

PRINT 'Created stored procedure: sp_ETL_Complete';
PRINT '';
PRINT 'This procedure will:';
PRINT '  1. Auto-sync missing locations';
PRINT '  2. Run the ETL process';
PRINT '';
PRINT 'Usage: EXEC sp_ETL_Complete';
GO
