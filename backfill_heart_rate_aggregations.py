#!/usr/bin/env python3

"""
Backfill heart rate aggregations for existing sessions.

This script finds sessions that have heart rate samples but null aggregated values
(avg_heart_rate, min_heart_rate, max_heart_rate) and calculates/updates them.
"""

import os
import sys
sys.path.append('RuckTracker')

from supabase import create_client, Client
from dotenv import load_dotenv
import logging

# Load environment variables
load_dotenv()

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_supabase_client() -> Client:
    """Get Supabase client"""
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    
    if not url or not key:
        raise ValueError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    
    return create_client(url, key)

def backfill_heart_rate_aggregations():
    """Backfill heart rate aggregations for sessions with samples but null aggregated values"""
    supabase = get_supabase_client()
    
    try:
        # Find sessions with null HR aggregations but that might have HR samples
        logger.info("Finding sessions with null heart rate aggregations...")
        
        sessions_resp = supabase.table('ruck_session').select(
            'id, avg_heart_rate, min_heart_rate, max_heart_rate'
        ).or_(
            'avg_heart_rate.is.null,min_heart_rate.is.null,max_heart_rate.is.null'
        ).execute()
        
        if not sessions_resp.data:
            logger.info("No sessions found with null HR aggregations")
            return
        
        logger.info(f"Found {len(sessions_resp.data)} sessions with potential null HR aggregations")
        
        updated_count = 0
        
        for session in sessions_resp.data:
            session_id = session['id']
            
            # Check if this session has heart rate samples
            hr_samples_resp = supabase.table('heart_rate_sample').select(
                'bpm'
            ).eq('session_id', session_id).execute()
            
            if not hr_samples_resp.data:
                continue  # No HR samples for this session
            
            # Calculate aggregations
            bpm_values = [int(sample['bpm']) for sample in hr_samples_resp.data if sample.get('bpm') is not None]
            
            if not bpm_values:
                continue  # No valid BPM values
            
            avg_hr = sum(bpm_values) / len(bpm_values)
            min_hr = min(bpm_values)
            max_hr = max(bpm_values)
            
            # Update the session
            update_resp = supabase.table('ruck_session').update({
                'avg_heart_rate': round(avg_hr, 1),
                'min_heart_rate': int(min_hr),
                'max_heart_rate': int(max_hr)
            }).eq('id', session_id).execute()
            
            if update_resp.error:
                logger.error(f"Failed to update session {session_id}: {update_resp.error}")
            else:
                updated_count += 1
                logger.info(f"Updated session {session_id}: avg={avg_hr:.1f}, min={min_hr}, max={max_hr} from {len(bpm_values)} samples")
        
        logger.info(f"Successfully updated {updated_count} sessions with heart rate aggregations")
        
    except Exception as e:
        logger.error(f"Error during backfill: {e}")
        raise

if __name__ == "__main__":
    backfill_heart_rate_aggregations()
