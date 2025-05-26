import os
import logging
import sys
import json
from datetime import datetime
from dotenv import load_dotenv # Import load_dotenv
from flask import Flask, render_template, Blueprint, g, jsonify, request, redirect
from flask_restful import Api
from werkzeug.middleware.proxy_fix import ProxyFix
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate # Import Migrate
from RuckTracker.supabase_client import get_supabase_client # Correct import path for get_supabase_client
from flask_limiter.util import get_remote_address

# Load environment variables from .env file
load_dotenv()

# Configure logging - Use appropriate level based on environment
log_level = logging.INFO
if os.environ.get("FLASK_ENV") == "development":
    log_level = logging.DEBUG

logging.basicConfig(
    level=log_level,
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

# Initialize SQLAlchemy and Migrate *after* imports
db = SQLAlchemy()
migrate = Migrate(directory='RuckTracker/migrations')

# Ensure secret key is set in environment
if not os.environ.get("SESSION_SECRET"):
    logger.error("SESSION_SECRET environment variable not set! Exiting for security.")
    if not os.environ.get("FLASK_ENV") == "development":
        # In production, we should exit if no secret key is provided
        sys.exit(1)
    else:
        logger.warning("Using temp secret key for development only")
        
# Set secret key from environment variable - no fallback in production
app.secret_key = os.environ.get("SESSION_SECRET")

# Configure database URI
database_url = os.environ.get('DATABASE_URL')
if not database_url:
    logger.error("DATABASE_URL environment variable not set! Exiting.")
    sys.exit(1) # Exit if DATABASE_URL is not set

# Heroku uses postgresql://, but SQLAlchemy needs postgresql+psycopg2://
if database_url.startswith("postgres://"):
    database_url = database_url.replace("postgres://", "postgresql+psycopg2://", 1)

app.config['SQLALCHEMY_DATABASE_URI'] = database_url
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False # Recommended to disable

app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)
app.json_encoder = CustomJSONEncoder  # Use custom JSON encoder

# Initialize extensions *after* app configuration
db.init_app(app)
migrate.init_app(app, db)

# Initialize rate limiter
limiter = Limiter(
    get_remote_address,
    app=app,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="memory://",
    strategy="fixed-window"
)
limiter.init_app(app)

# Import and rate-limit HeartRateSampleUploadResource AFTER limiter is ready to avoid circular import
from RuckTracker.api.ruck import HeartRateSampleUploadResource

limiter.limit("360 per hour", key_func=get_remote_address)(HeartRateSampleUploadResource)

# Define custom rate limits for specific endpoints
@app.route("/api/auth/register", methods=["POST"])
@limiter.limit("3 per hour")
def register_endpoint():
    # This just defines the rate limit, actual implementation is elsewhere
    pass

# Use a decorator function to apply rate limiting to resources
def rate_limit_resource(resource, limit):
    logger.info(f"Applying rate limit: {limit} to resource: {resource.__name__}")
    
    # Store the original dispatch_request method
    original_dispatch_request = resource.dispatch_request
    
    # Create a new dispatch_request method with rate limiting
    @limiter.limit(limit, override_defaults=True)
    def wrapped_dispatch_request(*args, **kwargs):
        return original_dispatch_request(*args, **kwargs)
    
    # Replace the original method with our wrapped version
    resource.dispatch_request = wrapped_dispatch_request
    return resource

# Apply rate limiting to Flask-RESTful endpoints - using higher defaults
# Individual resources can have their own specific limits applied via rate_limit_resource
decorators = []  # No global rate limit - we'll set specific limits per endpoint

# Enable CORS with specific allowed origins
allowed_origins = [
    "https://getrucky.com",
    "https://www.getrucky.com"
]

# Add localhost in development
if os.environ.get("FLASK_ENV") == "development":
    allowed_origins.extend([
        "http://localhost:3000",
        "http://localhost:8080", 
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8080"
    ])

CORS(app, resources={r"/api/*": {"origins": allowed_origins}})

# Initialize API
api = Api(app)

# Import and register ruck_buddies blueprint (single place)
from RuckTracker.api.ruck_buddies import ruck_buddies_bp
app.register_blueprint(ruck_buddies_bp)

# Import API resources after initializing db to avoid circular imports
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

from .api.ruck_photos_resource import RuckPhotosResource # Added import for RuckPhotosResource
from .api.ruck_likes_resource import RuckLikesResource # Import for RuckLikesResource
from .api.ruck_comments_resource import RuckCommentsResource # Import for RuckCommentsResource
from .api.notifications_resource import NotificationsResource, NotificationReadResource, ReadAllNotificationsResource # Import for Notification resources

# Apply rate limiting to SignInResource
rate_limit_resource(SignInResource, "5 per minute")

# User authentication middleware
@app.before_request
def load_user():
    # Skip token validation for public signup/register endpoints
    public_paths = ['/api/auth/signup', '/api/users/register']
    if request.path in public_paths:
        g.user = None # Ensure g.user is None for these paths
        logger.debug(f"Skipping token auth for public path: {request.path}")
        return

    # Extract auth token from headers
    auth_header = request.headers.get('Authorization')
    g.user = None
    g.access_token = None
    
    # Check if this is a development environment
    is_development = os.environ.get('FLASK_ENV') == 'development' or app.debug
    
    if auth_header and auth_header.startswith('Bearer '):
        token = auth_header.split("Bearer ")[1]
        try:
            logger.debug(f"Setting session with token: {token[:10]}...")
            
            # Create a JWT client to decode the token
            # In a proper setup, you would verify the token signature
            # Supabase JWT tokens don't require a refresh token in many operations
            try:
                # Use Supabase admin API to verify the token and get user
                supabase = get_supabase_client(user_jwt=token)
                user_response = supabase.auth.get_user(token)
                
                if user_response.user:
                    g.user = user_response.user
                    g.access_token = token
                    logger.info(f"Token storage code is active")
                    logger.debug(f"User {user_response.user.id} loaded successfully.")
                    return
                else:
                    logger.warning("No user data returned from Supabase")
                    
                    # In development, create a mock user
                    if is_development:
                        logger.debug("Creating mock user for development")
                        from types import SimpleNamespace
                        g.user = SimpleNamespace(
                            id="dev-user-id",
                            email="dev@example.com", 
                            user_metadata={"name": "Development User"}
                        )
                        g.access_token = token
                    logger.debug(f"Authenticated user: {getattr(g.user, 'id', None)}")
                    return
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
                    g.access_token = token
                logger.debug(f"Authenticated user: {getattr(g.user, 'id', None)}")
                return
                
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
                g.access_token = None
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
            g.access_token = None

