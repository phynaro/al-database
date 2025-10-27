# Location Sync Utility

## Overview

The `sp_Sync_ETL_Control_Locations` stored procedure automatically detects and adds any missing locations from the Diagnostic table to ETL_Control.

## When to Use

Use this procedure when:
- New SCADA stations start sending data
- Locations were manually added to Diagnostic
- You want to ensure ETL_Control is in sync with Diagnostic
- Running as part of regular maintenance

## How It Works

1. **Scan Diagnostic**: Finds all distinct locations in the Diagnostic table
2. **Check ETL_Control**: Identifies locations that exist in Diagnostic but NOT in ETL_Control
3. **Create Records**: For each missing location, creates an ETL_Control record with:
   - `LastProcessedTime` = MIN(TimeStmp) for that location
   - `LastUpdated` = Current timestamp
4. **Report**: Shows summary of what was added

## Usage

### Basic Sync
```sql
USE FTDIAG;
EXEC sp_Sync_ETL_Control_Locations;
```

### Expected Output
```
========================================
Syncing ETL_Control Locations
========================================

Found 2 missing location(s)

  Added location: MTP1-04
  Added location: ThinClient04

========================================
Sync Summary
========================================
Start Time: 2025-XX-XX XX:XX:XX
End Time: 2025-XX-XX XX:XX:XX
Duration: XX ms
Locations Added: 2
========================================
```

## Example Scenarios

### Scenario 1: New SCADA Station
1. New station "MTP1-04" starts sending data to Diagnostic
2. Run: `EXEC sp_Sync_ETL_Control_Locations;`
3. MTP1-04 is automatically added to ETL_Control
4. Next ETL run will process data from MTP1-04

### Scenario 2: Manual Data Import
1. Data imported to Diagnostic from a backup
2. Contains location "OldStation1" not in ETL_Control
3. Run sync to add missing location
4. ETL will then track this location

### Scenario 3: All Already Synced
```
========================================
Syncing ETL_Control Locations
========================================

All locations are already in ETL_Control

========================================
Sync Summary
========================================
...
Locations Added: 0
========================================
```

## Faster ETL with Auto-Sync

Use the combined procedure `sp_ETL_Complete` which runs sync first, then ETL:

```sql
USE FTDIAG;
EXEC sp_ETL_Complete;
```

This ensures you never miss new locations.

## Scheduling Recommendations

### Option 1: Before Each ETL Run
In your SQL Agent job, call the complete procedure:
```sql
EXEC sp_ETL_Complete;  -- Syncs first, then runs ETL
```

### Option 2: Periodic Sync Only
Run sync separately, less frequently:
```sql
-- Daily sync at midnight
EXEC sp_Sync_ETL_Control_Locations;

-- Then regular ETL every 5 minutes
EXEC sp_ETL_DiagnosticToStaging_v2;
```

### Option 3: On-Demand
Run only when you know new locations were added.

## Verification Queries

### Check for Missing Locations
```sql
-- Find locations in Diagnostic not in ETL_Control
SELECT DISTINCT d.Location
FROM Diagnostic d
WHERE d.Location IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 
      FROM ETL_Control c
      WHERE c.TableName = 'Diagnostic'
        AND c.Location = d.Location
  );
```

### Count Locations in Each Table
```sql
SELECT 
    'Diagnostic' AS Source,
    COUNT(DISTINCT Location) AS LocationCount
FROM Diagnostic
WHERE Location IS NOT NULL

UNION ALL

SELECT 
    'ETL_Control' AS Source,
    COUNT(DISTINCT Location) AS LocationCount
FROM ETL_Control
WHERE TableName = 'Diagnostic';
```

### View All Tracked Locations
```sql
SELECT 
    Location,
    LastProcessedTime,
    LastUpdated,
    DATEDIFF(MINUTE, LastUpdated, GETDATE()) AS MinutesSinceUpdate
FROM ETL_Control
WHERE TableName = 'Diagnostic'
ORDER BY Location;
```

## Troubleshooting

### Issue: Procedure Not Found
**Solution**: Create the procedure first:
```sql
-- Run: scripts/sp_Sync_ETL_Control_Locations.sql
```

### Issue: Primary Key Violation
**Solution**: Check ETL_Control has composite primary key:
```sql
SELECT 
    i.name AS IndexName,
    COL_NAME(ic.object_id, ic.column_id) AS ColumnName
FROM sys.indexes i
INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
WHERE i.object_id = OBJECT_ID('ETL_Control') AND i.is_primary_key = 1
ORDER BY ic.key_ordinal;
```

Should show: TableName, Location (in that order)

### Issue: Performance Slow with Large Tables
**Optimization**: Add indexes:
```sql
CREATE INDEX IX_Diagnostic_Location ON Diagnostic(Location);
CREATE INDEX IX_ETL_Control_Location ON ETL_Control(Location);
```

## Related Procedures

- `sp_ETL_DiagnosticToStaging_v2` - Main ETL process
- `sp_ETL_Complete` - Combined sync + ETL
- `sp_Sync_ETL_Control_Locations` - Location sync only

## Files

- `scripts/sp_Sync_ETL_Control_Locations.sql` - Sync procedure
- `scripts/sp_ETL_Complete.sql` - Combined ETL with auto-sync
