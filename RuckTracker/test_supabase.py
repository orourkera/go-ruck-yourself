import os
import sys
import logging
from dotenv import load_dotenv
from supabase_client import get_supabase_client

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

def test_supabase_connection():
    try:
        logger.info('Testing Supabase connection...')
        supabase = get_supabase_client()
        
        # Test a simple query to verify connection
        response = supabase.table('profiles').select('id').limit(1).execute()
        
        if response.data is not None:
            logger.info(f'Successfully connected to Supabase! Response: {response.data}')
            return True
        else:
            logger.error(f'Error connecting to Supabase: No data returned')
            return False
    except Exception as e:
        logger.error(f'Error connecting to Supabase: {str(e)}', exc_info=True)
        return False

if __name__ == '__main__':
    test_supabase_connection()
