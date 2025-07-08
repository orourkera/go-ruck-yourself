# App Encryption Documentation - Rucking App

## Encryption Usage Summary
**Answer to Apple's Questions: NO to both**

The Rucking app uses only standard encryption algorithms provided by Apple's iOS operating system and widely-accepted industry standards. No proprietary or non-standard encryption is implemented.

## Detailed Encryption Usage

### 1. Network Communications
- **HTTPS/TLS 1.2+**: All API communications with backend services
- **Firebase SDK**: Standard Google Firebase encryption for push notifications and analytics
- **Standard**: Uses OS-provided encryption, no custom implementation

### 2. Local Data Storage
- **Flutter Secure Storage**: Utilizes iOS Keychain for secure token storage
- **SQLite**: Standard database storage without additional encryption layers
- **Standard**: Relies entirely on iOS-provided security mechanisms

### 3. Authentication & Tokens
- **OAuth 2.0/JWT**: Standard authentication token handling
- **API Keys**: Stored using iOS Keychain via Flutter Secure Storage
- **Standard**: Industry-standard authentication protocols only

### 4. Payment Processing (if applicable)
- **RevenueCat/App Store**: Uses Apple's standard payment encryption
- **Standard**: No custom payment encryption implementation

### 5. Health & Location Data
- **HealthKit Integration**: Uses Apple's standard HealthKit encryption
- **Core Location**: Standard iOS location services encryption
- **Standard**: Entirely dependent on Apple's OS-level encryption

## Certification Statement

**The Rucking app:**
- ✅ Uses **ONLY** standard encryption algorithms accepted by international bodies (IEEE, IETF, ITU)
- ✅ Does **NOT** implement any proprietary encryption algorithms
- ✅ Relies **EXCLUSIVELY** on encryption provided by Apple's iOS operating system
- ✅ Does **NOT** access or modify the OS encryption implementation
- ✅ Uses standard HTTPS/TLS for all network communications
- ✅ Uses standard iOS Keychain for secure storage via Flutter Secure Storage

**Therefore:**
- **Question 1**: NO - Does not use proprietary encryption
- **Question 2**: NO - Does not use encryption beyond what's provided by iOS

This app is **exempt from export control requirements** under Category 5 Part 2 as it uses only standard, publicly available encryption.

## Compliance Notes
- **Generated**: January 8, 2025
- **App Version**: 2.6.0+
- **Platform**: iOS/Android Flutter Application
- **Classification**: Standard Encryption Only - Export Exempt

For submission to Apple App Store Connect or regulatory authorities.
