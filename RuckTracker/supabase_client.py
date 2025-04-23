import os
from dotenv import load_dotenv
from supabase import create_client, Client
from supabase.lib.client_options import ClientOptions

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