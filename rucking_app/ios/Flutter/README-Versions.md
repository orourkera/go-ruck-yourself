# Supported Versions

This directory contains configuration files that define the minimum supported versions for the RuckingApp project:

## SupportedVersions.xcconfig

This file defines the minimum deployment targets and Swift version:
- iOS: 14.0 (required for SwiftUI and specific UI components)
- watchOS: 9.0 (required for modern watchOS features)
- Swift: 5.0

## How to Use

When working on the project, ensure:

1. All new code adheres to these minimum version requirements
2. All Swift files in the Watch app include the `@available(watchOS 9.0, *)` annotation
3. UI components rely only on SwiftUI features available in iOS 14+ and watchOS 9+

## Making Changes

If you need to update the minimum supported versions:

1. Update the SupportedVersions.xcconfig file
2. Update the project.pbxproj file by opening Xcode and changing deployment targets
3. Update this README with the reasoning for the change
4. Check all Swift files for appropriate @available annotations

## Known Version Dependencies

- iOS 14.0: Required for SwiftUI, EnvironmentObject, and LazyVGrid components
- watchOS 9.0: Required for LazyVGrid, modern SwiftUI components
- Swift 5.0: Required for modern Swift language features

Last Updated: 2025-04-27
