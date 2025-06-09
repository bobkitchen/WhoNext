-- EMERGENCY DATA RECOVERY SCRIPT
-- This will restore all soft-deleted records from today's sync
-- Run this IMMEDIATELY in your Supabase SQL Editor

-- Restore all people that were soft deleted today
UPDATE people 
SET is_deleted = FALSE, 
    deleted_at = NULL 
WHERE is_deleted = TRUE 
  AND deleted_at::date = CURRENT_DATE;

-- Restore all conversations that were soft deleted today  
UPDATE conversations 
SET is_deleted = FALSE, 
    deleted_at = NULL 
WHERE is_deleted = TRUE 
  AND deleted_at::date = CURRENT_DATE;

-- Check how many records we restored
SELECT 
  'People restored' as table_name,
  COUNT(*) as count
FROM people 
WHERE is_deleted = FALSE 
  AND updated_at::date = CURRENT_DATE

UNION ALL

SELECT 
  'Conversations restored' as table_name,
  COUNT(*) as count  
FROM conversations
WHERE is_deleted = FALSE
  AND updated_at::date = CURRENT_DATE;

COMMIT;
