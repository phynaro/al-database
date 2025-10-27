# ETL Implementation Guide: Diagnostic to Staging

## Overview

This ETL solution extracts "Successful Write" operations from the `Diagnostic` table and loads them into `DiagnosticStaging`. The implementation uses per-location tracking to handle multiple SCADA stations with their own RecordID and timestamp sequences.

## Architecture

### Key Components

1. **ETL_Control Table** - Tracks last processed timestamp for each SCADA station (Location)
2. **sp_ETL_DiagnosticToStaging_v2** - Stored procedure that performs the extraction
3. **SQL Server Agent Job** - Automates the ETL to run every 5 minutes
4. **DiagnosticStaging Table** - Target table for processed data

### Problem Solved

**Challenge**: Multiple SCADA stations send event logs with their own RecordID sequences and timestamps. A simple approach using `RecordID > LastRecordID` would miss records when different stations have overlapping or non-sequential IDs.

**Solution**: Track the last processed timestamp (`LastProcessedTime`) separately for each SCADA location. This ensures no records are missed regardless of how RecordIDs are structured across different stations.

## Implementation Files

Execute the scripts in this order:

### 1. `01_alter_etl_control.sql`
- Modifies ETL_Control table to support per-location tracking
- Adds `Location` column
- Creates composite primary key on (TableName, Location)
- Removes obsolete `LastProcessedRecordID` column

### 2. `02_create_sp_etl_v2.sql`
- Creates the new ETL stored procedure
- Implements per-location processing loop
- Extracts only "Successful Write" operations (MessageText LIKE 'Write%to%')
- Parses and converts values (True/False to 1.0/0.0)
- Updates ETL_Control after processing each location

### 3. `03_initialize_etl_control.sql`
- Initializes ETL_Control with records for each distinct location
- Sets LastProcessedTime to the minimum timestamp for each location
- This ensures the ETL starts from the beginning of available data

### 4. `04_create_sql_agent_job.sql`
- Creates SQL Server Agent job: `ETL_DiagnosticToStaging_Job`
- Configures schedule to run every 5 minutes
- Sets retry logic (3 attempts, 1-minute intervals)
- Configures failure notifications

## How It Works

### ETL Process Flow

1. **Start Transaction** - Begin transaction for data consistency
2. **Iterate Locations** - Loop through each distinct location in Diagnostic table
3. **Get Last Processed Time** - Retrieve the last processed timestamp for the current location
4. **Extract Data** - Select records where:
   - MessageText LIKE 'Write%to%' (successful writes only)
   - Location = current location
   - TimeStmp > LastProcessedTime
   - UserID <> 'FactoryTalk Service'
5. **Parse Values** - Extract and convert:
   - Tag (destination tag name)
   - OldValue (previous value) → float
   - NewValue (new value) → float
   - Convert "True"/"False" to 1.0/0.0
6. **Insert Records** - Insert into DiagnosticStaging
7. **Update Control** - Update ETL_Control with latest timestamp for the location
8. **Commit Transaction** - Commit changes
9. **Next Location** - Process next SCADA station

### Data Conversion

The ETL converts text values to float:

- "True" → 1.0
- "False" → 0.0
- Numeric strings → float value
- NULL or invalid → NULL (record skipped)

Only records with both OldValue and NewValue successfully converted are inserted.

## Installation Steps

### Prerequisites

- SQL Server with SQL Server Agent installed and running
- Database: FTDIAG
- Proper permissions for creating stored procedures and agent jobs
- Tables: Diagnostic, DiagnosticStaging

### Deployment

1. **Open SQL Server Management Studio (SSMS)**

2. **Execute Scripts in Order**:
   ```sql
   -- Run these scripts sequentially
   EXEC scripts/01_alter_etl_control.sql
   EXEC scripts/02_create_sp_etl_v2.sql
   EXEC scripts/03_initialize_etl_control.sql
   EXEC scripts/04_create_sql_agent_job.sql
   ```

3. **Verify Installation**:
   ```sql
   -- Run the test script
   EXEC test/test_etl_execution.sql
   ```

4. **Start the Job**:
   ```sql
   USE msdb;
   EXEC dbo.sp_start_job @job_name = 'ETL_DiagnosticToStaging_Job';
   ```

5. **Verify Execution**:
   - Check SQL Server Agent Job history
   - Query DiagnosticStaging table for new records
   - Monitor ETL_Control table for timestamp updates

## Monitoring

### Check Job Status

```sql
USE msdb;
SELECT 
    job.name AS 'Job Name',
    job.enabled AS 'Enabled',
    h.run_status,
    h.run_date,
    h.run_time
FROM sysjobs job
LEFT JOIN (
    SELECT TOP 1 *
    FROM sysjobhistory
    WHERE job_id = (SELECT job_id FROM sysjobs WHERE name = 'ETL_DiagnosticToStaging_Job')
    ORDER BY run_date DESC, run_time DESC
) h ON job.job_id = h.job_id
WHERE job.name = 'ETL_DiagnosticToStaging_Job';
```

