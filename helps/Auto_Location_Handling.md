# Automatic Location Handling

## Yes, New Locations Are Created Automatically! ✅

The stored procedure `sp_ETL_DiagnosticToStaging_v2` is designed to automatically handle new SCADA locations as they start feeding data.

## How It Works

### The Cursor Logic

The stored procedure uses a cursor to iterate through **all distinct locations** found in the Diagnostic table:

```sql
-- Lines 24-27
DECLARE location_cursor CURSOR FOR
SELECT DISTINCT [Location]
FROM [dbo].[Diagnostic]
WHERE [Location] IS NOT NULL;
```

This means **every time the ETL runs**, it checks ALL locations in the Diagnostic table, not just ones that exist in ETL_Control.

### Auto-Initialization Logic

For each location found in Diagnostic table:

```sql
-- Lines 34-48
-- Get last processed time for this location
SELECT @LastProcessedTime = [LastProcessedTime]
FROM [dbo].[ETL_Control]
WHERE [TableName] = 'Diagnostic' 
  AND [Location] = @Location;

-- If no record exists, initialize with timestamp 1 day ago
IF @LastProcessedTime IS NULL
BEGIN
    SET @LastProcessedTime = DATEADD(DAY, -1, GETDATE());
    
    -- Insert initial control record
    INSERT INTO [dbo].[ETL_Control] ([TableName], [Location], [LastProcessedTime], [LastUpdated])
    VALUES ('Diagnostic', @Location, @LastProcessedTime, GETDATE());
END;
```

### What Happens When a New Location Appears

**Scenario**: A new SCADA station "MTP1-04" starts feeding data to the Diagnostic table.

1. **Next ETL Run**: The cursor queries Diagnostic table and finds 'MTP1-04'
2. **ETL_Control Check**: Queries ETL_Control for 'MTP1-04' → Returns NULL
3. **Auto-Create**: Inserts a new record with:
   - TableName = 'Diagnostic'
   - Location = 'MTP1-04'
   - LastProcessedTime = 1 day ago (DATEADD(DAY, -1, GETDATE()))
   - LastUpdated = Current timestamp
4. **Process Data**: Extracts all data from 'MTP1-04' where TimeStmp > LastProcessedTime
5. **Update**: Updates ETL_Control with the latest timestamp from 'MTP1-04'

## Example Timeline

### Day 1: ETL_Control has 5 locations
```
MTP1-01, MTP1-02, MTP1-03, ThinClient02, ThinClient03
```

### Day 2: New station MTP1-04 starts
```
- MTP1-04 sends data to Diagnostic table
- Next ETL run (within 5 minutes) detects MTP1-04
- Automatically creates ETL_Control record for MTP1-04
- Processes all data from MTP1-04
```

### Day 2: ETL_Control now has 6 locations
```
MTP1-01, MTP1-02, MTP1-03, MTP1-04, ThinClient02, ThinClient03
```

## Important Notes

### Updated Date Handling

When a new location is created, it sets `LastProcessedTime = 1 day ago`. This means:
- ✅ The first ETL run will process up to 1 day of historical data
- ⚠️ Older data (beyond 1 day) won't be processed unless you manually adjust

### Manual Initialization Alternative

If you want to process ALL historical data from a new location, you can manually initialize:

```sql
-- Process ALL data from a new location
INSERT INTO ETL_Control (TableName, Location, LastProcessedTime, LastUpdated)
VALUES ('Diagnostic', 'MTP1-04', 
        (SELECT MIN(TimeStmp) FROM Diagnostic WHERE Location = 'MTP1-04'), 
        GETDATE());
```

### Removing Old Locations

The ETL does **NOT** automatically remove locations from ETL_Control. If a SCADA station is decommissioned:
- The location remains in ETL_Control
- No harm is done (it just won't find new data)
- You can manually delete if desired:

```sql
DELETE FROM ETL_Control 
WHERE TableName = 'Diagnostic' AND Location = 'OldStation';
```

## Verification Query

To see all locations being tracked:

```sql
SELECT 
    Location,
    LastProcessedTime,
    LastUpdated,
    DATEDIFF(MINUTE, LastUpdated, GETDATE()) AS MinutesSinceLastUpdate
FROM ETL_Control
WHERE TableName = 'Diagnostic'
ORDER BY Location;
```

## Summary

✅ **Automatic**: New locations are detected and tracked automatically  
✅ **No Manual Work**: No need to manually add new locations  
✅ **Safe**: Creates records only when data exists  
✅ **Flexible**: Can be overridden with manual initialization if needed  

The design handles dynamic SCADA environments where stations can be added or removed!
