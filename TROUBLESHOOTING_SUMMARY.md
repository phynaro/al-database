# ETL Troubleshooting Summary

## Problem
Running `sp_ETL_DiagnosticToStaging_v2` but no data in DiagnosticStaging table.

## Root Causes Identified

### 1. ETL_Control Table is Empty ❌
The table has no records, so the stored procedure cannot track locations.

### 2. Primary Key Issue ⚠️
The primary key constraint likely only allows one row (only on `TableName` column, not `TableName + Location`).

### 3. Limited Data Available 📊
Only ThinClient03 appears to have "Write" operations that can be extracted.

## Current State

```
ETL_Control:       0 records
DiagnosticStaging: 0 records
Write Operations:  ThinClient03 (confirmed)
```

## Solution (Run These in SSMS)

### Complete Fix Script (All-in-One)

```sql
USE FTDIAG;
GO

-- Step 1: Fix primary key constraint
DECLARE @SQL NVARCHAR(MAX);
SELECT @SQL = 'ALTER TABLE ETL_Control DROP CONSTRAINT ' + name + ';'
FROM sys.indexes 
WHERE object_id = OBJECT_ID('ETL_Control') AND is_primary_key = 1;
EXEC sp_executesql @SQL;

ALTER TABLE ETL_Control 
ADD CONSTRAINT PK_ETL_Control PRIMARY KEY (TableName, Location);
PRINT 'Fixed primary key';

-- Step 2: Initialize ETL_Control with all locations
DELETE FROM ETL_Control WHERE TableName = 'Diagnostic';

INSERT INTO ETL_Control (TableName, Location, LastProcessedTime, LastUpdated)
SELECT 
    'Diagnostic',
    d.Location,
    (SELECT MIN(TimeStmp) FROM Diagnostic d2 WHERE d2.Location = d.Location),
    GETDATE()
FROM (SELECT DIST鑄TH Location FROM Diagnostic WHERE Location IS NOT NULL) d;

PRINT 'Initialized all locations';

-- Step 3: Verify
SELECT * FROM ETL_Control WHERE TableName = 'Diagnostic' ORDER BY Location;

-- Step 4: Run ETL
EXEC sp_ETL_DiagnosticToStaging_v2;

-- Step 5: Check results
SELECT 
    (SELECT COUNT(*) FROM DiagnosticStaging) AS StagingRecords,
    (SELECT COUNT(*) FROM ETL_Control WHERE TableName = 'Diagnostic') AS ControlRecords;
GO
```

## Expected Output

### After Step 3 (ETL_Control):
```
TableName  | Location     | LastProcessedTime
-----------|--------------|------------------
Diagnostic | MTP1-01      | 2025-10-21...
Diagnostic | MTP1-02      | 2025-10-21...
Diagnostic | MTP1-03      | 2025-10-21...
Diagnostic | ThinClient02 | 2025-10-21...
Diagnostic | ThinClient03 | 2025-10-21...
```

### After Step 4 (ETL Execution):
```
========================================
ETL Execution Summary (v2)
========================================
Start Time: 2025-XX-XX...
End Time: 2025-XX-XX...
Duration: XXX ms
Rows Inserted: 2
========================================
```

### After Step 5 (Results):
```
StagingRecords: 2 (or more)
ControlRecords: 5
```

## What the ETL Will Process

Based on current data, the ETL will extract records like:

```
Location: ThinClient03
Tag: U2\HS012\Confirm
NewValue: 1.0 (True)
OldValue: 0.0 (False)
User: THIN-RDS1\THINCLIENT02
```

## Why Some Locations Show No Data

- **MTP1-01**: Has "AE_Acknowledge" operations (not "Write" operations)
- **Other locations**: Check for MessageText starting with "Write '"
- Only operations matching pattern `Write '%' to '%'. Previous value was '%'.` are extracted

## Files to Reference

- `QUICK_FIX_ETL.md` - Detailed fix instructions
- `scripts/agual_initialize_locations.sql` - Initialize script
- `test/diagnose_etl_issue.sql` - Diagnostic queries
- `helps/Auto_Location_Handling.md` - How auto-discovery works

## Next Steps

1. Run the complete fix script above in SSMS
2. Verify DiagnosticStaging has records
3. Check ETL_Control timestamps are updated
4. Monitor SQL Server Agent job execution (if created)
