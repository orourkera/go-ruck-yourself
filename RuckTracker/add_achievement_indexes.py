#!/usr/bin/env python3
"""
Script to add database indexes for achievements performance optimization
"""

import os
from supabase import create_client
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

def add_achievement_indexes():
    """Add indexes to improve achievements query performance"""
    
    # Create admin client
    supabase_url = os.getenv('SUPABASE_URL')
    supabase_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY')
    
    if not supabase_url or not supabase_key:
        print("Error: Missing Supabase environment variables")
        return False
    
    supabase = create_client(supabase_url, supabase_key)
    
    indexes_to_create = [
        # Index for user_achievements by user_id (for fast user achievement lookups)
        {
            "name": "idx_user_achievements_user_id",
            "sql": "CREATE INDEX IF NOT EXISTS idx_user_achievements_user_id ON user_achievements(user_id);"
        },
        
        # Index for user_achievements by user_id and earned_at (for fast recent achievements)
        {
            "name": "idx_user_achievements_user_earned",
            "sql": "CREATE INDEX IF NOT EXISTS idx_user_achievements_user_earned ON user_achievements(user_id, earned_at DESC);"
        },
        
        # Index for achievement_progress by user_id
        {
            "name": "idx_achievement_progress_user_id",
            "sql": "CREATE INDEX IF NOT EXISTS idx_achievement_progress_user_id ON achievement_progress(user_id);"
        },
        
        # Index for ruck_session by user_id and status (for power points calculation)
        {
            "name": "idx_ruck_session_user_status",
            "sql": "CREATE INDEX IF NOT EXISTS idx_ruck_session_user_status ON ruck_session(user_id, status);"
        },
        
        # Index for ruck_session power_points calculation specifically
        {
            "name": "idx_ruck_session_user_completed_power",
            "sql": "CREATE INDEX IF NOT EXISTS idx_ruck_session_user_completed_power ON ruck_session(user_id, status) WHERE status = 'completed';"
        },
        
        # Index for achievements by is_active and unit_preference
        {
            "name": "idx_achievements_active_unit",
            "sql": "CREATE INDEX IF NOT EXISTS idx_achievements_active_unit ON achievements(is_active, unit_preference);"
        },
        
        # Index for achievements category and tier for stats
        {
            "name": "idx_achievements_category_tier",
            "sql": "CREATE INDEX IF NOT EXISTS idx_achievements_category_tier ON achievements(category, tier) WHERE is_active = true;"
        },
        
        # Index for recent achievements (earned_at desc for last 7 days)
        {
            "name": "idx_user_achievements_recent",
            "sql": "CREATE INDEX IF NOT EXISTS idx_user_achievements_recent ON user_achievements(earned_at DESC);"
        }
    ]
    
    created_count = 0
    error_count = 0
    
    print("Creating database indexes for achievements performance...")
    
    for index in indexes_to_create:
        try:
            print(f"Creating index: {index['name']}")
            
            # Execute the SQL directly via RPC
            result = supabase.rpc('exec_sql', {'sql': index['sql']}).execute()
            
            if result.data:
                print(f"✅ Successfully created index: {index['name']}")
                created_count += 1
            else:
                print(f"⚠️  Index may already exist: {index['name']}")
                
        except Exception as e:
            print(f"❌ Error creating index {index['name']}: {str(e)}")
            error_count += 1
    
    print(f"\nSummary:")
    print(f"✅ Indexes created: {created_count}")
    print(f"❌ Errors: {error_count}")
    print(f"📊 Total attempted: {len(indexes_to_create)}")
    
    return error_count == 0

if __name__ == "__main__":
    add_achievement_indexes()
