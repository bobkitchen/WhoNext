-- Migration to add soft delete columns to existing Supabase tables
-- Run this in your Supabase SQL Editor

-- Add soft delete columns to people table
ALTER TABLE people 
ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Add soft delete columns to conversations table  
ALTER TABLE conversations
ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Add missing device_id columns (required for sync)
ALTER TABLE people
ADD COLUMN IF NOT EXISTS device_id TEXT;

ALTER TABLE conversations
ADD COLUMN IF NOT EXISTS device_id TEXT;

-- Add missing columns that our app expects
ALTER TABLE people
ADD COLUMN IF NOT EXISTS identifier TEXT,
ADD COLUMN IF NOT EXISTS photo_base64 TEXT,
ADD COLUMN IF NOT EXISTS timezone TEXT,
ADD COLUMN IF NOT EXISTS scheduled_conversation_date TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS is_direct_report BOOLEAN DEFAULT FALSE;

ALTER TABLE conversations
ADD COLUMN IF NOT EXISTS uuid TEXT,
ADD COLUMN IF NOT EXISTS person_identifier TEXT,
ADD COLUMN IF NOT EXISTS summary TEXT,
ADD COLUMN IF NOT EXISTS analysis_version TEXT,
ADD COLUMN IF NOT EXISTS key_topics TEXT,
ADD COLUMN IF NOT EXISTS quality_score DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS sentiment_label TEXT,
ADD COLUMN IF NOT EXISTS sentiment_score DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS last_analyzed TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS last_sentiment_analysis TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS legacy_id TIMESTAMPTZ;

-- Create indexes for the new columns
CREATE INDEX IF NOT EXISTS idx_people_is_deleted ON people(is_deleted);
CREATE INDEX IF NOT EXISTS idx_people_identifier ON people(identifier);
CREATE INDEX IF NOT EXISTS idx_people_device_id ON people(device_id);
CREATE INDEX IF NOT EXISTS idx_conversations_is_deleted ON conversations(is_deleted);
CREATE INDEX IF NOT EXISTS idx_conversations_uuid ON conversations(uuid);
CREATE INDEX IF NOT EXISTS idx_conversations_person_identifier ON conversations(person_identifier);
CREATE INDEX IF NOT EXISTS idx_conversations_device_id ON conversations(device_id);

-- Update existing records to have is_deleted = false (if they don't already)
UPDATE people SET is_deleted = FALSE WHERE is_deleted IS NULL;
UPDATE conversations SET is_deleted = FALSE WHERE is_deleted IS NULL;

-- Make is_deleted NOT NULL with default FALSE
ALTER TABLE people ALTER COLUMN is_deleted SET NOT NULL;
ALTER TABLE people ALTER COLUMN is_deleted SET DEFAULT FALSE;

ALTER TABLE conversations ALTER COLUMN is_deleted SET NOT NULL;
ALTER TABLE conversations ALTER COLUMN is_deleted SET DEFAULT FALSE;

COMMIT;
