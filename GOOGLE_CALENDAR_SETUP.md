# Google Calendar Integration Setup Guide

## Current Status
The Google Calendar integration code is now in place but requires OAuth 2.0 credentials from Google Cloud Console to function.

## Setup Instructions

### 1. Create a Google Cloud Project
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Note your Project ID

### 2. Enable Google Calendar API
1. In the Google Cloud Console, go to "APIs & Services" > "Library"
2. Search for "Google Calendar API"
3. Click on it and press "Enable"

### 3. Configure OAuth Consent Screen
1. Go to "APIs & Services" > "OAuth consent screen"
2. Choose "External" for user type (or "Internal" if using Google Workspace)
3. Fill in the required fields:
   - App name: WhoNext
   - User support email: Your email
   - Developer contact: Your email
4. Add scopes:
   - `https://www.googleapis.com/auth/calendar.readonly`
   - `https://www.googleapis.com/auth/userinfo.email`
5. Add test users if in testing mode

### 4. Create OAuth 2.0 Credentials
1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth client ID"
3. Choose "iOS" as Application type (for macOS apps)
4. Set the Bundle ID: `com.bobk.whonext`
5. Download the credentials JSON file
6. Note the Client ID

### 5. Update the Code
1. Open `/WhoNext/GoogleCalendarProvider.swift`
2. Find the `GoogleOAuthConfig` struct (around line 389)
3. Replace `YOUR_CLIENT_ID.apps.googleusercontent.com` with your actual Client ID
4. The redirect URI should remain: `com.bobk.whonext:/oauth2redirect`

### 6. Configure URL Scheme in Xcode
1. Open `WhoNext.xcodeproj` in Xcode
2. Select the WhoNext target
3. Go to the "Info" tab
4. Under "URL Types", add a new URL Type:
   - Identifier: `com.bobk.whonext`
   - URL Schemes: `com.bobk.whonext`
   - Role: Editor

### 7. Test the Integration
1. Build and run the app
2. Go to Settings > Calendar
3. Click on "Google Calendar"
4. You should be redirected to Google's OAuth consent screen
5. Authorize the app
6. Your Google calendars should appear in the list

## Troubleshooting

### "Coming soon" error still appears
- Ensure you've updated the Client ID in GoogleCalendarProvider.swift
- Check that the URL scheme is properly configured in Info.plist
- Verify the Google Calendar API is enabled in Google Cloud Console

### Authentication fails
- Check that the redirect URI matches exactly: `com.bobk.whonext:/oauth2redirect`
- Ensure your OAuth consent screen is properly configured
- If using test users, make sure your Google account is added as a test user

### No calendars appear after authentication
- Verify the calendar.readonly scope is included in the OAuth consent
- Check that your Google account has calendars
- Look for error messages in Xcode's console

## Security Notes
- Never commit your Client ID to public repositories
- Consider using environment variables or a configuration file for credentials
- The client secret is not required for native apps using the authorization code flow with PKCE

## Next Steps
Once configured, the Google Calendar integration will:
- Allow users to sign in with their Google account
- Display their Google calendars in the calendar picker
- Fetch upcoming meetings from selected Google calendars
- Automatically refresh tokens when they expire
- Securely store credentials in the macOS Keychain


whonext-469411

654710857458-md2cpglkug04ah5ls0efn3oml7ev06gv.apps.googleusercontent.com

AIzaSyB_J8QM6rzEiRTH53RCHHFbc-XAXvgXZJw

