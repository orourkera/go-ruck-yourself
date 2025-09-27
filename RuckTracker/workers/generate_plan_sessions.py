#!/usr/bin/env python3
"""
Background worker to generate plan sessions for coaching plans.
This runs periodically to process plans that need session generation.
"""

import os
import sys
import time
import logging
from datetime import datetime, timedelta

# Add parent directory to path to import app modules
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from config import get_supabase_admin_client
from api.user_coaching_plans import _generate_plan_sessions
from services.plan_notification_service import PlanNotificationService

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_pending_plans():
    """Process coaching plans that need session generation."""
    client = get_supabase_admin_client()
    notification_service = PlanNotificationService()

    try:
        # Find plans that need session generation
        # Look for plans with session_generation status = 'pending' or 'partial'
        plans = client.table("user_coaching_plans") \
            .select("id, user_id, start_date, plan_modifications") \
            .eq("current_status", "active") \
            .execute()

        for plan in plans.data:
            try:
                modifications = plan.get('plan_modifications', {})
                session_gen = modifications.get('session_generation', {})

                if session_gen.get('status') in ['pending', 'partial']:
                    logger.info(f"Processing plan {plan['id']} with status {session_gen.get('status')}")

                    # Calculate which weeks to generate
                    weeks_generated = session_gen.get('weeks_generated', 0)
                    total_weeks = session_gen.get('duration_weeks', 12)

                    if weeks_generated >= total_weeks:
                        # Already fully generated
                        logger.info(f"Plan {plan['id']} already fully generated")
                        continue

                    # Prepare metadata for full generation
                    plan_metadata = {
                        'plan_structure': modifications.get('plan_structure', {}),
                        'weekly_template': session_gen.get('weekly_template', []),
                        'training_schedule': session_gen.get('training_schedule', []),
                        'duration_weeks': total_weeks,
                        'user_timezone': session_gen.get('user_timezone', 'UTC'),
                        'preferred_notification_time': session_gen.get('preferred_notification_time'),
                        'enable_notifications': session_gen.get('enable_notifications', True)
                    }

                    start_date = datetime.fromisoformat(session_gen.get('start_date', plan['start_date']))

                    # If partial, we need to delete existing sessions and regenerate all
                    if session_gen.get('status') == 'partial':
                        logger.info(f"Clearing partial sessions for plan {plan['id']}")
                        client.table("plan_sessions").delete() \
                            .eq("user_coaching_plan_id", plan['id']) \
                            .execute()

                    # Generate all sessions
                    logger.info(f"Generating {total_weeks} weeks of sessions for plan {plan['id']}")
                    _generate_plan_sessions(
                        plan['id'],
                        plan_metadata,
                        start_date,
                        user_id=plan['user_id']
                    )

                    # Update status to completed
                    updated_modifications = modifications.copy()
                    updated_modifications['session_generation'] = {
                        **session_gen,
                        'status': 'completed',
                        'weeks_generated': total_weeks,
                        'completed_at': datetime.utcnow().isoformat()
                    }

                    client.table("user_coaching_plans").update({
                        "plan_modifications": updated_modifications
                    }).eq("id", plan['id']).execute()

                    logger.info(f"Successfully generated sessions for plan {plan['id']}")

                    # Also seed notifications
                    try:
                        notification_service.seed_plan_schedule(plan['user_id'], plan['id'])
                        logger.info(f"Successfully seeded notifications for plan {plan['id']}")
                    except Exception as notif_err:
                        logger.error(f"Failed to seed notifications for plan {plan['id']}: {notif_err}")

            except Exception as e:
                logger.error(f"Failed to process plan {plan['id']}: {e}")
                continue

    except Exception as e:
        logger.error(f"Failed to fetch pending plans: {e}")

def main():
    """Main worker loop."""
    logger.info("Starting plan session generation worker")

    while True:
        try:
            process_pending_plans()
        except Exception as e:
            logger.error(f"Worker error: {e}")

        # Sleep for 30 seconds between runs
        time.sleep(30)

if __name__ == "__main__":
    main()