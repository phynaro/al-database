-- Script 04: Create SQL Server Agent Job
-- Purpose: Create a job to run the ETL process every 5 minutes
-- Note: This script uses SQL Server Agent objects (msdb database)

USE [msdb];
GO

-- Remove the job if it already exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'ETL_DiagnosticToStaging_Job')
BEGIN
    EXEC msdb.dbo.sp_delete_job 
        @job_name = 'ETL_DiagnosticToStaging_Job',
        @delete_unused_schedule = 1;
    PRINT 'Removed existing job: ETL_DiagnosticToStaging_Job';
END;
GO

-- Create the job
EXEC msdb.dbo.sp_add_job
    @job_name = 'ETL_DiagnosticToStaging_Job',
    @description = 'ETL job to extract Diagnostic data to DiagnosticStaging every 5 minutes',
    @owner_login_name = 'sa',
    @enabled = 1,
    @notify_level_eventlog = 2,  -- On failure
    @delete_level = 0;  -- Do not delete on completion
GO

-- Add job step to execute the stored procedure
EXEC msdb.dbo.sp_add_jobstep
    @job_name = 'ETL_DiagnosticToStaging_Job',
    @step_name = 'Run ETL Procedure',
    @subsystem = 'TSQL',
    @command = N'EXEC [FTDIAG].[dbo].[sp_ETL_DiagnosticToStaging_v2];',
    @database_name = 'FTDIAG',
    @on_success_action = 3,  -- Go to next step
    @on_fail_action = 3,     -- Go to next step
    @retry_attempts = 3,      -- Retry up to 3 times
    @retry_interval = 1;      -- Wait 1 minute between retries
GO

-- Add a step to log job completion
EXEC msdb.dbo.sp_add_jobstep
    @job_name = 'ETL_DiagnosticToStaging_Job',
    @step_name = 'Log Completion',
    @subsystem = 'TSQL',
    @command = N'
    PRINT ''ETL Job completed at: '' + CONVERT(VARCHAR(30), GETDATE(), 120);
    ',
    @database_name = 'FTDIAG',
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 2;     -- Quit with failure
GO

-- Create schedule to run every 5 minutes
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = 'ETL_Every_5_Minutes',
    @freq_type = 4,  -- Daily
    @freq_interval = 1,
    @freq_subday_type = 4,  -- Minutes
    @freq_subday_interval = 5,
    @active_start_time = 0;  -- Start at midnight (000000)
GO

-- Attach the schedule to the job
EXEC msdb.dbo.sp_attach_schedule
    @job_name = 'ETL_DiagnosticToStaging_Job',
    @schedule_name = 'ETL_Every_5_Minutes';
GO

-- Add the job to the local server
EXEC msdb.dbo.sp_add_jobserver
    @job_name = 'ETL_DiagnosticToStaging_Job',
    @server_name = '(local)';
GO

PRINT 'SQL Server Agent Job created successfully: ETL_DiagnosticToStaging_Job';
PRINT 'Schedule: Every 5 minutes';
PRINT '';
PRINT 'To start the job manually, execute:';
PRINT 'USE msdb;';
PRINT 'EXEC dbo.sp_start_job @job_name = ''ETL_DiagnosticToStaging_Job'';';
PRINT '';
PRINT 'To stop the job, execute:';
PRINT 'USE msdb;';
PRINT 'EXEC dbo.sp_stop_job @job_name = ''ETL_DiagnosticToStaging_Job'';';
GO

USE [FTDIAG];
GO
