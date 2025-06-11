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
from .supabase_client import get_supabase_client # Relative import for supabase_client within RuckTracker package
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

# Configure Redis connection with SSL options to skip certificate verification for Heroku Redis
redis_url = os.environ.get('REDIS_URL', 'redis://localhost:6379')

# For Heroku Redis, we need to configure SSL settings to skip certificate verification
if redis_url.startswith('rediss://'):  # Heroku Redis uses rediss:// for SSL
    redis_url += '?ssl_cert_reqs=none'

limiter = Limiter(
    get_remote_address,
    app=app,
    default_limits=["200 per day", "50 per hour"],
    storage_uri=redis_url,
    strategy="fixed-window",
    swallow_errors=True
)
limiter.init_app(app)

# Import and rate-limit HeartRateSampleUploadResource AFTER limiter is ready to avoid circular import
from RuckTracker.api.ruck import HeartRateSampleUploadResource

# Apply rate limit to specific HTTP methods
app.logger.info("Setting HeartRateSampleUploadResource rate limit to: 3600 per hour")
HeartRateSampleUploadResource.get = limiter.limit("3600 per hour", override_defaults=True)(HeartRateSampleUploadResource.get)
HeartRateSampleUploadResource.post = limiter.limit("3600 per hour", override_defaults=True)(HeartRateSampleUploadResource.post)

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

# Import and register achievements blueprint
from RuckTracker.api.achievements import achievements_bp
app.register_blueprint(achievements_bp, url_prefix='/api')

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
    UserProfileResource,
    UserAvatarUploadResource,
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
from .api.resources import UserResource # Import UserResource
from .api.duels import DuelListResource, DuelResource, DuelJoinResource, DuelParticipantResource, DuelWithdrawResource
from .api.duel_participants import DuelParticipantProgressResource, DuelLeaderboardResource
from .api.duel_stats import UserDuelStatsResource, DuelStatsLeaderboardResource, DuelAnalyticsResource
from .api.duel_invitations import DuelInvitationListResource, DuelInvitationResource, SentInvitationsResource
from .api.duel_comments import DuelCommentsResource
from .api.device_tokens import DeviceTokenResource

# Apply rate limiting to SignInResource
rate_limit_resource(SignInResource, "5 per minute")

# User authentication middleware
@app.before_request
def load_user():
    # Skip token validation for public signup/register endpoints
    public_paths = ['/api/auth/signup', '/api/users/register']
    if request.path in public_paths:
        g.user = None
        g.user_id = None
        g.access_token = None
        logger.debug(f"Skipping token auth for public path: {request.path}")
        return

    # Extract auth token from headers
    auth_header = request.headers.get('Authorization')
    g.user = None
    g.user_id = None
    g.access_token = None
    
    # Check if this is a development environment
    is_development = os.environ.get('FLASK_ENV') == 'development' or app.debug
    
    if auth_header and auth_header.startswith('Bearer '):
        token = auth_header.split("Bearer ")[1].strip()
        try:
            logger.debug(f"Validating token (first 10 chars): {token[:10]}...")
            
            # Use the shared singleton client – no new thread creation per request
            supabase = get_supabase_client()
            
            # Pass the JWT explicitly to get_user() per Supabase Python docs
            user_response = supabase.auth.get_user(token)
            user_obj = getattr(user_response, 'user', None)

            if user_obj:
                g.user = user_obj
                g.user_id = user_obj.id
                g.access_token = token
                logger.debug(f"User {user_obj.id} authenticated successfully")
                return
            else:
                logger.warning("Token validation failed – no user returned from Supabase")
        except Exception as token_error:
            logger.error(f"Token validation exception: {str(token_error)}", exc_info=True)

        # Fallback to mock user flow happens below for dev environments
    else:
        logger.debug("No authorization header found")
        
    # In development, create a mock user when no valid token is present
    if is_development:
        logger.debug("Creating mock user for development (no valid auth)")
        from types import SimpleNamespace
        g.user = SimpleNamespace(
            id="dev-user-id",
            email="dev@example.com", 
            user_metadata={"name": "Development User"}
        )
        g.user_id = "dev-user-id"
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
api.add_resource(SignOutResource, '/api/auth/signout', '/api/auth/logout')
api.add_resource(RefreshTokenResource, '/api/auth/refresh')
api.add_resource(ForgotPasswordResource, '/api/auth/forgot-password')
api.add_resource(UserProfileResource, '/api/auth/profile', '/api/users/profile')
api.add_resource(UserAvatarUploadResource, '/api/auth/avatar')

