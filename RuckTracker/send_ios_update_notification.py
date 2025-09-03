#!/usr/bin/env python3
"""
Script to send push notifications to iOS users about critical app update
"""

import os
import sys
import logging
from datetime import datetime

# Add the RuckTracker directory to Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from services.push_notification_service import PushNotificationService
from supabase_client import get_supabase_admin_client

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def get_ios_device_tokens():
    """Get device tokens for iOS users only"""
    try:
        supabase = get_supabase_admin_client()
        
        # Query for iOS device tokens (where platform = 'ios')
        result = supabase.table('user_device_tokens') \
            .select('fcm_token, user_id, device_type, device_id') \
            .eq('device_type', 'ios') \
            .eq('is_active', True) \
            .execute()
        
        if result.data:
            logger.info(f"📱 Found {len(result.data)} active iOS device tokens")
            tokens = [row['fcm_token'] for row in result.data if row.get('fcm_token')]
            return tokens
        else:
            logger.warning("No iOS device tokens found")
            return []
            
    except Exception as e:
        logger.error(f"Error fetching iOS device tokens: {e}")
        return []

def send_ios_update_notification():
    """Send critical update notification to iOS users"""
    try:
        # Initialize push notification service
        push_service = PushNotificationService()
        
        # Get iOS device tokens
        ios_tokens = get_ios_device_tokens()
        
        if not ios_tokens:
            logger.error("No iOS device tokens found - cannot send notifications")
            return False
        
        logger.info(f"🚀 Sending critical app update notification to {len(ios_tokens)} iOS devices")
        
        # Send critical update notification
        success = push_service.send_app_update_notification(
            device_tokens=ios_tokens,
            version="3.5.1",
            is_critical=True
        )
        
        if success:
            logger.info("✅ Successfully sent iOS update notifications")
            return True
        else:
            logger.error("❌ Failed to send some iOS update notifications")
            return False
            
    except Exception as e:
        logger.error(f"Error sending iOS update notifications: {e}")
        return False

if __name__ == "__main__":
    logger.info("🔔 Starting iOS App Update Notification Campaign")
    logger.info(f"🕐 Timestamp: {datetime.now()}")
    
    # Check required environment variables
    required_env_vars = ['FIREBASE_PROJECT_ID', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']
    missing_vars = [var for var in required_env_vars if not os.getenv(var)]
    
    if missing_vars:
        logger.error(f"Missing required environment variables: {missing_vars}")
        sys.exit(1)
    
    # Send notifications
    success = send_ios_update_notification()
    
    if success:
        logger.info("🎉 iOS update notification campaign completed successfully")
        sys.exit(0)
    else:
        logger.error("💥 iOS update notification campaign failed")
        sys.exit(1)