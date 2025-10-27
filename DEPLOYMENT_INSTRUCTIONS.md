# ETL Deployment Instructions

## Current Status

I've created all the necessary SQL scripts for the ETL solution. However, I cannot directly execute them via the MCP connection due to security restrictions on ALTER TABLE and some administrative operations.

## Scripts Created

All scripts are ready in the following locations:

### 📁 Scripts Folder
- `scripts/01_alter_etl_control.sql` - Modifies ETL_Control table structure
- `scripts/02_create_sp_etl_v2.sql` - Creates the ETL stored procedure
- `scripts/03_initialize_etl_control.sql` - Initializes control records
- `scripts/04_create_sql_agent_job.sql` - Creates SQL Server Agent job

### 📁 Test Folder
- `test/test_etl_execution.sql` - Comprehensive test script

### 📁 Helps Folder
- `helps/ETL_Implementation_Guide.md` - Complete documentation

## Manual Deployment Steps

Please follow these steps using SQL Server Management Studio (SSMS):

### Step 1: Execute Script 01
Open and run `scripts/01_alter_etl_control.sql` in SSMS:
- This adds the Location column
- Modifies the primary key to composite (TableName, Location)
- Removes the LastProcessedRecordID column

### Step 2: Execute Script 02
Open and run `scripts/02_create_sp_ сумма` в `scripts/02_create_sp_etl_v2.sql` в SSMS:
- This creates the new ETL stored procedure `sp_ETL_DiagnosticToStaging_v2`

### Step 3: Execute Script 03
Open and run `scripts/03_initialize_etl_control.sql` в SSMS:
- This initializes ETL_Control with records for each SCADA location

### Step 4: Execute Script 04
Open and run `scripts/04_create_sql_agent_job.sql` в SSMS:
- This creates the SQL Server Agent job to run every 5 minutes

### Step 5: Test the Solution
Run `test/test_etl_execution.sql` to validate everything works correctly.

### Step 6: Start the Job
```sql
USE msdb;
EXEC dbo.sp_start_job @job_name = 'ETL_DiagnosticToStaging_Job';
```

## Quick Verification Queries

After deployment, run these queries to verify:

```sql
-- Check ETL_Control structure
SELECT * FROM ETL_Control WHERE TableName = 'Diagnostic';

-- Check if stored procedure exists
SELECT name FROM sys.procedures WHERE name = 'sp_ETL_DiagnosticToStaging_v2';

-- Check SQL Agent job
USE msdb;
SELECT name, enabled FROM sysjobs WHERE name = 'ETL_DiagnosticToStaging_Job';

-- Manually test ETL execution
USE FTDIAG;
EXEC sp_ETL_DiagnosticToStaging_v2;

-- Check results in DiagnosticStaging
SELECT TOP 10 * FROM DiagnosticStaging ORDER BY TimeStmp DESC;
```

## What the Solution Does

1. **Per-Location Tracking**: Tracks last processed timestamp separately for each SCADA station
2. **Successful Writes Only**: Extracts only operations where MessageText LIKE 'Write%to%'
3. **Value Conversion**: Converts True/False to 1.0/0.0, handles numeric values
4. **Automatic Scheduling**: Runs every 5 minutes via SQL Server Agent
5. **No Data Loss**: Handles multiple RecordID sequences from different stations correctly

## Need Help?

See the complete documentation in `helps/ETL_Implementation_Guide.md` for:
- Detailed architecture explanation
- Troubleshooting guide
- Performance tuning recommendations
- Maintenance procedures

