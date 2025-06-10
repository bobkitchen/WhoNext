-- Check the current state of Supabase data
-- Run this in your Supabase SQL Editor to see what's actually there

-- Count of people by deletion status
SELECT 
  is_deleted,
  COUNT(*) as count,
  'people' as table_name
FROM people 
GROUP BY is_deleted

UNION ALL

-- Count of conversations by deletion status  
SELECT 
  is_deleted,
  COUNT(*) as count,
  'conversations' as table_name
FROM conversations
GROUP BY is_deleted
ORDER BY table_name, is_deleted;

-- Sample of people records to check identifiers
SELECT 
  id,
  identifier,
  name,
  is_deleted,
  deleted_at,
  created_at
FROM people 
ORDER BY created_at DESC
LIMIT 10;