api.add_resource(UserResource, '/api/users/<string:user_id>') # Add registration for DELETE

# Ruck session endpoints (prefixed with /api)
api.add_resource(RuckSessionListResource, '/api/rucks')
api.add_resource(RuckSessionResource, '/api/rucks/<int:ruck_id>')
api.add_resource(RuckSessionStartResource, '/api/rucks/start')
api.add_resource(RuckSessionPauseResource, '/api/rucks/<int:ruck_id>/pause')
api.add_resource(RuckSessionResumeResource, '/api/rucks/<int:ruck_id>/resume')
api.add_resource(RuckSessionCompleteResource, '/api/rucks/<int:ruck_id>/complete')
# Apply high rate limit to location data endpoint
app.logger.info(f"Setting RuckSessionLocationResource rate limit to: 3600 per hour")
# Directly patch the RuckSessionLocationResource methods with only the post method (no get method)
try:
    RuckSessionLocationResource.post = limiter.limit("3600 per hour", override_defaults=True)(RuckSessionLocationResource.post)
    app.logger.info(f"Successfully applied rate limit to RuckSessionLocationResource.post")
except AttributeError as e:
    app.logger.error(f"Failed to apply rate limit to RuckSessionLocationResource: {e}")
    # Fall back to a global rate limit approach for this resource

# Now register the resource with modified methods
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

# Ruck Comments Endpoints
app.logger.info(f"Setting RuckCommentsResource rate limit to: 500 per minute")
# Directly patch the RuckCommentsResource methods with the limiter decorator
RuckCommentsResource.get = limiter.limit("500 per minute", override_defaults=True)(RuckCommentsResource.get)
RuckCommentsResource.post = limiter.limit("500 per minute", override_defaults=True)(RuckCommentsResource.post)
RuckCommentsResource.put = limiter.limit("500 per minute", override_defaults=True)(RuckCommentsResource.put)
RuckCommentsResource.delete = limiter.limit("500 per minute", override_defaults=True)(RuckCommentsResource.delete)

# Now register the resource with modified methods
api.add_resource(RuckCommentsResource, '/api/rucks/<int:ruck_id>/comments')

# Register notification resources with higher rate limits
app.logger.info(f"Setting NotificationsResource rate limit to: 4000 per hour")
# Apply higher rate limit to notification endpoints - only for GET method (POST doesn't exist)
NotificationsResource.get = limiter.limit("4000 per hour", override_defaults=True)(NotificationsResource.get)

# Register notification resources
api.add_resource(NotificationsResource, '/api/notifications')
api.add_resource(NotificationReadResource, '/api/notifications/<string:notification_id>/read')
api.add_resource(ReadAllNotificationsResource, '/api/notifications/read-all')

# Duel endpoints
api.add_resource(DuelListResource, '/api/duels')
api.add_resource(DuelResource, '/api/duels/<string:duel_id>')
api.add_resource(DuelJoinResource, '/api/duels/<string:duel_id>/join')
api.add_resource(DuelWithdrawResource, '/api/duels/<string:duel_id>/withdraw')
api.add_resource(DuelParticipantResource, '/api/duels/<string:duel_id>/participants/<string:participant_id>/status')

# Duel participants endpoints
api.add_resource(DuelParticipantProgressResource, '/api/duels/<string:duel_id>/participants/<string:participant_id>/progress')
api.add_resource(DuelLeaderboardResource, '/api/duels/<string:duel_id>/leaderboard')

# Duel stats endpoints
api.add_resource(UserDuelStatsResource, '/api/duel-stats', '/api/duel-stats/<string:user_id>')
api.add_resource(DuelStatsLeaderboardResource, '/api/duel-stats/leaderboard')
api.add_resource(DuelAnalyticsResource, '/api/duel-stats/analytics')

# Duel invitations endpoints
api.add_resource(DuelInvitationListResource, '/api/duel-invitations')
api.add_resource(DuelInvitationResource, '/api/duel-invitations/<string:invitation_id>')
api.add_resource(SentInvitationsResource, '/api/duel-invitations/sent')

