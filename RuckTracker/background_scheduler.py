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

def auto_complete_stale_sessions():
    """Auto-complete sessions that haven't had location updates for over 4 hours"""
    try:
        from datetime import datetime, timezone
        import math

        logger.info("Checking for stale sessions to auto-complete...")

        def haversine_distance(lat1, lon1, lat2, lon2):
            """Calculate distance between two GPS points in kilometers"""
            R = 6371.0  # Earth radius in kilometers

            lat1_rad = math.radians(lat1)
            lat2_rad = math.radians(lat2)
            delta_lat = math.radians(lat2 - lat1)
            delta_lon = math.radians(lon2 - lon1)

            a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
            c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

            return R * c

        supabase = get_supabase_admin_client()

        # Find sessions that are in_progress with last location update > 1 hour ago
        # First get all in_progress sessions
        sessions_resp = supabase.table('ruck_session') \
            .select('id, user_id, started_at, status') \
            .eq('status', 'in_progress') \
            .execute()

        if not sessions_resp.data:
            logger.debug("No in-progress sessions found")
            return

        stale_sessions = []
        cancelled_sessions = []

        for session in sessions_resp.data:
            session_id = session['id']

            # Get last location point for this session
            location_resp = supabase.table('location_point') \
                .select('timestamp') \
                .eq('session_id', session_id) \
                .order('timestamp', desc=True) \
                .limit(1) \
                .execute()

            if location_resp.data:
                # Has location data - check if stale
                last_location_time = datetime.fromisoformat(location_resp.data[0]['timestamp'].replace('Z', '+00:00'))
                hours_since_location = (datetime.now(timezone.utc) - last_location_time).total_seconds() / 3600

                if hours_since_location >= 4.0:  # Changed from 1 hour to 4 hours
                    stale_sessions.append({
                        'id': session_id,
                        'user_id': session['user_id'],
                        'last_location_time': last_location_time.isoformat(),
                        'hours_inactive': hours_since_location
                    })
            else:
                # No location data at all
                started_at = datetime.fromisoformat(session['started_at'].replace('Z', '+00:00'))
                hours_since_start = (datetime.now(timezone.utc) - started_at).total_seconds() / 3600

                if hours_since_start >= 4.0:  # Changed from 1 hour to 4 hours
                    cancelled_sessions.append({
                        'id': session_id,
                        'user_id': session['user_id'],
                        'started_at': session['started_at']
                    })

        # Auto-complete stale sessions with location data
        completed_count = 0
        for session_info in stale_sessions:
            try:
                session_id = session_info['id']

                # Calculate distance from location points
                location_points = supabase.table('location_point') \
                    .select('latitude, longitude, altitude, timestamp') \
                    .eq('session_id', session_id) \
                    .order('timestamp', asc=True) \
                    .execute()

                total_distance = 0.0
                elevation_gain = 0.0

                if location_points.data and len(location_points.data) > 1:
                    for i in range(1, len(location_points.data)):
                        prev_point = location_points.data[i-1]
                        curr_point = location_points.data[i]

                        # Calculate distance using haversine formula
                        lat1, lon1 = prev_point['latitude'], prev_point['longitude']
                        lat2, lon2 = curr_point['latitude'], curr_point['longitude']

                        # Use proper haversine distance calculation
                        distance = haversine_distance(lat1, lon1, lat2, lon2)
                        total_distance += distance

                        # Calculate elevation gain
                        if curr_point.get('altitude') and prev_point.get('altitude'):
                            alt_diff = curr_point['altitude'] - prev_point['altitude']
                            if alt_diff > 0:
                                elevation_gain += alt_diff

                # Get session details for duration calculation
                session_details = supabase.table('ruck_session') \
                    .select('started_at, ruck_weight_kg, user_weight_kg') \
                    .eq('id', session_id) \
                    .single() \
                    .execute()

                started_at = datetime.fromisoformat(session_details.data['started_at'].replace('Z', '+00:00'))
                last_location = datetime.fromisoformat(session_info['last_location_time'].replace('Z', '+00:00'))
                duration_seconds = int((last_location - started_at).total_seconds())

                # Simple calorie calculation
                calories = (duration_seconds / 60.0) * 75 * 0.5  # Basic estimate

                # Update session to completed
                update_data = {
                    'status': 'completed',
                    'completed_at': session_info['last_location_time'],
                    'distance_km': round(total_distance, 2),
                    'duration_seconds': duration_seconds,
                    'elevation_gain_m': round(elevation_gain, 1),
                    'calories_burned': round(calories, 0),
                    'notes': f'Auto-completed after {session_info["hours_inactive"]:.1f} hours of inactivity'
                }

                supabase.table('ruck_session') \
                    .update(update_data) \
                    .eq('id', session_id) \
                    .execute()

                completed_count += 1
                logger.info(f"Auto-completed session {session_id} after {session_info['hours_inactive']:.1f} hours inactive")

            except Exception as e:
                logger.error(f"Failed to auto-complete session {session_info['id']}: {e}")

        # Cancel sessions with no location data
        cancelled_count = 0
        for session_info in cancelled_sessions:
            try:
                supabase.table('ruck_session') \
                    .update({
                        'status': 'cancelled',
                        'completed_at': session_info['started_at'],
                        'notes': 'Auto-cancelled: No location data recorded'
                    }) \
                    .eq('id', session_info['id']) \
                    .execute()

                cancelled_count += 1
                logger.info(f"Auto-cancelled session {session_info['id']} (no location data)")

            except Exception as e:
                logger.error(f"Failed to auto-cancel session {session_info['id']}: {e}")

        if completed_count > 0 or cancelled_count > 0:
            logger.info(f"Auto-completion summary: {completed_count} completed, {cancelled_count} cancelled")
        else:
            logger.debug("No stale sessions found to auto-complete")

    except Exception as e:
        logger.error(f"Error during auto-completion of stale sessions: {e}")

def process_scheduled_messages():
    """Process and send scheduled voice messages"""
    try:
        from RuckTracker.supabase_client import get_supabase_admin_client
        from RuckTracker.services.notification_manager import notification_manager
        from RuckTracker.services.voice_message_service import voice_message_service
        from datetime import datetime, timezone

        supabase = get_supabase_admin_client()

        # Find messages scheduled for now or earlier that haven't been sent
        now = datetime.now(timezone.utc).isoformat()
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
                    'has_audio': 'true' if msg.get('audio_url') else 'false',
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
                    'sent_at': datetime.now(timezone.utc).isoformat()
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

    # Add auto-complete stale sessions job (every 10 minutes)
    scheduler.add_job(
        auto_complete_stale_sessions,
        'interval',
        minutes=10,
        id='auto_complete_sessions',
        name='Auto-complete Stale Sessions',
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
