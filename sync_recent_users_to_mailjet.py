#!/usr/bin/env python3
"""
Script to sync recent users to Mailjet
Fetches users from database and syncs them to Mailjet with proper formatting
"""

import sys
import os
from datetime import datetime, timedelta

# Add current directory to path for imports
sys.path.append(os.path.join(os.path.dirname(__file__), 'RuckTracker'))

from supabase_client import get_supabase_admin_client
from services.mailjet_service import sync_user_to_mailjet

def format_signup_date(created_at_str):
    """Convert ISO timestamp to DD/MM/YYYY format"""
    try:
        # Parse the timestamp (handles various formats)
        if 'T' in created_at_str:
            dt = datetime.fromisoformat(created_at_str.replace('Z', '+00:00'))
        else:
            dt = datetime.strptime(created_at_str, '%Y-%m-%d %H:%M:%S')
        
        return dt.strftime('%d/%m/%Y')
    except Exception as e:
        print(f"❌ Error formatting date {created_at_str}: {e}")
        return datetime.now().strftime('%d/%m/%Y')

def extract_first_name(username):
    """Extract first name from username (everything before first space)"""
    if not username:
        return ''
    return username.split(' ')[0]

def sync_recent_users(days_back=30):
    """Sync users from the last N days to Mailjet"""
    
    try:
        # Get Supabase client
        supabase = get_supabase_admin_client()
        
        # Calculate date threshold
        cutoff_date = datetime.now() - timedelta(days=days_back)
        cutoff_str = cutoff_date.isoformat()
        
        print(f"🔍 Fetching users created after {cutoff_date.strftime('%Y-%m-%d')}...")
        
        # Query users from the last N days
        response = supabase.table('user').select(
            'id, username, email, created_at'
        ).gte('created_at', cutoff_str).execute()
        
        if not response.data:
            print("ℹ️  No recent users found")
            return
        
        users = response.data
        print(f"📋 Found {len(users)} recent users")
        
        # Sync each user to Mailjet
        success_count = 0
        error_count = 0
        
        for user in users:
            try:
                email = user.get('email')
                username = user.get('username', '')
                created_at = user.get('created_at')
                
                if not email:
                    print(f"⚠️  Skipping user {user.get('id')} - no email")
                    continue
                
                # Format data for Mailjet
                first_name = extract_first_name(username)
                signup_date = format_signup_date(created_at)
                
                # Create user metadata
                user_metadata = {
                    'signup_date': signup_date,
                    'signup_source': 'manual_sync',
                    'username': username,
                    'firstname': first_name,
                    'user_id': user.get('id')
                }
                
                print(f"📧 Syncing: {email} ({username}) - {signup_date}")
                
                # Sync to Mailjet
                success = sync_user_to_mailjet(
                    email=email,
                    username=username,
                    user_metadata=user_metadata
                )
                
                if success:
                    print(f"✅ Success: {email}")
                    success_count += 1
                else:
                    print(f"❌ Failed: {email}")
                    error_count += 1
                    
            except Exception as e:
                print(f"❌ Error processing user {user.get('email', 'unknown')}: {e}")
                error_count += 1
        
        print(f"\n📊 SUMMARY:")
        print(f"✅ Successfully synced: {success_count} users")
        print(f"❌ Errors: {error_count} users")
        print(f"📋 Total processed: {len(users)} users")
        
    except Exception as e:
        print(f"💥 Fatal error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    print("🚀 Starting Mailjet sync for recent users...")
    
    # Default to last 30 days, or accept command line argument
    days = 30
    if len(sys.argv) > 1:
        try:
            days = int(sys.argv[1])
        except ValueError:
            print("❌ Invalid days argument, using default (30)")
    
    print(f"📅 Syncing users from last {days} days")
    sync_recent_users(days)
    print("🏁 Sync complete!")
