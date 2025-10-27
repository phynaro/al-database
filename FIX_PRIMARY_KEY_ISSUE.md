# Fix for ETL_Control Location Issue

## Problem Identified

**Issue**: ETL_Control table only has 1 record (for 'MTP1-01') instead of 5 records (one per location).

**Root Cause**: The primary key constraint on ETL_Control only includes `TableName`, not `(TableName, Location)`. This prevents multiple records with the same TableName value.

**Current Structure**:
- Primary Key: Only `TableName`
- Result: Can only have one row with TableName='Diagnostic'

**Required Structure**:
- Primary Key: `(TableName, Location)` 
- Result: Can have multiple rows with TableName='Diagnostic', one per Location

## Solution

Run the fix script `scripts/06_manual_initialize_locations.sql` in SSMS. This script will:

1. Drop the old primary key constraint
2. Add a new composite primary key on `(TableName, Location)`
3. Clear existing Diagnostic records
4. Insert records for all 5 locations

## Quick Fix (Run in SSMS)

```sql
USE FTDIAG;
GO

-- Step 1: Drop old primary key
DECLARE @SQL NVARCHAR(MAX);
SELECT @SQL = 'ALTER TABLE ETL_Control DROP CONSTRAINT ' + name + ';'
FROM sys.indexes 
WHERE object_id = OBJECT_ID('ETL_Control') AND is_primary_key = 1;
EXEC sp_executesql @SQL;
GO

-- Step 2: Add composite primary key
ALTER TABLE ETL_Control 
ADD CONSTRAINT PK_ETL_Control PRIMARY KEY (TableName, Location);
GO

-- Step 3: Insert all locations
DELETE FROM ETL_Control WHERE TableName = 'Diagnostic';

INSERT INTO ETL_Control (TableName, Location, LastProcessedTime, LastUpdated)
SELECT 
    'Diagnostic',
    d.Location,
    (SELECT MIN(TimeStmp) FROM Diagnostic d2 WHERE d2.Location = d.Location),
    GETDATE()
FROM (SELECT DISTINCT Location FROM Diagnostic WHERE Location IS NOT NULL) d;
GO

-- Verify
SELECT * FROM ETL_Control WHERE TableName = 'Diagnostic' ORDER BY Location;
GO
```

## After Fixing

1. Run the fix script
2. Verify all 5 locations appear in ETL_Control
3. Re-run the ETL procedure: `EXEC sp_ETL_DiagnosticToStaging_v2`
4. Check that it processes data from all locations

## Expected Result

After running the fix, you should see:

```
TableName  | Location     | LastProcessedTime    | LastUpdated
-----------|--------------|---------------------|--------------------
Diagnostic | MTP1-01      | 2025-10-XX XX:XX:XX | 2025-XX-XX XX:XX:XX
Diagnostic | MTP1-02      | 2025-10-XX XX:XX:XX | 2025-XX-XX XX:XX:XX
Diagnostic | MTP1-03      | 2025-10-XX XX:XX:XX | 2025-XX-XX XX:XX:XX
Diagnostic | ThinClient02 | 2025-10-XX XX:XX:XX | 2025-XX-XX XX:XX:XX
Diagnostic | ThinClient03 | 2025-10-XX XX:XX:XX | 2025-XX-XX XX:XX:XX
```

## Note for Future Reference

Script `01_alter_etl_control.sql` was supposed to handle this, but it wasn't executed properly. The table structure modification requires full ALTER TABLE permissions that weren't available via the MCP connection. This is why manual execution in SSMS is required.
