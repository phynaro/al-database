# ETL Diagnostic to Staging Solution

Complete ETL solution to extract "Successful Write" operations from Diagnostic table to DiagnosticStaging every 5 minutes.

## Quick Start

### Prerequisites
- SQL Server with SQL Server Agent
- Database: FTDIAG
- SSMS installed

### Installation

1. Open SQL Server Management Studio (SSMS)
2. Connect to your SQL Server
3. Execute scripts in order:
   ```
   scripts/01_alter_etl_control.sql
   scripts/02_create_sp_etl_v2.sql
   scripts/03_initialize_etl_control.sql
   scripts/04_create_sql_agent_job.sql
   ```
4. Run tests: `test/test_etl_execution.sql`
5. Start the job:
   ```sql
   USE msdb;
   EXEC dbo.sp_start_job @job_name = 'ETL_DiagnosticToStaging_Job';
   ```

## Key Features

✅ **Per-Location Tracking** - Handles multiple SCADA stations with separate RecordID sequences
✅ **Auto-Discovery** - Automatically detects and tracks new SCADA locations without manual configuration
✅ **Success Only** - Extracts only "Successful Write" operations (MessageText LIKE 'Write%to%')
✅ **Automatic Scheduling** - Runs every 5 minutes via SQL Server Agent
✅ **Data Conversion** - Converts True/False to 1.0/0.0, handles numeric values
✅ **No Data Loss** - Tracks last processed timestamp per location

## Project Structure

```
al-database/
├── scripts/           # Deployment scripts
│   ├── 01_alter_etl_control.sql
│   ├── 02_create_sp_etl_v2.sql
│   ├── 03_initialize_etl_control.sql
│   └── 04_create_sql_agent_job.sql
├── test/             # Test scripts
│   ├── test_etl_execution.sql
│   └── manual_test_etl.sql
├── helps/            # Documentation
│   └── ETL_Implementation_Guide.md
├── DEPLOYMENT_INSTRUCTIONS.md
└── README.md
```

## How It Works

1. **ETL_Control** tracks `LastProcessedTime` for each SCADA location
2. **Stored Procedure** processes each location separately
3. Extracts records where `TimeStmp > LastProcessedTime` for that location
4. Parses MessageText to extract Tag, OldValue, NewValue
5. Converts values to float (True→1.0, False→0.0)
6. Inserts into DiagnosticStaging
7. Updates ETL_Control with latest timestamp

## Monitoring

```sql
-- Check job status
USE msdb;
SELECT name, enabled FROM sysjobs WHERE name = 'ETL_DiagnosticToStaging_Job';

-- Check ETL progress
USE FTDIAG;
SELECT * FROM ETL_Control WHERE TableName = 'Diagnostic';

-- Check recent data
SELECT TOP 10 * FROM DiagnosticStaging ORDER BY TimeStmp DESC;
```

## Documentation

- **Complete Guide**: `helps/ETL_Implementation_Guide.md`
- **Auto Location Handling**: `helps/Auto_Location_Handling.md` - How new SCADA stations are automatically tracked
- **Deployment**: `DEPLOYMENT_INSTRUCTIONS.md`
- **Manual Test**: `test/manual_test_etl.sql`

## Support

For issues or questions, see the troubleshooting section in `helps/ETL_Implementation_Guide.md`
# al-database
