# RuckingApp Watch Companion - Setup Guide

This guide will walk you through setting up the watchOS companion app for RuckingApp.

## Prerequisites

- Xcode 15.0 or later
- iOS device with paired Apple Watch running watchOS 10 or later
- Flutter development environment

## Step 1: Add watchOS Target in Xcode

1. Open Terminal and navigate to your Flutter project:
   ```
   cd /Users/rory/RuckingApp/rucking_app/ios
   ```

2. Open the Xcode workspace:
   ```
   open Runner.xcworkspace
   ```

3. In Xcode, go to File → New → Target
   - Select "Watch App" from the template options
   - Product Name: "RuckWatch"
   - Interface: SwiftUI
   - Language: Swift
   - Check "Include Notification Scene"
   - Make sure "Runner" is selected as the iOS App

4. When prompted to activate the new scheme, select "Activate"

## Step 2: Configure HealthKit Entitlements

1. Select the RuckWatch target in Xcode
2. Go to the "Signing & Capabilities" tab
3. Click "+ Capability" and add "HealthKit"
4. Create a new file named "RuckWatch.entitlements" with:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.developer.healthkit</key>
       <true/>
       <key>com.apple.developer.healthkit.access</key>
       <array>
           <string>health-records</string>
       </array>
   </dict>
   </plist>
   ```

5. In Info.plist for RuckWatch, add:
   ```xml
   <key>NSHealthShareUsageDescription</key>
   <string>This app needs access to your health data to track your rucking workouts</string>
   <key>NSHealthUpdateUsageDescription</key>
   <string>This app needs to save workout data to your Health app</string>
   ```

## Step 3: Copy Swift Files to Watch App

After creating the watch target, copy all the Swift files from the provided code to the appropriate locations in your RuckWatch target folder.

The main files to include are:
- ContentView.swift
- SessionManager.swift
- HealthKitManager.swift
- PrimaryMetricsView.swift
- SecondaryMetricsView.swift
- StartSessionView.swift

## Step 4: Testing Your Watch App

1. Connect your iPhone to your Mac
2. Make sure your Apple Watch is paired with your iPhone
3. In Xcode, select the "RuckWatch" scheme
4. Select your Apple Watch as the run destination
5. Click the Run button
6. The app should install on your Apple Watch

## Troubleshooting

### Common Issues

1. **WatchConnectivity Issues**
   - Ensure both iOS and watchOS apps have activated their WCSession
   - Check reachability status before sending immediate messages
   - Use transferUserInfo for non-urgent messages that can be delivered later
   - Monitor logs for session activation errors

2. **HealthKit Permissions**
   - Verify both iOS and watchOS apps have proper HealthKit entitlements
   - Check authorization status in HealthKitManager before attempting to read/write data
   - Use the Health app on the device to verify permissions are granted

3. **Flutter Integration Issues**
   - If Pigeon generated files have errors, regenerate them with:
     ```
     flutter pub run pigeon --input pigeons/rucking_api.dart
     ```
   - Ensure the WatchService is properly registered in your service locator
   - Check logs for any message handling errors between Flutter and native code

### Debugging

- Use `print` statements in both the iOS and watchOS code to track message flow
- Check the Xcode console for errors
- Test the watch app independently to verify HealthKit integration
- Use the Debug Navigator in Xcode to monitor CPU, memory, and network usage
