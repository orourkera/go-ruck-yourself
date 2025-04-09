import os
from dotenv import load_dotenv
from supabase import create_client, Client

# Load environment variables
load_dotenv()

# Initialize Supabase client
supabase_url = os.getenv('SUPABASE_URL', 'https://zmxapklvrbafuwhkefhf.supabase.co')
supabase_key = os.getenv('SUPABASE_KEY')

# Create Supabase client
supabase: Client = create_client(supabase_url, supabase_key) 