<!-- a43f6cb4-7280-4b0e-97ce-6ccb5f470259 86a88733-f5a5-41a8-8c00-052358cde857 -->
# ETL Diagnostic to Staging Solution

## Architecture Overview

Build a complete ETL system that:

- Extracts only "Successful Write" operations from the Diagnostic table
- Tracks last processed timestamp per SCADA station (Location) to handle multiple sources
- Runs automatically every 5 minutes via SQL Server Agent Job
- Prevents duplicate records and ensures no data loss

## Implementation Components

### 1. ETL Control Table Redesign

**Modify `ETL_Control` table structure:**

- Change from single-row tracking to per-location tracking
- Add primary key on `TableName` and `Location`
- Store last processed timestamp per SCADA station

**Table Schema:**

```sql
- TableName (nvarchar(50))
- Location (nvarchar(50))  -- SCADA station identifier
- LastProcessedTime (datetime2)
- LastUpdated (datetime2)
- PRIMARY KEY (TableName, Location)
```

### 2. New ETL Stored Procedure

**Create `sp_ETL_DiagnosticToStaging_v2`:**

**Logic Flow:**

1. Get distinct locations from Diagnostic table
2. For each location, retrieve last processed timestamp from ETL_Control
3. Extract records with MessageText LIKE 'Write%to%' (successful writes only)
4. Filter: `TimeStmp > LastProcessedTime` for that specific location
5. Parse MessageText to extract Tag, OldValue, NewValue
6. Convert boolean text ("True"/"False") to float (1.0/0.0)
7. Insert into DiagnosticStaging
8. Update ETL_Control with max(TimeStmp) per location

**Key Features:**

- Uses `sp_GetAuditLogs` parsing logic as reference
- Per-location timestamp tracking prevents missed records
- Handles concurrent writes from multiple SCADA stations
- Error handling with transaction rollback
- Execution logging for monitoring

### 3. SQL Server Agent Job

**Create Job: `ETL_DiagnosticToStaging_Job`**

- Schedule: Every 5 minutes
- Step: Execute `sp_ETL_DiagnosticToStaging_v2`
- Notifications: On failure (optional)
- Retry logic: 3 attempts with 1-minute intervals

### 4. Initialization & Testing

**Setup Tasks:**

1. Initialize ETL_Control with current timestamp for each location
2. Create test script to validate:

   - Extracts only "Successful Write" records
   - No duplicate records on subsequent runs
   - Handles multiple locations correctly
   - Properly converts values to float

3. Verify SQL Server Agent service is running
4. Test job execution manually before scheduling

## Files to Create

1. **`scripts/01_alter_etl_control.sql`** - Modify ETL_Control table structure
2. **`scripts/02_create_sp_etl_v2.sql`** - New stored procedure
3. **`scripts/03_initialize_etl_control.sql`** - Initialize control table
4. **`scripts/04_create_sql_agent_job.sql`** - SQL Agent job definition
5. **`test/test_etl_execution.sql`** - Testing and validation script
6. **`helps/ETL_Implementation_Guide.md`** - Documentation

## Success Criteria

- ✓ ETL runs every 5 minutes automatically
- ✓ Only "Successful Write" operations are extracted
- ✓ No records missed from any SCADA station
- ✓ No duplicate records in DiagnosticStaging
- ✓ Per-location tracking in ETL_Control
- ✓ Proper error handling and logging

### To-dos

- [ ] Modify ETL_Control table to support per-location tracking
- [ ] Create sp_ETL_DiagnosticToStaging_v2 stored procedure with location-based tracking
- [ ] Initialize ETL_Control with current timestamp for each SCADA location
- [ ] Create SQL Server Agent job to run ETL every 5 minutes
- [ ] Create test script to validate ETL functionality
- [ ] Create implementation guide and documentation