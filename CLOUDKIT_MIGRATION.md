# iCloud CloudKit Migration

## Overview
Migrated from Supabase sync to iCloud CloudKit for simpler, native sync between devices.

## Changes Made (January 5, 2026)

### 1. Persistence.swift
**Location:** `WhoNext/Persistence.swift`

**Changes:**
- Changed from `NSPersistentContainer` to `NSPersistentCloudKitContainer`
- Added CloudKit import: `import CloudKit`
- Enabled persistent history tracking (required for CloudKit)
- Added remote change notification support

**Key Configuration:**
```swift
// CloudKit container
container = NSPersistentCloudKitContainer(name: modelName,
                                          managedObjectModel: model)

// Persistent history tracking (required for CloudKit)
store.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
store.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

// Auto-merge changes from iCloud
container.viewContext.automaticallyMergesChangesFromParent = true
container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
```

### 2. Entitlements
**Location:** `WhoNext/WhoNext.entitlements`

**Added:**
```xml
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.bobkitchen.WhoNext</string>
</array>
```

### 3. Core Data Model
**Location:** `WhoNext/WhoNext.xcdatamodeld/WhoNext.xcdatamodel/contents`

**Status:** Already CloudKit-compatible
- All entities marked `syncable="YES"`
- UUID identifiers present on all main entities (Person, Conversation, Group, GroupMeeting)
- Transformable attributes use NSSecureUnarchiveFromDataTransformer
- Binary data with external storage properly configured

### 4. Disabled Supabase Sync Code
**Location:** Multiple files

**Changes Made:**
- **WhoNextApp.swift (line 111):** Disabled `triggerLaunchSync()` - no longer triggers Supabase sync on app launch
- **RobustSyncManager.swift (line 1373):** Disabled `validateConnectivity()` - no longer checks Supabase connection health
- **RobustSyncManager.swift (line 590):** Disabled `performSync()` - returns success without making Supabase API calls
- **RobustSyncManager.swift (line 1634):** Disabled `triggerSync()` - does nothing instead of triggering Supabase sync

All these methods now print CloudKit status messages and return immediately, preventing any Supabase API calls.

## How iCloud Sync Works

1. **Automatic Sync:** NSPersistentCloudKitContainer automatically syncs Core Data changes to iCloud
2. **Merge Policy:** Changes from iCloud are automatically merged using property-level merge
3. **Persistent History:** Tracks all changes for efficient sync
4. **No Manual Code Required:** CloudKit handles all sync operations automatically

## Important Notes

### iCloud Container
- Container ID: `iCloud.com.bobkitchen.WhoNext`
- This must match your Apple Developer account and app bundle ID
- Ensure the container is created in the Apple Developer Portal with CloudKit enabled

### First Run After Migration
- Existing local data will be uploaded to iCloud on first run
- This may take some time depending on database size
- Ensure you're signed into iCloud on all devices

### Testing Sync
1. Sign into iCloud on both Macs
2. Run app on first Mac, make changes (add person, meeting, etc.)
3. Quit app and relaunch on second Mac
4. Changes should appear after a few moments
5. Look for "Core Data store loaded successfully" in console logs

## Rollback Instructions

If you need to rollback to Supabase:

1. **Restore Persistence.swift backup:**
   ```bash
   cp WhoNext/Persistence.swift.backup WhoNext/Persistence.swift
   ```

2. **Restore entitlements:**
   Remove the CloudKit entries from `WhoNext.entitlements`

3. **Re-enable Supabase code:**
   The Supabase package dependency is still in the project, just not being used.
   RobustSyncManager and related files are still present if needed.

## Files Not Modified (Kept for Rollback)

- `RobustSyncManager.swift` - Custom Supabase sync code
- `Package.swift` - Still includes Supabase dependency
- All Supabase-related Swift files remain in project

## Next Steps

### After Testing
Once you confirm CloudKit sync is working on both devices:
1. Remove Supabase package dependency from project
2. Delete RobustSyncManager.swift and related sync files
3. Clean up any Supabase API key settings from SettingsView

### Monitoring Sync
Monitor console logs for:
- "Core Data store loaded successfully" - Store initialized properly
- CloudKit sync messages (if verbose logging enabled)
- Any "NSPersistentCloudKitContainer" errors

## Troubleshooting

### Sync Not Working
1. Check iCloud is signed in on both devices
2. Verify container ID matches in Developer Portal
3. Check CloudKit Dashboard in Developer Portal for data
4. Ensure app has iCloud Drive permission in System Settings

### Build Errors
1. Ensure Xcode version supports CloudKit (Xcode 11+)
2. Verify entitlements file is properly linked in project settings
3. Check that Team ID is set in Xcode project settings

### Data Not Appearing
1. CloudKit sync is eventual - allow 30-60 seconds
2. Force quit and relaunch app on second device
3. Check Console.app for CloudKit or Core Data errors
4. Verify network connectivity

## Technical Details

### What Changed Under the Hood
- **Before:** Manual REST API calls to Supabase + custom conflict resolution
- **After:** Apple's native CloudKit with automatic sync and conflict resolution
- **Benefit:** Less code, more reliable, better battery life, works offline

### CloudKit Private Database
- All data is stored in the user's private CloudKit database
- Data is encrypted in transit and at rest
- Each user's data is isolated (no sharing between accounts)
- Free tier includes 1GB storage per user

## References
- [Apple: Setting Up Core Data with CloudKit](https://developer.apple.com/documentation/coredata/mirroring_a_core_data_store_with_cloudkit)
- [NSPersistentCloudKitContainer Documentation](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer)
