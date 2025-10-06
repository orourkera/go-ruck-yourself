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

def process_scheduled_messages():
    """Process and send scheduled voice messages"""
    try:
        from RuckTracker.supabase_client import get_supabase_admin_client
        from RuckTracker.services.notification_manager import notification_manager
        from RuckTracker.services.voice_message_service import voice_message_service
        from datetime import datetime

        supabase = get_supabase_admin_client()

        # Find messages scheduled for now or earlier that haven't been sent
        now = datetime.utcnow().isoformat()
        result = supabase.table('ruck_messages').select(
            '*, sender:sender_id(username), recipient:recipient_id(id)'
        ).lte('scheduled_for', now).is_('sent_at', 'null').execute()

        if not result.data:
            return

        logger.info(f"Processing {len(result.data)} scheduled messages")

        for msg in result.data:
            try:
                # Generate audio if not already generated
                if not msg.get('audio_url') and msg.get('voice_id'):
                    audio_url = voice_message_service.generate_voice_message(
                        msg['message'],
                        msg['voice_id']
                    )
                    # Update message with audio URL
                    if audio_url:
                        supabase.table('ruck_messages').update({
                            'audio_url': audio_url
                        }).eq('id', msg['id']).execute()
                        msg['audio_url'] = audio_url

                # Send notification
                sender_name = msg.get('sender', {}).get('username', 'Someone')
                notification_data = {
                    'ruck_id': msg['ruck_id'],
                    'message_id': msg['id'],
                    'sender_id': msg['sender_id'],
                    'voice_id': msg['voice_id'],
                    'has_audio': bool(msg.get('audio_url')),
                    'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                }

                if msg.get('audio_url'):
                    notification_data['audio_url'] = msg['audio_url']

                notification_manager.send_notification(
                    recipients=[msg['recipient_id']],
                    notification_type='ruck_message',
                    title=f'🎤 {sender_name}',
                    body=msg['message'],
                    data=notification_data,
                    sender_id=msg['sender_id']
                )

                # Mark as sent
                supabase.table('ruck_messages').update({
                    'sent_at': datetime.utcnow().isoformat()
                }).eq('id', msg['id']).execute()

                logger.info(f"Sent scheduled message {msg['id']}")

            except Exception as msg_error:
                logger.error(f"Failed to send scheduled message {msg.get('id')}: {msg_error}")

    except Exception as e:
        logger.error(f"Error processing scheduled messages: {e}")

def main():
    """Main scheduler loop"""
    logger.info("Starting background scheduler...")
    
    # Create scheduler
    scheduler = BlockingScheduler()
    
    # Duel completion disabled - not using duels currently
    # scheduler.add_job(
    #     check_duel_completion,
    #     'interval',
    #     minutes=5,
    #     id='duel_completion',
    #     name='Check Duel Completion'
    # )

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

    # Add scheduled voice messages job (every 1 minute)
    scheduler.add_job(
        process_scheduled_messages,
        'interval',
        minutes=1,
        id='scheduled_messages',
        name='Process Scheduled Voice Messages'
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
