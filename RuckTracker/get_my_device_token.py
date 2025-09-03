#!/usr/bin/env python3
"""
Script to find your device token for testing push notifications
"""

import os
import sys
import logging

# Add the RuckTracker directory to Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from supabase_client import get_supabase_admin_client

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def find_device_tokens(user_email=None, limit=10):
    """Find device tokens, optionally filtered by user email"""
    try:
        supabase = get_supabase_admin_client()
        
        if user_email:
            # First get user ID from email
            user_result = supabase.table('users') \
                .select('id, email, username') \
                .eq('email', user_email) \
                .execute()
            
            if not user_result.data:
                logger.error(f"No user found with email: {user_email}")
                return
            
            user = user_result.data[0]
            user_id = user['id']
            
            logger.info(f"Found user: {user['email']} (ID: {user_id})")
            
            # Get device tokens for this user
            tokens_result = supabase.table('user_device_tokens') \
                .select('token, platform, device_model, device_id, is_active, created_at') \
                .eq('user_id', user_id) \
                .order('created_at', desc=True) \
                .execute()
        else:
            # Get recent device tokens (all users)
            tokens_result = supabase.table('user_device_tokens') \
                .select('token, user_id, platform, device_model, device_id, is_active, created_at') \
                .eq('is_active', True) \
                .order('created_at', desc=True) \
                .limit(limit) \
                .execute()
        
        if tokens_result.data:
            logger.info(f"📱 Found {len(tokens_result.data)} device tokens:")
            
            for i, token in enumerate(tokens_result.data):
                active_status = "✅ Active" if token['is_active'] else "❌ Inactive"
                platform_emoji = "🍎" if token['platform'] == 'ios' else "🤖" 
                
                print(f"\n{i+1}. {platform_emoji} {token['platform'].upper()} - {active_status}")
                print(f"   Token: {token['token']}")
                print(f"   Device: {token.get('device_model', 'Unknown')} ({token.get('device_id', 'No ID')})")
                print(f"   Created: {token['created_at']}")
                if 'user_id' in token:
                    print(f"   User ID: {token['user_id']}")
        else:
            logger.warning("No device tokens found")
            
    except Exception as e:
        logger.error(f"Error finding device tokens: {e}")

if __name__ == "__main__":
    print("🔍 Device Token Finder")
    print("=" * 50)
    
    # Check if email provided as argument
    if len(sys.argv) > 1:
        user_email = sys.argv[1]
        print(f"Searching for user: {user_email}")
        find_device_tokens(user_email)
    else:
        print("Showing recent 10 device tokens from all users")
        print("Usage: python3 get_my_device_token.py your-email@example.com")
        print()
        find_device_tokens()
        
    print("\n" + "=" * 50)
    print("💡 To test with your specific token, use:")
    print("curl -X POST https://getrucky.com/api/app/update-notifications \\")
    print("  -H 'Content-Type: application/json' \\")
    print("  -d '{\"device_tokens\": [\"YOUR_TOKEN_HERE\"], \"version\": \"3.5.1\", \"is_critical\": true}'")