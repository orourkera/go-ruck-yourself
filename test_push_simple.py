#!/usr/bin/env python3
"""
Simple test script for Heroku push notification service
"""
import os
import sys
import logging
import time
import argparse

# Add RuckTracker to path for Heroku deployment
sys.path.append(os.path.join(os.path.dirname(__file__), 'RuckTracker'))
from services.push_notification_service import PushNotificationService

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_push_notification(fcm_token=None):
    """Test push notification with provided or default FCM token"""
    
    print("🧪 TESTING PUSH NOTIFICATIONS ON HEROKU")
    print("=" * 50)
    
    # Use provided token or default
    FCM_TOKEN = fcm_token or "dsoCTDrtb00GkCZieamvNZ:APA91bGaSSQCe1ujVtzxvJf5ykyJnipy1kUTX57WF8aDES5EjyK8LNyI7KtOA2vlWsua1aLPgwJ5ymWkQUig-kvUg2p4mupiQB1QZafLuFLjMQqP35ZpGqI"
    
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
    parser = argparse.ArgumentParser(description='Test push notifications')
    parser.add_argument('--token', '-t', type=str, help='FCM token to test with')
    args = parser.parse_args()
    
    test_push_notification(args.token)
