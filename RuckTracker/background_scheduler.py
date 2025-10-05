"""
Background Scheduler for Heroku
===============================

This runs as a separate worker dyno and handles scheduled tasks like duel completion and coaching plan notifications.
Uses APScheduler to run tasks within the Python process.

To deploy:
1. Add to Procfile: worker: python background_scheduler.py
2. Scale worker dyno: heroku ps:scale worker=1
3. Install APScheduler: pip install apscheduler
"""

import logging
import requests
import os
import time
from apscheduler.schedulers.blocking import BlockingScheduler
from datetime import datetime
from RuckTracker.services.plan_notification_service import plan_notification_service
from RuckTracker.supabase_client import get_supabase_admin_client
from RuckTracker.api.user_coaching_plans import _generate_plan_sessions

# Configure logging - Reduced verbosity
logging.basicConfig(
    level=logging.WARNING,  # Reduced from INFO to WARNING
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

# Reduce third-party library logging
logging.getLogger('apscheduler').setLevel(logging.WARNING)
logging.getLogger('requests').setLevel(logging.WARNING)
logging.getLogger('urllib3').setLevel(logging.WARNING)

logger = logging.getLogger(__name__)

def check_duel_completion():
    """Periodic task to check and complete expired duels"""
    try:
        logger.info("Starting duel completion check...")

        # Get app URL from environment
        app_url = (
            os.environ.get('BACKEND_URL')
            or os.environ.get('HEROKU_APP_URL')
            or os.environ.get('APP_URL')
        )

        if not app_url:
            app_name = os.environ.get('HEROKU_APP_NAME')
            if app_name:
                app_url = f"https://{app_name}.herokuapp.com"
            else:
                logger.error("No app URL configured")
                return

        app_url = app_url.rstrip('/')
        endpoint = f"{app_url}/api/duels/completion-check"

        # Make the request
        response = requests.post(endpoint, json={}, timeout=30)
        response.raise_for_status()

        result = response.json()
        completed_count = len(result.get('completed_duels', []))

        if completed_count > 0:
            logger.info(f"Completed {completed_count} expired duels")
            for duel in result.get('completed_duels', []):
                logger.info(f"  - Duel '{duel.get('title')}': {duel.get('result')}")
        else:
            logger.info("No expired duels found")

    except Exception as e:
        logger.error(f"Error during duel completion check: {e}")

def process_plan_notifications():
    """Process and send scheduled coaching plan notifications"""
    try:
        logger.info("Processing coaching plan notifications...")

        # Call the plan notification service to process due notifications
        processed_count = plan_notification_service.process_scheduled_notifications()

        if processed_count > 0:
            logger.info(f"Processed {processed_count} coaching plan notifications")
        else:
            logger.debug("No coaching plan notifications due")

    except Exception as e:
        logger.error(f"Error processing plan notifications: {e}")

def main():
    """Main scheduler loop"""
    logger.info("Starting background scheduler...")
    
    # Create scheduler
    scheduler = BlockingScheduler()
    
    # Add duel completion job (every 5 minutes)
    scheduler.add_job(
        check_duel_completion,
        'interval',
        minutes=5,
        id='duel_completion',
        name='Check Duel Completion'
    )

    # Add coaching plan notification job (every 15 minutes)
    # More frequent checks ensure timely delivery of morning hype and evening briefs
    scheduler.add_job(
        process_plan_notifications,
        'interval',
        minutes=15,
        id='plan_notifications',
        name='Process Coaching Plan Notifications',
        misfire_grace_time=300  # Allow 5 minute grace period for misfires
    )
    
    try:
        logger.info("Scheduler started. Press Ctrl+C to exit.")
        scheduler.start()
    except KeyboardInterrupt:
        logger.info("Scheduler stopped.")
    except Exception as e:
        logger.error(f"Scheduler error: {e}")

if __name__ == "__main__":
    main()
