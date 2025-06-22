# Google Places API Setup Guide

## Overview
The app has been upgraded from the basic `geocoding` package to Google Places API for better location search results, including business names, landmarks, and more accurate location data.

## Changes Made

### 1. **New Google Places Service**
- Created `lib/core/services/google_places_service.dart`
- Supports both Text Search and Autocomplete APIs
- Better business name and landmark recognition
- More accurate location results

### 2. **Updated Components**
- **Club Creation/Editing**: Now uses Google Places for location search
- **Event Creation/Editing**: Now uses Google Places for location search
- **Service Locator**: Registered GooglePlacesService instead of LocationSearchService

### 3. **Dependencies Updated**
- Added `google_places_flutter: ^2.1.0` to pubspec.yaml
- Removed dependency on basic geocoding package

## Setup Instructions

### Step 1: Get Google Places API Key
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing project
3. Enable the following APIs:
   - **Places API (New)** 
   - **Geocoding API**
   - **Maps JavaScript API** (if using web)

### Step 2: Create API Key
1. Go to "Credentials" in Google Cloud Console
2. Click "Create Credentials" > "API Key"
3. Copy the generated API key
4. **Restrict the API key** (recommended):
   - Application restrictions: Set to your app's package name
   - API restrictions: Limit to Places API, Geocoding API

### Step 3: Configure API Key
1. Open `lib/core/services/google_places_service.dart`
2. Find the `GooglePlacesConfig` class at the top
3. Replace `'YOUR_GOOGLE_PLACES_API_KEY'` with your actual API key:

```dart
class GooglePlacesConfig {
  static const String apiKey = 'AIzaSyC...your-actual-key-here';
  static bool get isConfigured => apiKey != 'YOUR_GOOGLE_PLACES_API_KEY' && apiKey.isNotEmpty;
}
```

### Step 4: Test the Integration
1. Build and run the app
2. Try creating a club or event
3. Search for locations - you should see better business/landmark results
4. Check logs for any "API key not configured" messages

## Benefits of Google Places API

### ✅ **Improved Search Results**
- **Business Names**: Find restaurants, gyms, coffee shops by name
- **Landmarks**: Parks, monuments, popular destinations
- **Addresses**: More accurate street addresses
- **POI Data**: Points of interest with detailed information

### ✅ **Better User Experience**
- **Faster Results**: Optimized search with autocomplete
- **More Relevant**: Results ranked by relevance and popularity
- **Rich Data**: Additional details like place types, ratings, etc.

### ✅ **Global Coverage**
- Works worldwide with consistent quality
- Multi-language support
- Real-time data updates

## API Usage & Costs

### **Pricing** (as of 2024)
- **Text Search**: $32 per 1,000 requests
- **Autocomplete**: $2.83 per 1,000 requests (session-based)
- **Place Details**: $17 per 1,000 requests

### **Free Tier**
- Google provides $200 free credits monthly
- Equivalent to ~6,250 text searches per month
- Monitor usage in Google Cloud Console

### **Optimization Tips**
- Service includes debouncing to reduce API calls
- Uses session-based autocomplete when possible
- Limits results to prevent excessive calls

## Troubleshooting

### **"API key not configured" Error**
- Ensure you've replaced the placeholder API key
- Check that `GooglePlacesConfig.apiKey` contains your real key

### **"API Error" Messages**
- Verify API key is correct
- Ensure Places API is enabled in Google Cloud Console
- Check API key restrictions aren't blocking your app

### **No Search Results**
- Verify internet connection
- Check Google Cloud Console for API quotas/billing
- Review logs for specific error messages

### **Permission Errors**
- Make sure API key has permissions for Places API
- Check if key restrictions are too strict

## Migration Notes

### **From LocationSearchService**
- All location search now goes through GooglePlacesService
- Same `LocationSearchResult` interface maintained
- Added `placeId` field for Google Places integration
- Improved search quality and business name recognition

### **Backward Compatibility**
- UI remains the same for users
- Same search flow and result display
- Enhanced results with better accuracy

## Next Steps

1. **Set up your API key** following steps above
2. **Test thoroughly** with various location searches  
3. **Monitor API usage** in Google Cloud Console
4. **Consider implementing** place details for enhanced features
5. **Set up billing alerts** to track API costs

---

**Important**: Don't commit your API key to version control! Consider using environment variables or secure configuration management for production builds.
