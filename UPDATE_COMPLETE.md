# Update Complete: ETL Now Includes Writes Without Previous Value

## ✅ What Was Changed

The ETL stored procedure has been updated to capture write operations that don't have a "Previous value was" statement.

## 📝 Changes Made

### Modified Files
1. **scripts/02_create_sp_etl_v2.sql** (Line 121-131)
2. **scripts/00_create_complete_etl.sql** (Line 209-219)

### What Changed
- **Old filter**: Required BOTH OldValue AND NewValue to be NOT NULL
- **New filter**: Only requires NewValue to be NOT NULL

```sql
-- OLD
WHERE [OldValue] IS NOT NULL AND [NewValue] IS NOT NULL;

-- NEW
WHERE [NewValue] IS NOT NULL;
```

## 🎯 What This Means

### Now Captures:
- ✅ `Write '123' to 'U3\Machine\tag'` → OldValue=NULL, NewValue=123.0
- ✅ `Write 'True' to 'tag'` → OldValue=NULL, NewValue=1.0
- ✅ `Write '456.78' to 'tag'` → OldValue=NULL, NewValue=456.78

### Still Captures:
- ✅ `Write 'True' to 'tag'. Previous value was 'False'.` → OldValue=0.0, NewValue=1.0

### Still Skips:
- ❌ Messages that don't start with "Write"
- ❌ Messages without a valid NewValue (non-numeric text)

## 📊 Current State

Based on your data:
- **ETL_Control**: ✅ Created with 5 locations
- **Stored Procedure**: Needs to be recreated with this update
- **Data Available**: Mix of writes with/without previous values

## 🚀 Next Steps

### 1. Recreate the Stored Procedure
Run in SSMS:
```sql
USE FTDIAG;

-- Drop old procedure if exists
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sp_ETL_DiagnosticToStaging_v2')
    DROP PROCEDURE sp_ETL_DiagnosticToStaging_v2;

-- Run the updated script
-- Execute: scripts/02_create_sp_etl_v2.sql
```

### 2. Test the ETL
```sql
-- Run the ETL
EXEC sp_ETL_DiagnosticToStaging_v2;

-- Check results
SELECT COUNT(*) AS TotalRecords FROM DiagnosticStaging;
SELECT COUNT(*) AS RecordsWithOldValue FROM DiagnosticStaging WHERE OldValue IS NOT NULL;
SELECT COUNT(*) AS RecordsWithoutOldValue FROM DiagnosticStaging WHERE OldValue IS NULL;
```

### 3. Verify
```sql
-- See the different record types
SELECT 
    CASE WHEN OldValue IS NULL THEN 'No Previous Value' ELSE 'With Previous Value' END AS RecordType,
    COUNT(*) AS Count
FROM DiagnosticStaging
GROUP BY CASE WHEN OldValue IS NULL THEN 'No Previous Value' ELSE 'With Previous Value' END;
```

## 📋 Summary

The ETL will now capture a more complete audit trail by including write operations even when the previous value is unknown. This eliminates data loss for these types of operations.

**Files ready to use:**
- `scripts/02_create_sp_etl_v2.sql` (updated)
- `scripts/00_create_complete_etl.sql` (updated)

**Just recreate the stored procedure and run it!** 🎉
