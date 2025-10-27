# Quick Start Guide

## Complete ETL Solution Overview

This solution provides a complete ETL system to extract "Successful Write" operations from the Diagnostic table to DiagnosticStaging.

## Key Features

✅ **Per-Location Tracking** - Handles multiple SCADA stations separately
✅ **Auto-Discovery** - Automatically detects new locations
✅ **Auto-Sync** - Syncs missing locations before ETL runs
✅ **Flexible** - Captures writes with or without previous values
✅ **Automated** - Runs every 5 minutes via SQL Agent

## Three Stored Procedures

### 1. `sp_ETL_DiagnosticToStaging_v2` - Main ETL
**Purpose**: Extract data from Diagnostic to DiagnosticStaging
**Usage**: `EXEC sp_ETL_DiagnosticToStaging_v2;`
**What it does**:
- Processes each location separately
- Extracts only "Write" operations
- Converts values (True/False → 1.0/0.0)
- Updates tracking timestamps

### 2. `sp_Sync_ETL_Control_Locations` - Location Sync
**Purpose**: Add missing locations to ETL_Control
**Usage**: `EXEC sp_Sync_ETL_Control_Locations;`
**What it does**:
- Finds locations in Diagnostic not in ETL_Control
- Creates tracking records for missing locations
- Sets LastProcessedTime to MIN(TimeStmp) for each

### 3. `sp_ETL_Complete` - Combined Solution
**Purpose**: Run sync + ETL in one call
**Usage**: `EXEC sp_ETL_Complete;`
**What it does**:
- Syncs missing locations first
- Then runs the main ETL process
- Recommended for automated scheduling

## Installation

### Step 1: Create ETL_Control Table
```sql
-- Already created in your database
```

### Step 2: Create Stored Procedures
```sql
-- Run these scripts in SSMS:
scripts/sp_Sync_ETL_Control_Locations.sql
scripts/02_create_sp_etl_v2.sql
scripts/sp_ETL_Complete.sql
```

### Step 3: Test
```sql
-- Run the complete ETL
USE FTDIAG;
EXEC sp_ETL_Complete;

-- Check results
SELECT COUNT(*) FROM DiagnosticStaging;
SELECT TOP 10 * FROM DiagnosticStaging ORDER BY TimeStmp DESC;
```

## Scheduling Options

### Option A: Use Complete ETL (that:Cre)

Update your SQL Agent job to call:
```sql
EXEC sp_ETL_Complete;
```
This ensures new locations are always tracked.

### Option B: Run Sync Separately

**Job 1**: Sync (daily at midnight)
```sql
EXEC sp_Sync_ETL_Control_Locations;
```

**Job 2**: ETL (every 5 minutes)
```sql
EXEC sp_ETL_DiagnosticToStaging_v2;
```

## What Data is Captured

### ✅ Captured (Included):
```
Write '123' to 'U3\Machine\tag'.
  → OldValue: NULL, NewValue: 123.0

Write 'True' to 'tag'. Previous value was 'False'.
  → OldValue: 0.0, NewValue: 1.0

Write '456.78' to 'tag'.
  → OldValue: NULL, NewValue: 456.78
```

### ❌ Not Captured (Excluded):
```
AE_Acknowledge "/:Alarm:*"
  → Not a "Write" operation

Write 'Hello' to 'tag'.
  → NewValue not numeric → NULL → Skipped

FactoryTalk Service operations
  → UserID filtered out
```

## Monitoring

### Check ETL Progress
```sql
SELECT * FROM ETL_Control 
WHERE TableName = 'Diagnostic' 
ORDER BY Location;
```

### Check Recent Data
```sql
SELECT TOP 10 * 
FROM DiagnosticStaging 
ORDER BY TimeStmp DESC;
```

### Find Missing Locations
```sql
SELECT DISTINCT d.Location
FROM Diagnostic d
WHERE d.Location IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM ETL_Control c
      WHERE c.TableName = 'Diagnostic' AND c.Location = d.Location
  );
```

## Troubleshooting

### No data in DiagnosticStaging
1. Run sync: `EXEC sp_Sync_ETL_Control_Locations;`
2. Check for "Write" operations in Diagnostic
3. Run ETL: `EXEC sp_ETL_Complete;`

### Missing locations
- Locations are auto-discovered in each ETL run
- Or manually sync: `EXEC sp_Sync_ETL_Control_Locations;`

### Primary key errors
- Ensure ETL_Control has composite primary key (TableName, Location)
- Not just single column

## Files Reference

| File | Purpose |
|------|---------|
| `scripts/02_create_sp_etl_v2.sql` | Main ETL procedure |
| `scripts/sp_Sync_ETL_Control_Locations.sql` | Location sync procedure |
| `scripts/sp_ETL_Complete.sql` | Combined procedure |
| `scripts/00_create_complete_etl.sql` | Complete setup from scratch |
| `helps/ETL_Implementation_Guide.md` | Full documentation |
| `helps/Location_Sync_Utility.md` | Sync utility guide |

## Quick Commands

```sql
-- Run complete ETL (recommended)
EXEC sp_ETL_Complete;

-- Just sync locations
EXEC sp_Sync_ETL_Control_Locations;

-- Just run ETL (assuming locations are synced)
EXEC sp_ETL_DiagnosticToStaging_v2;

-- Check status
SELECT Location, LastProcessedTime, LastUpdated FROM ETL_Control WHERE TableName = 'Diagnostic';

-- View results
SELECT TOP 10 * FROM DiagnosticStaging ORDER BY TimeStmp DESC;
```
