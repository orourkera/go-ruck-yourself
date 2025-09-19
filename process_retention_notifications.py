#!/usr/bin/env python3
"""
Background job processor for retention notifications.

This script should be run periodically (e.g., every 15 minutes) via cron job to:
1. Process scheduled retention notifications that are due
2. Send notifications via the notification manager
3. Mark processed notifications as sent

Example cron job entry (runs every 15 minutes):
*/15 * * * * cd /path/to/RuckingApp && python3 process_retention_notifications.py >> /var/log/retention_notifications.log 2>&1
"""

import os
import sys
import logging
from datetime import datetime

# Add the RuckTracker directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'RuckTracker'))

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/tmp/retention_notifications.log', mode='a')
    ]
)

logger = logging.getLogger(__name__)

def main():
    """Main function to process scheduled retention notifications."""
    try:
        logger.info("🚀 Starting retention notification processor")
        
        # Import and initialize the background job service
        from RuckTracker.services.retention_background_jobs import retention_background_jobs
        
        # Process all due notifications
        processed_count = retention_background_jobs.process_scheduled_notifications()
        
        if processed_count > 0:
            logger.info(f"✅ Successfully processed {processed_count} retention notifications")
        else:
            logger.info("ℹ️ No retention notifications were due for processing")
            
    except Exception as e:
        logger.error(f"❌ Error processing retention notifications: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
