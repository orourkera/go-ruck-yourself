import os
from dotenv import load_dotenv
from supabase import create_client, Client
from supabase.lib.client_options import ClientOptions
import logging
import threading

# Initialize logger
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Get Supabase credentials from environment variables
url = os.environ.get("SUPABASE_URL")
key = os.environ.get("SUPABASE_KEY")

if not url or not key:
    raise ValueError("SUPABASE_URL and SUPABASE_KEY must be set in environment variables")

# Global client instances with thread safety
_client_instance = None
_client_lock = threading.Lock()

def get_supabase_client(user_jwt=None):
    """
    Returns a Supabase client instance with thread-safe singleton pattern.
    Prevents thread exhaustion by disabling auto-refresh and reusing clients.
    """
    global _client_instance
    
    # For user-authenticated requests, create a temporary client without auto-refresh
    if user_jwt:
        options = ClientOptions(
            headers={"Authorization": f"Bearer {user_jwt}"},
            # Enable auto-refresh for proper token handling
            auto_refresh_token=True
        )
        return create_client(url, key, options)
    
    # For service-level requests, use singleton pattern
    if _client_instance is None:
        with _client_lock:
            if _client_instance is None:
                try:
                    options = ClientOptions(
                        # Enable auto-refresh for proper session handling
                        auto_refresh_token=True
                    )
                    _client_instance = create_client(url, key, options)
                    logger.info("Supabase client singleton created successfully (auto-refresh enabled)")
                except Exception as e:
                    logger.error(f"Failed to create Supabase client: {e}")
                    raise
    
    return _client_instance

# Function to get an admin client using the service role key
def get_supabase_admin_client():
    """
    Returns a Supabase admin client instance using the service role key.
    Requires SUPABASE_SERVICE_ROLE_KEY environment variable.
    """
    service_key = os.environ.get('SUPABASE_SERVICE_ROLE_KEY')
    if not service_key:
        logger.error("SUPABASE_SERVICE_ROLE_KEY environment variable not set!")
        raise ValueError("Service role key not configured.")
        
    # Admin client uses the service key instead of the anon key
    admin_client = create_client(url, service_key)
    logger.debug("Supabase admin client created.")
    return admin_client