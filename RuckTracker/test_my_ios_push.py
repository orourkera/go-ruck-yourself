#!/usr/bin/env python3
"""
Test script to send push notifications to MY iOS device tokens only
"""

import os
import sys
import logging
from datetime import datetime

# Add the RuckTracker directory to Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from services.push_notification_service import PushNotificationService

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def test_my_ios_push():
    """Send critical update notification to my specific iOS device tokens"""
    try:
        # Initialize push notification service
        push_service = PushNotificationService()
        
        # My specific iOS device tokens (from the device list you provided)
        my_ios_tokens = [
            "eUf6QseyUE7igTUZtLEiRU:APA91bEbuaRtubkybFn13oQIusfNEVbZDJv9M5EckawNXEXYu1-9PNmJlMgzzjwW89xvnfViAChIn32v47jCNx7zp8ekrTwqjq6fCyYB5LPpUjksakmOdoA"
        ]
        
        logger.info(f"🚀 Testing push notification to my iOS device ({len(my_ios_tokens)} token)")
        
        # Send critical update notification with timestamp to bypass duplicate detection
        import time
        import random
        version_with_timestamp = f"3.5.1.{int(time.time())}.{random.randint(1,999)}"
        
        success = push_service.send_app_update_notification(
            device_tokens=my_ios_tokens,
            version=version_with_timestamp,
            is_critical=True
        )
        
        if success:
            logger.info("✅ Successfully sent iOS update notification to my device")
            return True
        else:
            logger.error("❌ Failed to send iOS update notification to my device")
            return False
            
    except Exception as e:
        logger.error(f"Error sending iOS update notification: {e}")
        return False

if __name__ == "__main__":
    logger.info("🔔 Testing iOS App Update Notification to MY device")
    logger.info(f"🕐 Timestamp: {datetime.now()}")
    
    # Check required environment variables
    required_env_vars = ['FIREBASE_PROJECT_ID', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']
    missing_vars = [var for var in required_env_vars if not os.getenv(var)]
    
    if missing_vars:
        logger.error(f"Missing required environment variables: {missing_vars}")
        sys.exit(1)
    
    # Send test notification
    success = test_my_ios_push()
    
    if success:
        logger.info("🎉 Test iOS push notification completed successfully")
        sys.exit(0)
    else:
        logger.error("💥 Test iOS push notification failed")
        sys.exit(1)