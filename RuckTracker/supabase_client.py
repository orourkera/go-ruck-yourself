import os
from dotenv import load_dotenv
from supabase import create_client, Client
from supabase.lib.client_options import ClientOptions
import logging

# Initialize logger
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Get Supabase credentials from environment variables
url = os.environ.get("SUPABASE_URL")
key = os.environ.get("SUPABASE_KEY")

if not url or not key:
    raise ValueError("SUPABASE_URL and SUPABASE_KEY must be set in environment variables")

def get_supabase_client(user_jwt=None):
    """
    Returns a Supabase client instance. If user_jwt is provided, attaches it for RLS-authenticated requests.
    """
    options = None
    if user_jwt:
        options = ClientOptions(
            headers={"Authorization": f"Bearer {user_jwt}"}
        )
    client = create_client(url, key, options)
    return client

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