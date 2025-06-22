# Android Background Location Tracking Fixes

## Problem Reported
User feedback: GPS distance stops updating during background operation around 1.5-2 mile mark, despite timer continuing correctly. Distance tracking resumes but remains permanently behind actual distance.

## Root Cause
Android's aggressive battery optimization (Doze Mode) and OEM-specific battery management systems throttle GPS location services even when using foreground services. This is especially problematic on Samsung, Xiaomi, Huawei, and other OEM devices.

## Comprehensive Solution Implemented

### 1. Enhanced LocationService (`location_service.dart`)

#### Improvements Made:
- **Reduced distance filter** from 5m to 3m for better tracking accuracy
- **Upgraded GPS accuracy** to `LocationAccuracy.bestForNavigation` for fitness tracking
- **Enhanced Android settings** with WiFi lock and improved notification
- **Location timeout detection** - restarts GPS if no updates for 30 seconds
- **Staleness checking** - requests fresh location if same position for 45 seconds
- **Automatic restart logic** - recovers from GPS service failures
- **Fresh location requests** - breaks out of stale GPS states

#### New Monitoring Features:
- `_locationTimeoutTimer` - Detects complete GPS failure
- `_stalenessCheckTimer` - Detects when GPS stops updating position
- `_restartLocationTracking()` - Automatically recovers from failures
- `_requestFreshLocation()` - Forces fresh GPS fix

### 2. Android Optimization Service (`android_optimization_service.dart`)

#### Critical Permissions Requested:
- `ACCESS_BACKGROUND_LOCATION` - Android 10+ background GPS
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` - Exemption from Doze Mode
- `SYSTEM_ALERT_WINDOW` - Helps prevent app process killing

#### OEM-Specific Handling:
- **Samsung**: Battery → Allow background activity
- **Xiaomi**: Battery saver → No restrictions
- **Huawei**: App launch → Manage manually
- **Generic**: Battery optimization whitelist

#### Features:
- Permission status checking and logging
- Manual setup instructions for users
- OEM device detection and specific tips
- Comprehensive permission diagnostics

### 3. Enhanced Android Manifest (`AndroidManifest.xml`)

#### Added Permissions:
```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
```

#### Existing Critical Permissions:
- `ACCESS_BACKGROUND_LOCATION` - Background GPS access
- `FOREGROUND_SERVICE_LOCATION` - Location foreground service
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` - Battery exemption
- `WAKE_LOCK` - Prevent CPU sleep during tracking

### 4. Session Start Integration

#### Enhanced Permission Checks:
- Comprehensive Android optimization status logging
- OEM-specific guidance for problematic devices
- Detailed permission status reporting
- Graceful degradation if permissions missing

## Technical Approach

### Location Restart Strategy:
1. **Monitor for timeouts** - No GPS updates for 30+ seconds
2. **Detect stale locations** - Same position for 45+ seconds  
3. **Automatic restart** - Cancel and restart GPS stream
4. **Fresh location request** - Force new GPS fix
5. **Error recovery** - Restart after GPS service errors

### Android Doze Protection:
1. **Battery optimization exemption** - Prevents system throttling
2. **Foreground service** - Maintains GPS priority
3. **Wake locks** - Prevents CPU sleep
4. **Enhanced notifications** - High-priority persistent notification

### User Experience:
- **Transparent operation** - Automatic recovery without user intervention
- **Detailed logging** - Comprehensive debugging information
- **Graceful degradation** - Session continues even with GPS issues
- **OEM guidance** - Specific instructions for problematic devices

## Testing Approach

### Scenarios to Test:
1. **Background operation** - Lock phone during ruck session
2. **App switching** - Use other apps during session
3. **Long sessions** - 2+ hour rucks to trigger doze mode
4. **OEM devices** - Test on Samsung, Xiaomi, etc.
5. **Poor GPS areas** - Indoor/urban canyon scenarios

### Expected Behavior:
- GPS should recover automatically from timeouts
- Distance tracking should remain accurate throughout session
- Logs should show restart attempts and recoveries
- No permanent distance loss during background operation

## Monitoring & Debugging

### Key Log Messages:
- `Location timeout detected - attempting restart`
- `Stale location detected - requesting fresh location`
- `Location tracking resumed successfully`
- `✅ All critical Android permissions granted`
- `⚠️ Battery optimization exemption denied`

### Permission Status Check:
```dart
final service = AndroidOptimizationService.instance;
await service.logOptimizationStatus();
```

This comprehensive solution addresses the reported Android background location tracking issues through multiple layers of protection and automatic recovery mechanisms.
