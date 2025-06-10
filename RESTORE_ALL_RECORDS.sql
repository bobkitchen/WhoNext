-- RESTORE ALL INCORRECTLY SOFT-DELETED RECORDS
-- This will restore all records that were incorrectly marked as deleted

-- First, let's see what we have
SELECT 'Before restore - People' as status, is_deleted, COUNT(*) as count
FROM people 
GROUP BY is_deleted

UNION ALL

SELECT 'Before restore - Conversations' as status, is_deleted, COUNT(*) as count  
FROM conversations
GROUP BY is_deleted;

-- Restore all people (they shouldn't all be deleted!)
UPDATE people 
SET is_deleted = FALSE, 
    deleted_at = NULL 
WHERE is_deleted = TRUE;

-- Restore all conversations (they shouldn't all be deleted!)
UPDATE conversations
SET is_deleted = FALSE,
    deleted_at = NULL
WHERE is_deleted = TRUE;

-- Check the results
SELECT 'After restore - People' as status, is_deleted, COUNT(*) as count
FROM people 
GROUP BY is_deleted

UNION ALL

SELECT 'After restore - Conversations' as status, is_deleted, COUNT(*) as count
FROM conversations  
GROUP BY is_deleted;

COMMIT;
