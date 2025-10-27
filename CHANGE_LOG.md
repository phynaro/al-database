# Change Log

## Latest Update: Include Writes Without Previous Value

### Date
Current

### Change Summary
Modified the ETL stored procedure to include write operations that don't have a "Previous value was" statement.

### What Changed

**Before:**
```sql
WHERE [OldValue] IS NOT NULL 
  AND [NewValue] IS NOT NULL;
```
Only extracted records where BOTH OldValue and NewValue were available.

**After:**
```sql
WHERE [NewValue] IS NOT NULL;
```
Extracts records where NewValue is available, allowing OldValue to be NULL.

### Impact

**New Behavior:**
- ✅ Includes write operations like: `Write '123' to 'U3\Machine\tag'.`
- ✅ OldValue = NULL for these records
- ✅ NewValue is still captured (e.g., 123.0)
- ✅ Still captures writes with previous value: `Write 'True' to 'tag'. Previous value was 'False'.`

### Examples

#### Example 1: Write WITH Previous Value
```
MessageText: "Write 'True' to 'U2\HS012\Confirm'. Previous value was 'False'."
Result:
  - OldValue: 0.0 (False)
  - NewValue: 1.0 (True)
  - ✅ Inserted
```

#### Example 2: Write WITHOUT Previous Value (NEW)
```
MessageText: "Write '123' to 'U3\Machine\tag'."
Result:
  - OldValue: NULL
  - NewValue: 123.0
  - ✅ Inserted (previously skipped)
```

#### Example 3: Write with Non-Numeric Value
```
MessageText: "Write 'Hello' to 'U3\Machine\tag'."
Result:
  - OldValue: NULL
  - NewValue: NULL (not numeric)
  - ❌ Skipped (NewValue is NULL)
```

### Files Modified

1. `scripts/02_create_sp_etl_v2.sql` - Line 131
2. `scripts/00_create_complete_etl.sql` - Line 219

### Migration Notes

- No database schema changes required
- Existing DiagnosticStaging table supports NULL values in OldValue column
- No impact on existing records
- Simply run the updated stored procedure to start capturing these additional records

### Testing

To verify the change works:

```sql
-- Test query to see writes without previous value
SELECT TOP 10
    Location,
    TimeStmp,
    MessageText
FROM Diagnostic
WHERE MessageText LIKE 'Write%to%'
  AND MessageText NOT LIKE '%Previous value was%'
  AND UserID <> 'FactoryTalk Service'
ORDER BY TimeStmp DESC;

-- After running ETL, check for NULL OldValue records
SELECT 
    COUNT(*) AS RecordsWithoutOldValue
FROM DiagnosticStaging
WHERE OldValue IS NULL AND NewValue IS NOT NULL;
```

### Business Value

- Captures more complete audit trail
- No data loss for write operations without previous value tracking
- Maintains data integrity with NULL for unknown previous values
