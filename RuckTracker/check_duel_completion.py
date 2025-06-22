#!/usr/bin/env python3
"""
Heroku Scheduler Script for Duel Completion
===========================================

This script is designed to run with Heroku Scheduler add-on.
It makes a simple HTTP request to our own completion endpoint.

Heroku Scheduler Setup:
1. Add Heroku Scheduler add-on: heroku addons:create scheduler:standard
2. Add job: python check_duel_completion.py (run every 10 minutes)
"""

import requests
import os
import sys
from datetime import datetime

def main():
    """Check duel completion via internal API call"""
    print(f"[{datetime.utcnow().isoformat()}] Starting duel completion check...")
    
    try:
        # Use the app's own URL to call the completion endpoint
        # Heroku provides the app URL via environment variables
        app_url = os.environ.get('HEROKU_APP_URL') or os.environ.get('APP_URL')
        
        if not app_url:
            # Fallback: construct URL from Heroku app name
            app_name = os.environ.get('HEROKU_APP_NAME')
            if app_name:
                app_url = f"https://{app_name}.herokuapp.com"
            else:
                print("ERROR: No app URL found. Set HEROKU_APP_URL or HEROKU_APP_NAME")
                sys.exit(1)
        
        # Remove trailing slash
        app_url = app_url.rstrip('/')
        endpoint = f"{app_url}/api/duels/completion-check"
        
        print(f"Calling completion endpoint: {endpoint}")
        
        # Make the completion check request
        response = requests.post(endpoint, json={}, timeout=30)
        response.raise_for_status()
        
        result = response.json()
        completed_count = len(result.get('completed_duels', []))
        
        if completed_count > 0:
            print(f"✅ Successfully completed {completed_count} expired duels:")
            for duel in result.get('completed_duels', []):
                print(f"  - '{duel.get('title')}' → {duel.get('result')}")
        else:
            print("ℹ️  No expired duels found")
        
        print(f"[{datetime.utcnow().isoformat()}] Duel completion check finished successfully")
        
    except requests.exceptions.RequestException as e:
        print(f"❌ HTTP error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
