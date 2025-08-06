# 🌐 Firebase Remote Config Setup Guide

This guide shows how to configure Firebase Remote Config for instant feature flag control.

## 🎯 Overview

With Firebase Remote Config, you can:
- ✅ **Toggle features instantly** without app store deployments
- ✅ **Gradual rollout** - Enable for percentage of users
- ✅ **A/B testing** - Test different feature combinations
- ✅ **Emergency kill switches** - Disable features immediately
- ✅ **Production debugging** - Enable logging remotely

## 🔧 Firebase Console Setup

### 1. Access Remote Config
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your RuckingApp project
3. Navigate to **Engage > Remote Config**

### 2. Create Feature Flag Parameters

Add these parameters with the following **default values**:

#### Auth System Flags
```
Parameter: use_simplified_auth
Default value: false
Description: Master toggle for simplified auth system (enables all new auth features)
```

> 📝 **Note**: This single flag now controls ALL simplified auth features:
> - Direct Supabase signIn/signUp (no custom backend auth)
> - Automatic token refresh via Supabase SDK  
> - Native auth state listeners
> - Streamlined auth flow
> 
> No need for multiple granular flags - just toggle this one master switch!

> 🎉 **That's it!** Just one parameter to configure. All safety features, rollout control, and emergency switches are built into the app code with sensible defaults.

### 3. Publish Configuration
1. Click **"Publish changes"** in Firebase Console
2. Add a description like "Initial feature flag setup"
3. Confirm publication

## 🚀 Usage Examples

### Safe Testing (Debug Mode Only)
```
use_simplified_auth: false (keeps production safe - only works in debug mode)
```

### Production Rollout
```
use_simplified_auth: true (enables all simplified auth features for all users)
```

### Emergency Rollback
```
use_simplified_auth: false (instant rollback to legacy auth)
```

> 🎉 **Ultra Simple!** Just flip one switch for everything!

## 📱 App Integration Status

✅ **Remote Config Service** - Handles fetching and caching
✅ **Feature Flags Integration** - All flags now use remote config
✅ **Automatic Fallbacks** - Safe defaults if remote config fails
✅ **Debug Screen** - Monitor and refresh remote config
✅ **App Initialization** - Remote config loaded on startup

## 🛡️ Safety Features

### Automatic Fallbacks
- If remote config fails to load, uses hardcoded safe defaults
- Debug mode defaults to simplified auth enabled
- Production mode defaults to legacy auth enabled

### Emergency Controls
- `emergency_disable_all_flags` - Instant kill switch
- `auth_rollout_percentage` - Control user exposure
- Always-enabled fallback to legacy auth

### Gradual Rollout
- Start with 0% rollout in production
- Gradually increase percentage: 5% → 25% → 50% → 100%
- Monitor for issues before increasing

## 🔍 Monitoring & Debugging

### Debug Screen Access
In debug mode, use the feature flag debug screen to:
- See current remote config status
- View active flag values
- Force refresh configuration
- Test auth system

### Log Monitoring
Watch for these log messages:
```
🌐 [REMOTE_CONFIG] Initializing Firebase Remote Config...
✅ [REMOTE_CONFIG] Successfully initialized with X parameters
🔧 [REMOTE_CONFIG] use_simplified_auth: true
🆕 [AUTH_WRAPPER] Using simplified sign-in
```

### Firebase Console Analytics
- View parameter fetch success rates
- Monitor parameter activation
- See user segments affected by each parameter

## 🚨 Troubleshooting

### Common Issues

**Issue**: Remote config not loading
**Solution**: Check Firebase project configuration and network connectivity

**Issue**: Parameters not updating
**Solution**: 
1. Check if minimum fetch interval has passed (1 hour in production)
2. Force refresh using debug screen
3. Verify parameters are published in Firebase Console

**Issue**: Features not enabling despite remote config
**Solution**: Check `auth_rollout_percentage` and `emergency_disable_all_flags`

### Debug Commands
```dart
// Check remote config status
final debugInfo = FeatureFlags.getRemoteConfigDebugInfo();
print('Remote config initialized: ${debugInfo['isInitialized']}');

// Force refresh (debug screen)
await FeatureFlags.forceRefreshRemoteConfig();

// Check current values
final flags = FeatureFlags.getAuthFeatureStatus();
print('Current flags: $flags');
```

## 📈 Recommended Rollout Strategy

### Phase 1: Setup (Current)
- ✅ Configure all parameters in Firebase Console
- ✅ Set all auth flags to `false` in production
- ✅ Set `auth_rollout_percentage` to `0`
- ✅ Test in debug mode only

### Phase 2: Limited Testing
- Set `auth_rollout_percentage` to `5`
- Enable `use_direct_supabase_signin` only
- Monitor for 1-2 days

### Phase 3: Gradual Rollout
- Increase `auth_rollout_percentage`: 5% → 25% → 50%
- Enable additional features one by one
- Monitor error rates and user feedback

### Phase 4: Full Migration
- Set `auth_rollout_percentage` to `100`
- Enable all simplified auth features
- Plan removal of legacy code

### Emergency Procedures
- **Immediate rollback**: Set `emergency_disable_all_flags` to `true`
- **Gradual rollback**: Reduce `auth_rollout_percentage` to `0`
- **Feature-specific rollback**: Disable individual feature flags

## 🎉 Benefits Achieved

✅ **Zero deployment time** - Instant feature control
✅ **Risk mitigation** - Gradual rollout and instant rollback
✅ **A/B testing capability** - Test features with user segments
✅ **Production debugging** - Remote logging control
✅ **Operational flexibility** - No app store approval needed

---

**Remember**: Always test changes thoroughly in debug mode before enabling in production!
