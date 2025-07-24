import logging
import os
from datetime import datetime, timedelta
from supabase import create_client, Client  # Assuming you use supabase-py
from services.push_notification_service import PushNotificationService
from services.redis_cache_service import cache_get, cache_set  # If needed for idempotency

# Basic logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Supabase client helper (adjust if you have a custom one)
def get_supabase_client() -> Client:
    url = os.environ.get('SUPABASE_URL')
    key = os.environ.get('SUPABASE_KEY')
    if not url or not key:
        raise ValueError("Missing Supabase credentials in environment variables")
    return create_client(url, key)

if __name__ == '__main__':
    try:
        # Initialize service (it will use the supabase client internally if needed)
        service = PushNotificationService()
        
        # Run the check
        service.check_and_notify_stuck_sessions()
        
    except Exception as e:
        logger.error(f"Script failed: {e}")
        # Optional: Send alert (e.g., to Slack/Email) if script crashes
        # e.g., service.send_admin_alert("Stuck session checker failed", str(e))