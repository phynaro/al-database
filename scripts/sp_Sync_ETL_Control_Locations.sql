-- Stored Procedure: Sync ETL_Control Locations
-- Purpose: Add any missing locations from Diagnostic table to ETL_Control
-- If a location exists in Diagnostic but not in ETL_Control, create a record with MIN(TimeStmp)

USE [FTDIAG];
GO

CREATE PROCEDURE [dbo].[sp_Sync_ETL_Control_Locations]
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartTime DATETIME2 = GETDATE();
    DECLARE @LocationsAdded INT = 0;
    DECLARE @Location NVARCHAR(50);
    
    BEGIN TRY
        PRINT '========================================';
        PRINT 'Syncing ETL_Control Locations';
        PRINT '========================================';
        PRINT '';
        
        -- Find locations in Diagnostic that are NOT in ETL_Control
        SELECT DISTINCT d.[Location]
        INTO #MissingLocations
        FROM [dbo].[Diagnostic] d
        WHERE d.[Location] IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 
              FROM [dbo].[ETL_Control] c
              WHERE c.[TableName] = 'Diagnostic'
                AND c.[Location] = d.[Location]
          );
        
        -- Get count of missing locations
        SELECT @LocationsAdded = COUNT(*) FROM #MissingLocations;
        
        IF @LocationsAdded > 0
        BEGIN
            PRINT 'Found ' + CAST(@LocationsAdded AS VARCHAR(10)) + ' missing location(s)';
            PRINT '';
            
            -- Create cursor to process each missing location
            DECLARE location_cursor CURSOR FOR
            SELECT [Location] FROM #MissingLocations;
            
            OPEN location_cursor;
            FETCH NEXT FROM location_cursor INTO @Location;
            
            WHILE @@FETCH_STATUS = 0
            BEGIN
                -- Insert the missing location with MIN(TimeStmp) as LastProcessedTime
                INSERT INTO [dbo].[ETL_Control] 
                (
                    [TableName], 
                    [Location], 
                    [LastProcessedTime], 
                    [LastUpdated]
                )
                SELECT 
                    'Diagnostic' AS [TableName],
                    @Location AS [Location],
                    (
                        SELECT MIN([TimeStmp])
                        FROM [dbo].[Diagnostic]
                        WHERE [Location] = @Location
                    ) AS [LastProcessedTime],
                    GETDATE() AS [LastUpdated];
                
                PRINT '  Added location: ' + @Location;
                
                FETCH NEXT FROM location_cursor INTO @Location;
            END;
            
            CLOSE location_cursor;
            DEALLOCATE location_cursor;
        END
        ELSE
        BEGIN
            PRINT 'All locations are already in ETL_Control';
        END;
        
        -- Clean up temp table
        DROP TABLE #MissingLocations;
        
        -- Log execution summary
        DECLARE @DurationMs INT = DATEDIFF(MILLISECOND, @StartTime, GETDATE());
        
        PRINT '';
        PRINT '========================================';
        PRINT 'Sync Summary';
        PRINT '========================================';
        PRINT 'Start Time: ' + CONVERT(VARCHAR(30), @StartTime, 120);
        PRINT 'End Time: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
        PRINT 'Duration: ' + CAST(@DurationMs AS VARCHAR(10)) + ' ms';
        PRINT 'Locations Added: ' + CAST(@LocationsAdded AS VARCHAR(10));
        PRINT '========================================';
        PRINT '';
        
        -- Show current ETL_Control status
        PRINT 'Current ETL_Control Status:';
        SELECT 
            [Location],
            [LastProcessedTime],
            [LastUpdated]
        FROM [dbo].[ETL_Control]
        WHERE [TableName] = 'Diagnostic'
        ORDER BY [Location];
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        DECLARE @ErrorProcedure NVARCHAR(128) = ISNULL(ERROR_PROCEDURE(), 'sp_Sync_ETL_Control_Locations');
        
        PRINT '';
        PRINT '========================================';
        PRINT 'ERROR OCCURRED';
        PRINT '========================================';
        PRINT 'Error Message: ' + @ErrorMessage;
        PRINT 'Error Line: ' + CAST(@ErrorLine AS VARCHAR(10));
        PRINT 'Error Procedure: ' + @ErrorProcedure;
        PRINT '========================================';
        
        -- Re-throw error
        THROW;
    END CATCH
END;
GO

PRINT 'Created stored procedure: sp_Sync_ETL_Control_Locations';
GO

-- Example usage:
PRINT '';
PRINT 'To sync locations, run:';
PRINT '  EXEC sp_Sync_ETL_Control_Locations;';
GO