# Force HTTPS redirect in production
@app.before_request
def enforce_https():
    if not request.is_secure and not app.debug:
        url = request.url.replace("http://", "https://", 1)
        return redirect(url, code=301)

# Auth endpoints (prefixed with /api)
api.add_resource(SignUpResource, '/api/auth/signup', '/api/users/register')
api.add_resource(SignInResource, '/api/auth/signin', '/api/auth/login', endpoint='signin')
api.add_resource(SignOutResource, '/api/auth/signout')
api.add_resource(RefreshTokenResource, '/api/auth/refresh')
api.add_resource(ForgotPasswordResource, '/api/auth/forgot-password')
api.add_resource(UserProfileResource, '/api/users/profile') # Handles GET/PUT
from .api.resources import UserResource # Import UserResource
api.add_resource(UserResource, '/api/users/<string:user_id>') # Add registration for DELETE

# Ruck session endpoints (prefixed with /api)
api.add_resource(RuckSessionListResource, '/api/rucks')
api.add_resource(RuckSessionResource, '/api/rucks/<int:ruck_id>')
api.add_resource(RuckSessionStartResource, '/api/rucks/start')
api.add_resource(RuckSessionPauseResource, '/api/rucks/<int:ruck_id>/pause')
api.add_resource(RuckSessionResumeResource, '/api/rucks/<int:ruck_id>/resume')
api.add_resource(RuckSessionCompleteResource, '/api/rucks/<int:ruck_id>/complete')
api.add_resource(RuckSessionLocationResource, '/api/rucks/<int:ruck_id>/location')
api.add_resource(HeartRateSampleUploadResource, '/api/rucks/<int:ruck_id>/heartrate') # Ensure this is correctly placed if not already

# Stats Endpoints
api.add_resource(WeeklyStatsResource, '/api/stats/weekly', '/api/statistics/weekly')
api.add_resource(MonthlyStatsResource, '/api/stats/monthly', '/api/statistics/monthly')
api.add_resource(YearlyStatsResource, '/api/stats/yearly', '/api/statistics/yearly')

# Ruck Photos Endpoint
app.logger.info(f"Setting RuckPhotosResource rate limit to: 30 per minute")
# Directly patch the RuckPhotosResource methods with the limiter decorator
RuckPhotosResource.get = limiter.limit("30 per minute", override_defaults=True)(RuckPhotosResource.get)
RuckPhotosResource.post = limiter.limit("30 per minute", override_defaults=True)(RuckPhotosResource.post)

# Now register the resource with modified methods
api.add_resource(RuckPhotosResource, '/api/ruck-photos')

# Ruck Likes Endpoints
app.logger.info(f"Setting RuckLikesResource rate limit to: 2000 per minute")
# Directly patch the RuckLikesResource methods with the limiter decorator
RuckLikesResource.get = limiter.limit("2000 per minute", override_defaults=True)(RuckLikesResource.get)
RuckLikesResource.post = limiter.limit("2000 per minute", override_defaults=True)(RuckLikesResource.post)
RuckLikesResource.delete = limiter.limit("2000 per minute", override_defaults=True)(RuckLikesResource.delete)

# Now register the resource with modified methods
api.add_resource(RuckLikesResource, '/api/ruck-likes', '/api/ruck-likes/check')

# Ruck Comments Endpoint
# Ruck Comments Endpoints
app.logger.info(f"Setting RuckCommentsResource rate limit to: 500 per minute")
# Directly patch the RuckCommentsResource methods with the limiter decorator
RuckCommentsResource.get = limiter.limit("500 per minute", override_defaults=True)(RuckCommentsResource.get)
RuckCommentsResource.post = limiter.limit("500 per minute", override_defaults=True)(RuckCommentsResource.post)
RuckCommentsResource.put = limiter.limit("500 per minute", override_defaults=True)(RuckCommentsResource.put)
RuckCommentsResource.delete = limiter.limit("500 per minute", override_defaults=True)(RuckCommentsResource.delete)

# Now register the resource with modified methods
api.add_resource(RuckCommentsResource, '/api/rucks/<int:ruck_id>/comments')

# Register notification resources
api.add_resource(NotificationsResource, '/api/notifications')
api.add_resource(NotificationReadResource, '/api/notifications/<string:notification_id>/read')
api.add_resource(ReadAllNotificationsResource, '/api/notifications/read-all')

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

@app.route('/support')
def support():
    return render_template('support.html')

# Add route for health check (remains unprefixed)
@app.route('/health')
def health():
    return jsonify({
        'status': 'ok',
        'version': '1.0.0'
    })

logger.info("Application initialized successfully! All API endpoints registered.")

# Trigger redeploy: Cascade forced comment

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8000))
    app.run(host='0.0.0.0', port=port, debug=True)
