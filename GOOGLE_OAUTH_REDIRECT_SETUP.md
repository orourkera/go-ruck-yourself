# Google OAuth Redirect URI Configuration

## Issue Fixed
The Google OAuth redirect URIs were inconsistent with the actual app bundle identifiers, causing "access blocked: the app's request is invalid" errors.

## Updated Configuration
The redirect URIs have been updated in `simplified_auth_service.dart` to match the actual bundle IDs:

- **iOS**: `com.getrucky.gfy://login`
- **Android**: `com.ruck.app://login`

## Required Supabase Dashboard Updates

### 1. Go to Supabase Dashboard
- Navigate to your project dashboard
- Go to Authentication → Settings → URL Configuration

### 2. Update Site URL
Make sure your Site URL is set correctly (usually your production domain)

### 3. Update Redirect URLs
Add these redirect URLs to the "Redirect URLs" section:
```
com.getrucky.gfy://login
com.ruck.app://login
```

### 4. Google Cloud Console Configuration
You also need to update your Google Cloud Console OAuth configuration:

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to APIs & Services → Credentials
3. Find your OAuth 2.0 Client ID for the mobile app
4. Add the following authorized redirect URIs:
   - `com.getrucky.gfy://login`
   - `com.ruck.app://login`

### 5. Bundle Identifiers Reference
- **iOS Bundle ID**: `com.getrucky.gfy` (from Runner.xcodeproj)
- **Android Package Name**: `com.ruck.app` (from build.gradle.kts)

## Testing
After updating both Supabase and Google Cloud Console:
1. Clean and rebuild the app: `flutter clean && flutter pub get`
2. Test Google OAuth on both iOS and Android devices
3. The "access blocked" error should be resolved

## Notes
- Custom URL schemes must match the bundle identifier exactly
- Both Supabase and Google Cloud Console need to have matching redirect URIs
- Make sure your app is properly configured to handle these deep links
