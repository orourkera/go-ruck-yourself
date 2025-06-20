#!/usr/bin/env python3
"""
Script to set up the device tokens table and function in Supabase
"""
import os
import sys
from supabase_client import get_supabase_client

def setup_device_tokens():
    """Execute the SQL to create device tokens table and function"""
    try:
        # Read the SQL file
        sql_file_path = os.path.join(os.path.dirname(__file__), 'create_device_tokens_table.sql')
        with open(sql_file_path, 'r') as f:
            sql_content = f.read()
        
        # Get Supabase client with admin privileges
        supabase = get_supabase_client()
        
        # Execute the SQL
        print("Creating device tokens table and function...")
        result = supabase.rpc('exec_sql', {'sql': sql_content}).execute()
        
        if result.data:
            print("✅ Device tokens table and function created successfully!")
            return True
        else:
            print(f"❌ Error creating device tokens table: {result}")
            return False
            
    except Exception as e:
        print(f"❌ Error setting up device tokens: {e}")
        return False

if __name__ == "__main__":
    success = setup_device_tokens()
    sys.exit(0 if success else 1)
