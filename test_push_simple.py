#!/usr/bin/env python3
"""
Simple test script for Heroku push notification service
"""
import os
import logging
import time
from services.push_notification_service import PushNotificationService

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_push_notification():
    """Test push notification with hardcoded FCM token"""
    
    print("🧪 TESTING PUSH NOTIFICATIONS ON HEROKU")
    print("=" * 50)
    
    # Your FCM token from the diagnostic logs
    FCM_TOKEN = "dsoCTDrtb00GkCZieamvNZ:APA91bE_OiXgR3JIro6tGGZm7Bg2JzgsRiVmRj2QrWgioZAG3XhIY9Z3SmEcPThBiO2_KBvlTqqzBmzcVnY2fAdR1W1xKhQ0sTH_C52Anl09W0D-lpEs6e8"
    
    print(f"📱 Testing with token: {FCM_TOKEN[:20]}...")
    
    try:
        # Initialize push service
        push_service = PushNotificationService()
        print("✅ Push service initialized")
        
        # Send test notification
        success = push_service.send_notification(
            device_tokens=[FCM_TOKEN],
            title="Heroku Test 🚀",
            body="Push notification test from Heroku backend!",
            notification_data={
                'test': 'true',
                'source': 'heroku_test_script'
            }
        )
        
        if success:
            print("✅ Notification sent successfully!")
            print("📱 Check your phone for the notification")
        else:
            print("❌ Failed to send notification")
            
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_push_notification()
