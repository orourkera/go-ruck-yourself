# App Update API Specification

## Overview
This document specifies the backend API endpoints needed to support the app update system.

## Endpoints

### GET /api/app/version-info

Returns information about the latest app version and update requirements.

**Response:**
```json
{
  "latest_version": "2.8.4",
  "min_required_version": "2.7.0",
  "release_notes": [
    "🔧 Fixed elevation recovery in crash system",
    "📱 Improved app stability and performance", 
    "✨ Enhanced user experience",
    "🐛 Various bug fixes"
  ],
  "force_update_required": false,
  "download_urls": {
    "ios": "https://apps.apple.com/app/ruck-app/id6738063624",
    "android": "https://play.google.com/store/apps/details?id=com.getrucky.rucking_app"
  },
  "rollout_percentage": 100,
  "updated_at": "2025-01-25T10:00:00Z"
}
```

**Response Fields:**
- `latest_version`: The most recent version available in the app stores
- `min_required_version`: Minimum version required to use the app (for force updates)
- `release_notes`: Array of user-friendly feature descriptions
- `force_update_required`: Whether to show blocking update dialog
- `download_urls`: Platform-specific app store URLs
- `rollout_percentage`: Percentage of users who should see the update (for gradual rollout)
- `updated_at`: When this version info was last updated

## Implementation Examples

### Simple Static Implementation
```python
# Flask/FastAPI example
@app.get("/api/app/version-info")
def get_version_info():
    return {
        "latest_version": "2.8.4",
        "min_required_version": "2.7.0", 
        "release_notes": [
            "🔧 Fixed elevation recovery in crash system",
            "📱 Improved app stability and performance",
            "✨ Enhanced user experience"
        ],
        "force_update_required": False,
        "download_urls": {
            "ios": "https://apps.apple.com/app/ruck-app/id6738063624",
            "android": "https://play.google.com/store/apps/details?id=com.getrucky.rucking_app"
        },
        "rollout_percentage": 100,
        "updated_at": "2025-01-25T10:00:00Z"
    }
```

### Database-Driven Implementation
```sql
-- version_info table
CREATE TABLE app_versions (
    id SERIAL PRIMARY KEY,
    version VARCHAR(20) NOT NULL,
    min_required_version VARCHAR(20),
    release_notes JSONB,
    force_update BOOLEAN DEFAULT FALSE,
    ios_url TEXT,
    android_url TEXT,
    rollout_percentage INTEGER DEFAULT 100,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Insert current version
INSERT INTO app_versions (
    version,
    min_required_version,
    release_notes,
    force_update,
    ios_url,
    android_url,
    rollout_percentage
) VALUES (
    '2.8.4',
    '2.7.0',
    '["🔧 Fixed elevation recovery", "📱 Improved stability"]',
    FALSE,
    'https://apps.apple.com/app/ruck-app/id6738063624',
    'https://play.google.com/store/apps/details?id=com.getrucky.rucking_app',
    100
);
```

### Advanced Features (Optional)

#### Gradual Rollout Support
```python
@app.get("/api/app/version-info")
def get_version_info(user_id: str = None):
    version_info = get_latest_version_info()
    
    # Gradual rollout logic
    if user_id and version_info['rollout_percentage'] < 100:
        user_hash = hash(user_id) % 100
        if user_hash >= version_info['rollout_percentage']:
            # Return previous version for this user
            version_info = get_previous_version_info()
    
    return version_info
```

#### Platform-Specific Versions
```python
@app.get("/api/app/version-info")
def get_version_info(platform: str = None):
    base_info = get_base_version_info()
    
    if platform == "ios":
        # iOS might be on a different version due to review delays
        base_info["latest_version"] = "2.8.4"
    elif platform == "android":
        base_info["latest_version"] = "2.8.5"
    
    return base_info
```

## Security Considerations

1. **Rate Limiting**: Implement rate limiting on the endpoint (e.g., 10 requests per minute per IP)
2. **Caching**: Cache responses appropriately to reduce server load
3. **Authentication**: Endpoint can be public, but consider basic authentication for admin updates
4. **HTTPS**: Always serve over HTTPS to prevent tampering

## Monitoring & Analytics

Consider logging:
- App version distribution
- Update prompt acceptance rates
- Force update triggers
- Platform-specific adoption rates

## Admin Interface (Optional)

Create an admin interface to:
- Update version information
- Toggle force update requirements
- Manage rollout percentages
- View adoption statistics

## Error Handling

The app should gracefully handle:
- Network errors (continue without update check)
- Invalid JSON responses (log error, continue)
- Missing fields (use sensible defaults)
- Server errors (retry with exponential backoff)

## Testing

Test scenarios:
1. Normal update available
2. Force update required  
3. No update available
4. Server error responses
5. Network timeouts
6. Invalid version formats
7. Gradual rollout percentages
