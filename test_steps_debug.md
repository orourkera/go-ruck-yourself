# Step Tracking Debug Guide

## Issues Fixed Based on Web Research:

1. **Fresh Permission Checking**: Now uses `hasPermissions()` to check current authorization status instead of relying on cached `_isAuthorized`
2. **Robust Authorization**: Added HealthKit availability check and post-authorization permission verification  
3. **Multiple Retrieval Methods**: Tries `getTotalStepsInInterval()` first, then falls back to `getHealthDataFromTypes()`
4. **Better Error Handling**: More detailed logging at each step to identify where failures occur
5. **Increased Delay**: Extended authorization delay to 500ms to ensure iOS UI is ready

## How to Test:

### Step 1: Enable Live Step Tracking
1. Open the app → Profile → Turn ON "Live Step Tracking" toggle
2. Start a new ruck session
3. When prompted, **allow all HealthKit permissions**

### Step 2: Check Logs
Look for these debug messages in Flutter logs:
```
[STEPS DEBUG] getStepsBetween called: <start> to <end>
[STEPS DEBUG] Fresh permission check for STEPS: true/false
[STEPS DEBUG] Method 1: Calling health.getTotalStepsInInterval...
[STEPS DEBUG] getTotalStepsInInterval success: <number>
```

### Step 3: Verify Health App
1. Open iOS Health app
2. Go to Browse → Activity → Steps
3. Verify there's step data for the time period of your ruck

### Common Issues:
- **Permission Denied**: User denied HealthKit access → Re-enable in Settings > Privacy & Security > Health
- **No Data**: Health app has no step data for the time period → Walk around to generate data first
- **Authorization Failed**: HealthKit not properly enabled → Check entitlements and capabilities

### Fallback Behavior:
Even if HealthKit fails, the app will now estimate steps from distance:
- Uses 0.75m step length for rucking with weight
- Your 3.66km ruck would estimate ~4,880 steps
