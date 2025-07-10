#!/usr/bin/env python3
"""
Test script to debug backend push notification service
"""
import os
import sys
import json

# Add the RuckTracker directory to path
sys.path.append('/Users/rory/RuckingApp/RuckTracker')

from services.push_notification_service import PushNotificationService, get_user_device_tokens

def test_push_service():
    """Test the push notification service configuration and functionality"""
    
    print("🧪 TESTING BACKEND PUSH NOTIFICATION SERVICE")
    print("=" * 50)
    
    # 1. Check environment variables
    print("\n1. 🔧 ENVIRONMENT VARIABLES:")
    firebase_project_id = os.getenv('FIREBASE_PROJECT_ID')
    firebase_service_account_json = os.getenv('FIREBASE_SERVICE_ACCOUNT_JSON')
    firebase_service_account_path = os.getenv('FIREBASE_SERVICE_ACCOUNT_PATH')
    
    print(f"   FIREBASE_PROJECT_ID: {firebase_project_id or '❌ NOT SET'}")
    print(f"   FIREBASE_SERVICE_ACCOUNT_JSON: {'✅ SET' if firebase_service_account_json else '❌ NOT SET'}")
    print(f"   FIREBASE_SERVICE_ACCOUNT_PATH: {firebase_service_account_path or '❌ NOT SET'}")
    
    # 2. Initialize push service
    print("\n2. 🚀 INITIALIZING PUSH SERVICE:")
    try:
        push_service = PushNotificationService()
        print("   ✅ Push service initialized successfully")
    except Exception as e:
        print(f"   ❌ Failed to initialize push service: {e}")
        return
    
    # 3. Test with your actual FCM token
    print("\n3. 📱 TESTING WITH YOUR FCM TOKEN:")
    
    # Replace this with your actual FCM token from the logs
    test_fcm_token = input("Enter your FCM token from the app logs: ").strip()
    
    if not test_fcm_token:
        print("   ❌ No FCM token provided")
        return
        
    print(f"   Using token: {test_fcm_token[:20]}...")
    
    # 4. Test sending notification
    print("\n4. 📤 SENDING TEST NOTIFICATION:")
    try:
        success = push_service.send_notification(
            device_tokens=[test_fcm_token],
            title="Backend Test 🧪",
            body="This is a test from your backend service!",
            notification_data={'test': 'true'}
        )
        
        if success:
            print("   ✅ Notification sent successfully!")
            print("   📱 Check your phone for the notification")
        else:
            print("   ❌ Failed to send notification")
            
    except Exception as e:
        print(f"   ❌ Error sending notification: {e}")
        import traceback
        traceback.print_exc()
    
    # 5. Test device token lookup (optional)
    print("\n5. 🔍 TESTING DEVICE TOKEN LOOKUP:")
    user_id = input("Enter your user ID (optional, press Enter to skip): ").strip()
    
    if user_id:
        try:
            tokens = get_user_device_tokens([user_id])
            print(f"   Found {len(tokens)} tokens for user {user_id}")
            for i, token in enumerate(tokens):
                print(f"   Token {i+1}: {token[:20]}...")
        except Exception as e:
            print(f"   ❌ Error getting device tokens: {e}")
    else:
        print("   ⏭️ Skipped device token lookup")
    
    print("\n🧪 TEST COMPLETED")

if __name__ == "__main__":
    test_push_service()