# Duel comments endpoints
api.add_resource(DuelCommentsResource, '/api/duels/<string:duel_id>/comments')

# Device Token Endpoints
api.add_resource(DeviceTokenResource, '/api/device-token')

# Add route for homepage (remains unprefixed)
@app.route('/')
def landing():
    return render_template('landing.html')

# Auth redirect route to handle password reset from email and avoid Gmail scanner issues
@app.route('/auth/redirect')
def auth_redirect():
    """
    Handles redirect from email links to avoid Gmail scanner issues.
    Redirects to the original Supabase URL after validation.
    """
    to_url = request.args.get('to')
    
    if not to_url:
        logger.warning("Auth redirect called without 'to' parameter")
        return "Missing redirect URL", 400
    
    # Validate that the 'to' URL is a legitimate Supabase URL
    # This should match your Supabase project URL pattern
    supabase_url = os.environ.get('SUPABASE_URL', '')
    if not supabase_url:
        logger.error("SUPABASE_URL environment variable not set")
        return "Server configuration error", 500
    
    # Extract the domain from Supabase URL for validation
    supabase_domain = supabase_url.replace('https://', '').replace('http://', '')
    
    if not to_url.startswith(f'https://{supabase_domain}/auth/v1/verify'):
        logger.warning(f"Invalid redirect URL attempted: {to_url}")
        return "Invalid redirect URL", 400
    
    logger.info(f"Redirecting to Supabase auth URL: {to_url}")
    
    # Add security headers to prevent caching and scanning
    response = redirect(to_url, code=302)
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    
    return response

@app.route('/api/auth/password-reset-confirm', methods=['POST'])
@limiter.limit("5 per minute")
def password_reset_confirm():
    """
    Confirm password reset with new password.
    This uses Supabase's password update functionality.
    """
    try:
        data = request.get_json()
        logger.info(f"Password reset request received. Raw data: {data}")
        
        if not data:
            logger.error("No request body received")
            return jsonify({"error": "Request body is required"}), 400
            
        new_password = data.get('new_password')  # Changed from 'password'
        access_token = data.get('token')  # Changed from 'access_token'
        refresh_token = data.get('refresh_token')
        
        logger.info(f"Extracted - new_password: {'[PRESENT]' if new_password else '[MISSING]'}, token: {'[PRESENT]' if access_token else '[MISSING]'}, refresh_token: {'[PRESENT]' if refresh_token else '[MISSING]'}")
        logger.info(f"new_password value: '{new_password}', token length: {len(access_token) if access_token else 0}")
        
        if not new_password:
            logger.error("New password missing from request")
            return jsonify({"error": "New password is required"}), 400
            
        if not access_token:
            logger.error("Access token missing from request")
            return jsonify({"error": "Access token is required"}), 400
            
        # Use Supabase client with the user's token to update password
        try:
            # First, try to set the session with the recovery token
            supabase = get_supabase_client()
            
            # Set the session using the access token from password reset
            logger.info(f"Setting session with recovery token")
            supabase.auth.set_session(access_token, refresh_token or "")
            
            # Update the user's password
            response = supabase.auth.update_user({
                'password': new_password
            })
            
            if response.user:
                logger.info(f"Password reset successful for user: {response.user.id}")
                return jsonify({
                    "message": "Password updated successfully",
                    "user": {
                        "id": response.user.id,
                        "email": response.user.email
                    }
                }), 200
            else:
                logger.error("Password reset failed - no user returned")
                return jsonify({"error": "Failed to update password"}), 400
        except Exception as supabase_error:
            logger.error(f"Supabase password update error: {str(supabase_error)}")
            
            # Extract the specific error message from Supabase
            error_message = str(supabase_error)
            
            # For common user-facing errors, provide cleaner messages
            if "New password should be different from the old password" in error_message:
                error_message = "New password must be different from your current password, rucker."
            elif "Password should be at least" in error_message:
                error_message = "Password is too short, rucker. Please use at least 6 characters"
            elif "Auth session missing" in error_message:
                error_message = "Session expired, rucker. Please request a new password reset link"
            else:
                # For other errors, use a generic message but still informative
                error_message = f"Password update failed: {error_message}"
            
            return jsonify({"error": error_message}), 400
            
    except Exception as e:
        logger.error(f"Password reset confirmation error: {str(e)}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500

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
