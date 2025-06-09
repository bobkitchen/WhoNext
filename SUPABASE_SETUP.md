# Supabase Setup Guide for WhoNext

## 🚀 Step 1: Create Supabase Project

1. Go to [supabase.com](https://supabase.com)
2. Sign up/Sign in
3. Click "New Project"
4. Choose organization and name your project "WhoNext"
5. Set a strong database password
6. Choose a region close to you
7. Click "Create new project"

## 🗄️ Step 2: Create Database Tables

Go to the SQL Editor in your Supabase dashboard and run this SQL:

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create people table
CREATE TABLE people (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    role TEXT,
    organization TEXT,
    email TEXT,
    phone TEXT,
    notes TEXT,
    key_topics TEXT[], -- Array of strings for topics
    last_contact_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    device_id TEXT NOT NULL
);

-- Create conversations table
CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    person_id UUID REFERENCES people(id) ON DELETE CASCADE,
    date TIMESTAMPTZ NOT NULL,
    duration INTEGER, -- Duration in minutes
    engagement_level TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    device_id TEXT NOT NULL
);

-- Create indexes for better performance
CREATE INDEX idx_people_name ON people(name);
CREATE INDEX idx_people_organization ON people(organization);
CREATE INDEX idx_people_updated_at ON people(updated_at);
CREATE INDEX idx_conversations_person_id ON conversations(person_id);
CREATE INDEX idx_conversations_date ON conversations(date);
CREATE INDEX idx_conversations_updated_at ON conversations(updated_at);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Add triggers to auto-update updated_at
CREATE TRIGGER update_people_updated_at 
    BEFORE UPDATE ON people 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_conversations_updated_at 
    BEFORE UPDATE ON conversations 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Enable Row Level Security (RLS)
ALTER TABLE people ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- Create policies (allow all operations for now - you can restrict later)
CREATE POLICY "Allow all operations on people" ON people
    FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Allow all operations on conversations" ON conversations
    FOR ALL USING (true) WITH CHECK (true);

-- Enable real-time subscriptions
CREATE PUBLICATION supabase_realtime;
ALTER PUBLICATION supabase_realtime ADD TABLE people;
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
```

## 🔑 Step 3: Get Your Credentials

1. Go to Settings → API in your Supabase dashboard
2. Copy your **Project URL** (looks like: `https://your-project.supabase.co`)
3. Copy your **anon public** key (starts with `eyJ...`)

## 📱 Step 4: Update WhoNext App

1. Open `SupabaseConfig.swift` in Xcode
2. Replace the placeholder values:
   ```swift
   private let supabaseURL = "https://your-actual-project.supabase.co"
   private let supabaseAnonKey = "your-actual-anon-key"
   ```

## 🧪 Step 5: Test the Integration

1. Build and run WhoNext
2. Go to Settings → Sync tab
3. Click "Sync Now"
4. Check your Supabase dashboard → Table Editor to see if data appears

## 🔄 Step 6: Enable Real-time (Optional)

In your Supabase dashboard:
1. Go to Database → Replication
2. Turn on replication for `people` and `conversations` tables
3. This enables real-time sync between devices

## 🚨 Troubleshooting

- **"Invalid API key"**: Double-check your anon key in `SupabaseConfig.swift`
- **"Network error"**: Verify your project URL is correct
- **"Permission denied"**: Check that RLS policies are set up correctly
- **No real-time updates**: Ensure replication is enabled for your tables

## 🎉 Success!

Once set up, your WhoNext app will:
- ✅ Sync data between all your devices
- ✅ Work offline and sync when reconnected
- ✅ Show real-time updates from other devices
- ✅ Be much more reliable than CloudKit!
