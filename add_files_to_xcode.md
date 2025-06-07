# Instructions to Add Analytics Files to Xcode

The Analytics tab is ready but the files need to be added to your Xcode project. Please follow these steps:

## In Xcode:

1. **Right-click on the WhoNext folder** in the project navigator (left sidebar)
2. Select **"Add Files to WhoNext..."**
3. Navigate to the WhoNext folder and select these 3 files:
   - `TimelineView.swift`
   - `ActivityHeatMapView.swift`
   - `AnalyticsView.swift`
4. Make sure **"Copy items if needed"** is UNCHECKED (files are already in place)
5. Make sure **"WhoNext"** target is checked
6. Click **"Add"**

## Then uncomment the Analytics code:

After adding the files, the Analytics tab code is ready but commented out. I'll uncomment it for you now.

## For Calendar Sync:

The calendar sync needs you to select which calendar to use:
1. Go to **Settings** (gear icon in toolbar)
2. Select your calendar that contains 1:1 meetings
3. The app will then show your upcoming meetings
