-- Quick fix for missing device_id columns
-- Run this in your Supabase SQL Editor to fix the sync error

-- Add device_id column to people table
ALTER TABLE people
ADD COLUMN IF NOT EXISTS device_id TEXT;

-- Add device_id column to conversations table  
ALTER TABLE conversations
ADD COLUMN IF NOT EXISTS device_id TEXT;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_people_device_id ON people(device_id);
CREATE INDEX IF NOT EXISTS idx_conversations_device_id ON conversations(device_id);

-- Verify the columns were added
SELECT 'people table columns:' as info;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'people' 
AND column_name IN ('device_id', 'is_deleted', 'deleted_at')
ORDER BY column_name;

SELECT 'conversations table columns:' as info;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'conversations' 
AND column_name IN ('device_id', 'is_deleted', 'deleted_at')
ORDER BY column_name;