### Check ETL Progress

```sql
USE FTDIAG;
SELECT 
    Location,
    LastProcessedTime,
    LastUpdated,
    DATEDIFF(MINUTE, LastUpdated, GETDATE()) AS 'Minutes Since Last Update'
FROM ETL_Control
WHERE TableName = 'Diagnostic'
ORDER BY Location;
```

### Check Recent Data Load

```sql
USE FTDIAG;
SELECT 
    Location,
    COUNT(*) AS 'Record Count',
    MIN(TimeStmp) AS 'Earliest Record',
    MAX(TimeStmp) AS 'Latest Record'
FROM DiagnosticStaging
GROUP BY Location
ORDER BY Location;
```

## Troubleshooting

### Job Not Running

1. **Check SQL Server Agent Service**:
   - Open Services (services.msc)
   - Verify "SQL Server Agent (MSSQLSERVER)" is running

2. **Check Job Status**:
   ```sql
   USE msdb;
   SELECT * FROM sysjobs WHERE name = 'ETL_DiagnosticToStaging_Job';
   ```

3. **Check Job History**:
   ```sql
   USE msdb;
   SELECT TOP 10 *
   FROM sysjobhistory
   WHERE job_id = (SELECT job_id FROM sysjobs WHERE name = 'ETL_DiagnosticToStaging_Job')
   ».

DER BY run_date DESC, run_time DESC;
   ```

### No Records Being Inserted

1. **Check Source Data**:
   ```sql
   SELECT COUNT(*)
   FROM Diagnostic
   WHERE MessageText LIKE 'Write%to%'
     AND UserID <> 'FactoryTalk Service';
   ```

2. **Check LastProcessedTime**:
   ```sql
   SELECT *
   FROM ETL_Control
   WHERE TableName = 'Diagnostic';
   ```

3. **Manually Execute ETL**:
   ```sql
   EXEC sp_ETL_DiagnosticToStaging_v2;
   ```

### Duplicate Records

If duplicates are found:

1. **Check for overlapping timestamps**:
   ```sql
   SELECT TimeStmp, Location, Tag, COUNT(*) AS 'Count'
   FROM DiagnosticStaging
   GROUP BY TimeStmp, Location, Tag
   HAVING COUNT(*) > 1;
   ```

2. **Consider adding a unique constraint** on DiagnosticStaging to prevent duplicates

### Performance Issues

For large data volumes:

1. Add indexes to Diagnostic table:
   ```sql
   CREATE INDEX IX_Diagnostic_Location_TimeStmp ON Diagnostic(Location, TimeStmp)
   INCLUDE (MessageText, UserID);
   ```

2. Add indexes to DiagnosticStaging:
   ```sql
   CREATE INDEX IX_DiagnosticStaging_TimeStmp ON DiagnosticStaging(TimeStmp);
   CREATE INDEX IX_DiagnosticStaging_Location ON DiagnosticStaging(Location);
   ```

3. Consider batch processing for very high volume locations

## Maintenance

### Manual ETL Execution

```sql
USE FTDIAG;
EXEC sp_ETL_DiagnosticToStaging_v2;
```

### Reset ETL (Start from Beginning)

```sql
USE FTDIAG;

-- Reset LastProcessedTime to minimum timestamp for each location
UPDATE c
SET c.LastProcessedTime = d.MinTime,
    c.LastUpdated = GETDATE()
FROM ETL_Control c
INNER JOIN (
    SELECT Location, MIN(TimeStmp) AS MinTime
    FROM Diagnostic
    GROUP BY Location
) d ON c.Location = d.Location
WHERE c.TableName = 'Diagnostic';
```

### Modify Schedule

```sql
USE msdb;

-- View current schedule
SELECT s.name AS 'Schedule Name', s.freq_subday_interval
FROM sysjobschedules js
INNER JOIN sysjobs j ON js.job_id = j.job_id
INNER JOIN sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name = 'ETL_DiagnosticToStaging_Job';

-- Change to 10 minutes (update the schedule_id returned above)
EXEC sp_update_schedule
    @schedule_id = 1,  -- Replace with actual schedule_id
    @freq_subday_interval = 10;
```

## Success Criteria

- ✓ ETL runs every 5 minutes automatically
- ✓ Only "Successful Write" operations are extracted
- ✓ No records missed from any SCADA station
- ✓ No duplicate records in DiagnosticStaging
- ✓ Per-location tracking in ETL_Control
- ✓ Proper error handling and logging
- ✓ Data correctly converted to float format

## Support

For issues or questions:
1. Review the test script output: `test/test_etl_execution.sql`
2. Check SQL Server Agent job history
3. Review stored procedure execution logs
4. Check ETL_Control table for status
