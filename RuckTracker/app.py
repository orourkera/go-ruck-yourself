import os
import logging
import sys
import json
from datetime import datetime

from flask import Flask, render_template, Blueprint, g, jsonify, request, redirect
from flask_restful import Api
from werkzeug.middleware.proxy_fix import ProxyFix
from flask_cors import CORS
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Import Supabase client
from RuckTracker.supabase_client import supabase

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)
logger.info("Starting RuckTracker API server...")

# Custom JSON encoder to handle datetime objects
class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        return super().default(obj)

# Create Flask app
app = Flask(__name__)
app.secret_key = os.environ.get("SESSION_SECRET", "dev-secret-key")
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)
app.json_encoder = CustomJSONEncoder  # Use custom JSON encoder

# Enable CORS
CORS(app)

# Initialize API
api = Api(app)

# User authentication middleware
@app.before_request
def load_user():
    # Extract auth token from headers
    auth_header = request.headers.get('Authorization')
    g.user = None
    
    # Check if this is a development environment
    is_development = os.environ.get('FLASK_ENV') == 'development' or app.debug
    
    if auth_header and auth_header.startswith('Bearer '):
        token = auth_header[7:]  # Remove 'Bearer ' prefix
        try:
            logger.debug(f"Setting session with token: {token[:10]}...")
            
            # Create a JWT client to decode the token
            # In a proper setup, you would verify the token signature
            # Supabase JWT tokens don't require a refresh token in many operations
            try:
                # Use Supabase admin API to verify the token and get user
                user_response = supabase.auth.get_user(token)
                
                if user_response and user_response.user:
                    g.user = user_response.user
                    logger.debug(f"Authenticated user: {g.user.id}")
                else:
                    logger.warning("No user found in token validation")
                    
                    # In development, create a mock user
                    if is_development:
                        logger.debug("Creating mock user for development")
                        from types import SimpleNamespace
                        g.user = SimpleNamespace(
                            id="dev-user-id",
                            email="dev@example.com", 
                            user_metadata={"name": "Development User"}
                        )
            except Exception as token_error:
                logger.error(f"Token validation error: {str(token_error)}")
                
                # In development, create a mock user
                if is_development:
                    logger.debug("Creating mock user for development after token error")
                    from types import SimpleNamespace
                    g.user = SimpleNamespace(
                        id="dev-user-id",
                        email="dev@example.com", 
                        user_metadata={"name": "Development User"}
                    )
                
        except Exception as e:
            logger.error(f"Error authenticating user: {str(e)}", exc_info=True)
            g.user = None
            
            # In development, create a mock user
            if is_development:
                logger.debug("Creating mock user for development after error")
                from types import SimpleNamespace
                g.user = SimpleNamespace(
                    id="dev-user-id",
                    email="dev@example.com", 
                    user_metadata={"name": "Development User"}
                )
    else:
        logger.debug("No authorization header found")
        
        # In development, create a mock user even when no token is present
        if is_development:
            logger.debug("Creating mock user for development (no auth header)")
            from types import SimpleNamespace
            g.user = SimpleNamespace(
                id="dev-user-id",
                email="dev@example.com", 
                user_metadata={"name": "Development User"}
            )

# Force HTTPS redirect in production
@app.before_request
def enforce_https():
    if not request.is_secure and not app.debug:
        url = request.url.replace("http://", "https://", 1)
        return redirect(url, code=301)

# Import and register API resources
try:
    # Import API resources
    from .api.ruck import (
        RuckSessionListResource, 
        RuckSessionResource, 
        RuckSessionStartResource,
        RuckSessionPauseResource,
        RuckSessionResumeResource,
        RuckSessionCompleteResource,
        RuckSessionLocationResource,
        # RuckSessionDetailResource # Commented out - not found in api.ruck.py
    )
    
    from .api.auth import (
        SignUpResource,
        SignInResource,
        SignOutResource,
        RefreshTokenResource,
        ForgotPasswordResource,
        UserProfileResource
    )
    
    from .api.stats import ( # Import new stats resources
        WeeklyStatsResource,
        MonthlyStatsResource,
        YearlyStatsResource
    )
    
    # Auth endpoints (prefixed with /api)
    api.add_resource(SignUpResource, '/api/auth/signup', '/api/users/register')
    api.add_resource(SignInResource, '/api/auth/signin', '/api/auth/login') # Keep /api/auth/login
    api.add_resource(SignOutResource, '/api/auth/signout')
    api.add_resource(RefreshTokenResource, '/api/auth/refresh')
    api.add_resource(ForgotPasswordResource, '/api/auth/forgot-password')
    api.add_resource(UserProfileResource, '/api/users/profile') # Should be /api/users/profile
    
    # Ruck session endpoints (prefixed with /api)
    api.add_resource(RuckSessionListResource, '/api/rucks')
    api.add_resource(RuckSessionResource, '/api/rucks/<string:ruck_id>')
    api.add_resource(RuckSessionStartResource, '/api/rucks/<string:ruck_id>/start')
    api.add_resource(RuckSessionPauseResource, '/api/rucks/<string:ruck_id>/pause')
    api.add_resource(RuckSessionResumeResource, '/api/rucks/<string:ruck_id>/resume')
    api.add_resource(RuckSessionCompleteResource, '/api/rucks/<string:ruck_id>/complete')
    api.add_resource(RuckSessionLocationResource, '/api/rucks/<string:ruck_id>/location')
    # api.add_resource(RuckSessionDetailResource, '/api/ruck-details/<string:session_id>') # Commented out
    
    # Statistics endpoints (prefixed with /api)
    api.add_resource(WeeklyStatsResource, '/api/statistics/weekly')
    api.add_resource(MonthlyStatsResource, '/api/statistics/monthly')
    api.add_resource(YearlyStatsResource, '/api/statistics/yearly')
    
    # Add route for homepage (remains unprefixed)
    @app.route('/')
    def landing():
        return render_template('landing.html')

    @app.route('/privacy')
    def privacy():
        return render_template('privacy.html')

    @app.route('/terms')
    def terms():
        return render_template('terms.html')
    
    # Add route for health check (remains unprefixed)
    @app.route('/health')
    def health():
        return jsonify({
            'status': 'ok',
            'version': '1.0.0'
        })
        
    logger.info("Application initialized successfully! All API endpoints registered.")
except Exception as e:
    logger.error(f"Error during application initialization: {str(e)}", exc_info=True)
    raise

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8000))
    app.run(host='0.0.0.0', port=port, debug=True)
