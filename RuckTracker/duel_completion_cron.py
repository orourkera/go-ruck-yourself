#!/usr/bin/env python3
"""
Duel Completion Cron Job
========================

This script checks for expired duels and completes them automatically.
Should be run every 5-10 minutes via cron job.

Setup:
1. Make executable: chmod +x duel_completion_cron.py
2. Add to crontab: */5 * * * * /path/to/duel_completion_cron.py
"""

import requests
import logging
import sys
import os
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/duel_completion.log'),
        logging.StreamHandler(sys.stdout)
    ]
)

def check_duel_completion():
    """Call the backend endpoint to check and complete expired duels"""
    try:
        # Get the backend URL from environment or use default
        backend_url = os.environ.get('BACKEND_URL', 'https://your-backend-url.com')
        endpoint = f"{backend_url}/api/duels/completion-check"
        
        logging.info(f"Checking duel completion at {endpoint}")
        
        # Make POST request to completion check endpoint
        response = requests.post(endpoint, json={}, timeout=30)
        response.raise_for_status()
        
        result = response.json()
        completed_count = len(result.get('completed_duels', []))
        
        if completed_count > 0:
            logging.info(f"Successfully completed {completed_count} expired duels")
            for duel in result.get('completed_duels', []):
                logging.info(f"  - Duel '{duel.get('title')}' ({duel.get('duel_id')}) - {duel.get('result')}")
        else:
            logging.info("No expired duels found")
            
        return True
        
    except requests.exceptions.RequestException as e:
        logging.error(f"HTTP error during duel completion check: {e}")
        return False
    except Exception as e:
        logging.error(f"Unexpected error during duel completion check: {e}")
        return False

def main():
    """Main function for cron job execution"""
    logging.info("=== Duel Completion Check Started ===")
    
    success = check_duel_completion()
    
    if success:
        logging.info("=== Duel Completion Check Completed Successfully ===")
        sys.exit(0)
    else:
        logging.error("=== Duel Completion Check Failed ===")
        sys.exit(1)

if __name__ == "__main__":
    main()
