#!/usr/bin/env python3
"""
Test script to verify push notification functionality
Run this from the RuckTracker directory
"""
import os
import sys
sys.path.append('RuckTracker')

from RuckTracker.services.push_notification_service import PushNotificationService, get_user_device_tokens

def test_push_notifications():
    """Test push notification service"""
    
    print("🔔 Testing Push Notification System")
    print("=" * 50)
    
    # Check environment variables
    print("1. Checking environment variables...")
    firebase_project_id = os.getenv('FIREBASE_PROJECT_ID')
    firebase_service_account = os.getenv('FIREBASE_SERVICE_ACCOUNT_PATH')
    
    if not firebase_project_id:
        print("❌ FIREBASE_PROJECT_ID not set")
        return False
    else:
        print(f"✅ FIREBASE_PROJECT_ID: {firebase_project_id}")
    
    if not firebase_service_account:
        print("❌ FIREBASE_SERVICE_ACCOUNT_PATH not set")
        return False
    else:
        print(f"✅ FIREBASE_SERVICE_ACCOUNT_PATH: {firebase_service_account}")
        if not os.path.exists(firebase_service_account):
            print(f"❌ Service account file doesn't exist: {firebase_service_account}")
            return False
    
    # Initialize push service
    print("\n2. Initializing push notification service...")
    try:
        push_service = PushNotificationService()
        print("✅ Push notification service initialized")
    except Exception as e:
        print(f"❌ Failed to initialize push service: {e}")
        return False
    
    # Test getting device tokens (replace with your user ID)
    print("\n3. Testing device token retrieval...")
    print("Enter your user ID to test (or press Enter to skip):")
    user_id = input().strip()
    
    if user_id:
        try:
            device_tokens = get_user_device_tokens([user_id])
            if device_tokens:
                print(f"✅ Found {len(device_tokens)} device token(s)")
                
                # Send test notification
                print("\n4. Sending test achievement notification...")
                success = push_service.send_achievement_notification(
                    device_tokens=device_tokens,
                    achievement_name="Test Achievement",
                    achievement_id="test_123",
                    session_id="test_session"
                )
                
                if success:
                    print("✅ Test notification sent successfully!")
                    print("Check your phone for the notification.")
                else:
                    print("❌ Failed to send test notification")
                    
            else:
                print("❌ No device tokens found for user")
        except Exception as e:
            print(f"❌ Error testing device tokens: {e}")
    else:
        print("⏭️  Skipping device token test")
    
    return True

if __name__ == "__main__":
    success = test_push_notifications()
    if success:
        print("\n🎉 Push notification system test completed!")
    else:
        print("\n💥 Push notification system has issues that need fixing")
