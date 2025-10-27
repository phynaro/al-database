# Quick Fix: ETL Not Processing Data

## Issues Found

1. **ETL_Control table is empty** - No location tracking records
2. **Primary key issue** - The table may only have single-column primary key on TableName
3. **Cannot test execution** - EXEC statement blocked via MCP connection

## Root Cause

The ETL stored procedure requires ETL_Control records to exist. It:
1. Queries Diagnostic table for distinct locations
2. For each location, checks ETL_Control for LastProcessedTime
3. If NULL, it auto-creates a record with LastProcessedTime = 1 day ago

**But** if the primary key only allows one row (TableName-only), it will fail to insert or update.

## Solution

### Step 1: Fix Primary Key (Run in SSMS)

```sql
USE FTDIAG;
GO

-- Drop old primary key
DECLARE @SQL NVARCHAR(MAX);
SELECT @SQL = 'ALTER TABLE ETL_Control DROP CONSTRAINT ' + name + ';'
FROM sys.indexes 
WHERE object_id = OBJECT_ID('ETL_Control') AND is_primary_key = 1;
EXEC sp_executesql @SQL;
GO

-- Add composite primary key
ALTER TABLE ETL_Control 
ADD CONSTRAINT PK_ETL_Control PRIMARY KEY (TableName, Location);
GO

-- Verify
SELECT * FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS 
WHERE TABLE_NAME = 'ETL_Control' AND CONSTRAINT_TYPE = 'PRIMARY KEY';
GO
```

### Step 2: Initialize ETL_Control (Run in SSMS)

```sql
USE FTDIAG;
GO临

-- Clear existing
DELETE FROM ETL_Control WHERE TableName = 'Diagnostic';

-- Insert all locations
INSERT INTO ETL_Control (TableName, Location, LastProcessedTime, LastUpdated)
SELECT 
    'Diagnostic',
    d.Location,
    (SELECT MIN(TimeStmp) FROM Diagnostic d2 WHERE d2.Location = d.Location),
    GETDATE()
FROM (SELECT DISTINCT Location FROM Diagnostic WHERE Location IS NOT NULL) d;

-- Verify
SELECT * FROM ETL_Control WHERE TableName = 'Diagnostic' ORDER BY Location;
GO
```

### Step 3: Test ETL Execution (Run in SSMS)

```sql
USE FTDIAG;
GO

-- Run ETL
EXEC sp_ETL_DiagnosticToStaging_v2;
GO

-- Check results
SELECT COUNT(*) AS NewRecords FROM DiagnosticStaging;
SELECT TOP 10 * FROM DiagnosticStaging ORDER BY TimeStmp DESC;
GO

-- Check updated timestamps
SELECT * FROM ETL_Control WHERE TableName = 'Diagnostic' ORDER BY Location;
GO
```

## Expected Results After Fix

### ETL_Control should have:
```
TableName  | Location     | LastProcessedTime
-----------|--------------|------------------
Diagnostic | MTP1-01      | <timestamp>
Diagnostic | MTP1-02      | <timestamp>
Diagnostic | MTP1-03      | <timestamp>
Diagnostic matters | ThinClient02 | <timestamp>
Diagnostic | ThinClient03 | <timestamp>
```

### DiagnosticStaging should have:
- Records inserted from write operations
- Only locations with "Write 'X' to 'Y'. Previous value was 'Z'." messages
- Converted values: True → 1.0, False → 0.0

## Data Available for Processing

Based on current data:
- **ThinClient03**: Has write operations (should process)
- **MTP1-01**: No write operations (won't process)
- Other locations: Check with diagnostic script

## Verification Query

```sql
-- Check which locations have write operations
SELECT 
    Location,
    COUNT(*) AS WriteCount
FROM Diagnostic
WHERE MessageText LIKE 'Write%to%'
  AND UserID <> 'FactoryTalk Service'
GROUP BY Location
ORDER BY Location;
```

## Files Available

- `scripts/06_manual_initialize_locations.sql` - Combined fix script
- `test/diagnose_etl_issue.sql` - Diagnostic queries
- `FIX_PRIMARY_KEY_ISSUE.md` - Detailed explanation

## After Running the Fix

1. All 5 locations should appear in ETL_Control
2. ETL procedure should execute successfully
3. DiagnosticStaging should have data from ThinClient03
4. ETL job will continue running every 5 minutes automatically
