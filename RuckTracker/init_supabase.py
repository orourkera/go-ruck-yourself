import os
from dotenv import load_dotenv
from supabase import create_client, Client
import json
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Initialize Supabase client
supabase_url = os.getenv('SUPABASE_URL', 'https://zmxapklvrbafuwhkefhf.supabase.co')
supabase_key = os.getenv('SUPABASE_KEY')

if not supabase_key:
    logger.error("SUPABASE_KEY environment variable is not set!")
    exit(1)

# Create Supabase client
supabase: Client = create_client(supabase_url, supabase_key)

def init_session_reviews_table():
    """Initialize the session_reviews table if it doesn't exist"""
    
    try:
        # Check if table exists by querying it
        logger.info("Checking if session_reviews table exists...")
        
        # Try to select from the table - if it fails, the table might not exist
        try:
            supabase.table('session_reviews').select('id').limit(1).execute()
            logger.info("Table 'session_reviews' already exists")
            return True
        except Exception as e:
            if "relation" in str(e) and "does not exist" in str(e):
                logger.info("Table 'session_reviews' does not exist, creating it...")
            else:
                # Some other error occurred
                logger.error(f"Error checking table: {e}")
                return False
        
        # Define SQL to create the table with appropriate schema
        sql = """
        CREATE TABLE IF NOT EXISTS session_reviews (
            id UUID PRIMARY KEY,
            session_id UUID NOT NULL REFERENCES ruck_sessions(id) ON DELETE CASCADE,
            rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
            perceived_exertion INTEGER CHECK (perceived_exertion BETWEEN 1 AND 10),
            notes TEXT,
            tags JSONB,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
        
        -- Add foreign key index for better performance
        CREATE INDEX IF NOT EXISTS session_reviews_session_id_idx ON session_reviews(session_id);
        
        -- Add RLS policies for security
        ALTER TABLE session_reviews ENABLE ROW LEVEL SECURITY;
        
        -- Only allow access to the user's own session reviews
        CREATE POLICY session_reviews_auth_select ON session_reviews 
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM ruck_sessions 
                    WHERE ruck_sessions.id = session_reviews.session_id 
                    AND ruck_sessions.user_id = auth.uid()
                )
            );
            
        CREATE POLICY session_reviews_auth_insert ON session_reviews 
            FOR INSERT WITH CHECK (
                EXISTS (
                    SELECT 1 FROM ruck_sessions 
                    WHERE ruck_sessions.id = session_reviews.session_id 
                    AND ruck_sessions.user_id = auth.uid()
                )
            );
            
        CREATE POLICY session_reviews_auth_update ON session_reviews 
            FOR UPDATE USING (
                EXISTS (
                    SELECT 1 FROM ruck_sessions 
                    WHERE ruck_sessions.id = session_reviews.session_id 
                    AND ruck_sessions.user_id = auth.uid()
                )
            );
            
        CREATE POLICY session_reviews_auth_delete ON session_reviews 
            FOR DELETE USING (
                EXISTS (
                    SELECT 1 FROM ruck_sessions 
                    WHERE ruck_sessions.id = session_reviews.session_id 
                    AND ruck_sessions.user_id = auth.uid()
                )
            );
        """
        
        # Execute the SQL via RPC
        supabase.rpc('exec_sql', {'sql': sql}).execute()
        
        logger.info("Successfully created 'session_reviews' table")
        return True
        
    except Exception as e:
        logger.error(f"Error creating 'session_reviews' table: {e}")
        return False

if __name__ == "__main__":
    init_session_reviews_table() 