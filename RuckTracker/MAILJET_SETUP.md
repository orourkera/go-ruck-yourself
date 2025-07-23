# Mailjet Integration Setup

## Overview
The Ruck app now automatically syncs new user signups to Mailjet for email marketing. This happens for both regular email/password signups and Google OAuth signups.

## Heroku Environment Variables Required

Set these environment variables in your Heroku app:

```bash
# Required for Mailjet integration
MAILJET_API_KEY=your_mailjet_api_key_here
MAILJET_API_SECRET=your_mailjet_api_secret_here

# Optional - default contact list to add new users to
MAILJET_CONTACT_LIST_ID=your_list_id_here
```

## How to Get Mailjet Credentials

1. **Sign up for Mailjet** at https://www.mailjet.com/
2. **Get API credentials**:
   - Go to Account Settings → REST API → API Key Management
   - Copy your API Key and Secret Key
3. **Create a contact list** (optional):
   - Go to Contacts → Lists
   - Create a new list for Ruck app users
   - Copy the List ID from the URL or list settings

## Setting Environment Variables on Heroku

```bash
# Set the required variables
heroku config:set MAILJET_API_KEY=your_actual_api_key -a go-ruck-yourself
heroku config:set MAILJET_API_SECRET=your_actual_secret -a go-ruck-yourself

# Optional: Set default contact list
heroku config:set MAILJET_CONTACT_LIST_ID=your_list_id -a go-ruck-yourself
```

## What Gets Synced

When users sign up, the following data is sent to Mailjet:

### Contact Information
- **Email**: User's email address
- **Name**: User's display name/username
- **Ruck User ID**: Internal user ID for reference
- **Signup Date**: When they registered
- **Signup Source**: "mobile_app" or "google_oauth"

### Additional Metadata (if provided)
- **Gender**: From registration form
- **Date of Birth**: From registration form
- **Custom Properties**: Any additional fields can be added

## Integration Points

The Mailjet sync happens at these points in the user signup flow:

1. **Regular Signup** (`/api/auth/signup`)
   - After successful user record creation in database
   - Before returning success response to client

2. **Google OAuth Signup** (`/api/auth/profile` POST)
   - After successful user profile creation
   - Before returning profile data to client

## Error Handling

- **Non-blocking**: Mailjet sync failures won't prevent user registration
- **Comprehensive logging**: All sync attempts are logged for debugging
- **Graceful fallback**: If Mailjet is unavailable, users can still sign up normally

## Testing the Integration

1. **Test API connection**:
   ```python
   from services.mailjet_service import get_mailjet_service
   service = get_mailjet_service()
   success = service.test_connection()
   print(f"Mailjet connection: {'✅ Working' if success else '❌ Failed'}")
   ```

2. **Manual user sync**:
   ```python
   from services.mailjet_service import sync_user_to_mailjet
   success = sync_user_to_mailjet(
       email="test@example.com",
       username="Test User",
       user_metadata={"signup_source": "test"}
   )
   ```

## Monitoring

Check Heroku logs to monitor Mailjet sync activity:

```bash
heroku logs --tail -a go-ruck-yourself | grep -i mailjet
```

Look for log messages like:
- `✅ User email@example.com successfully synced to Mailjet`
- `⚠️ Failed to sync user email@example.com to Mailjet (non-blocking)`
- `❌ Mailjet sync error for email@example.com`

## Benefits

- **Automated email list building**: No manual export/import needed
- **Real-time sync**: Users are added immediately upon signup
- **Rich metadata**: Demographic and behavior data for targeted campaigns
- **Reliable**: Non-blocking implementation ensures user experience isn't affected
