import os
import logging
import sys
import json
from datetime import datetime, timedelta
from dotenv import load_dotenv # Import load_dotenv
from flask import Flask, render_template, Blueprint, g, jsonify, request, redirect
from flask_restful import Api
from werkzeug.middleware.proxy_fix import ProxyFix
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_cors import CORS
from .supabase_client import get_supabase_client, get_supabase_admin_client # Relative import for supabase_client within RuckTracker package
from .services.redis_cache_service import get_cache_service # Add Redis cache service

# Load environment variables from .env file
load_dotenv()

# Configure logging - default to WARNING to suppress info/debug noise.
# Set VERBOSE_LOGS=true env var to restore INFO level in staging/dev.
log_level = logging.WARNING
if os.environ.get("VERBOSE_LOGS") == "true":
    log_level = logging.INFO
elif os.environ.get("FLASK_ENV") == "development":
    log_level = logging.DEBUG

# Configure logging to ensure all errors are captured
logging.basicConfig(
    level=log_level,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.StreamHandler(sys.stderr)  # Also log to stderr for errors
    ]
)

# Set specific logger levels to reduce log volume
logging.getLogger('werkzeug').setLevel(logging.WARNING)  # Reduce werkzeug verbosity
logging.getLogger('gunicorn').setLevel(logging.WARNING)  # Reduce gunicorn verbosity
logging.getLogger('flask').setLevel(logging.WARNING)    # Reduce flask verbosity
logging.getLogger('httpx').setLevel(logging.WARNING)    # Reduce httpx client logging
logging.getLogger('httpcore').setLevel(logging.WARNING) # Reduce httpcore logging
logging.getLogger('urllib3').setLevel(logging.WARNING)  # Reduce urllib3 logging

logger = logging.getLogger(__name__)
logger.info("Starting RuckTracker API server...")

# Initialize Supabase
supabase = get_supabase_client()

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
    default_limits=["10000 per day", "2000 per hour"],  # Increased from 500/hour to 2000/hour
    storage_uri=redis_url,
    strategy="fixed-window",
    swallow_errors=True
)
limiter.init_app(app)

# Import and rate-limit HeartRateSampleUploadResource AFTER limiter is ready to avoid circular import
from RuckTracker.api.ruck import HeartRateSampleUploadResource

# Initialize Redis cache service and check connection
try:
    cache_service = get_cache_service()
    if cache_service.is_connected():
        memory_stats = cache_service.get_memory_usage()
        app.logger.info(f"Redis cache service connected successfully - Memory usage: {memory_stats.get('used_memory_human', 'Unknown')}")
    else:
        app.logger.error("Redis cache service failed to connect - using memory caching fallback")
except Exception as e:
    app.logger.error(f"Redis cache service initialization failed: {str(e)}")

# Initialize Memory Profiler
from .api.memory_profiler import init_memory_routes, auto_profiler
init_memory_routes(app)
app.logger.info(" Automatic memory profiler initialized - available at /api/system/memory")

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

# Import and register clubs blueprint
from RuckTracker.api.clubs import clubs_bp
app.register_blueprint(clubs_bp, url_prefix='/api')

# Import and register events blueprints
from RuckTracker.api.events import events_bp
from RuckTracker.api.event_comments import event_comments_bp
from RuckTracker.api.event_progress import event_progress_bp
app.register_blueprint(events_bp, url_prefix='/api')
app.register_blueprint(event_comments_bp, url_prefix='/api')
app.register_blueprint(event_progress_bp, url_prefix='/api')

# Import and register cache monitor blueprint
from RuckTracker.api.cache_monitor import cache_monitor_bp
app.register_blueprint(cache_monitor_bp)

# Import and register users blueprint
from RuckTracker.api.users import users_bp
app.register_blueprint(users_bp, url_prefix='/api/users')

# Ensure higher rate limit for user public profile endpoint now that blueprint is registered
try:
    view_key = 'users.get_public_profile'
    if view_key in app.view_functions:
        app.logger.info("Setting get_public_profile rate limit to: 300 per hour")
        app.view_functions[view_key] = limiter.limit("300 per hour", override_defaults=True)(app.view_functions[view_key])
    else:
        app.logger.warning(f"View function {view_key} not found when applying rate limit (post-registration)")
except Exception as e:
    app.logger.error(f"Failed to set rate limit for get_public_profile (post-registration): {e}")

# Import API resources after initializing db to avoid circular imports
from .api.ruck import (
    RuckSessionListResource, 
    RuckSessionResource, 
    RuckSessionStartResource,
    RuckSessionPauseResource,
    RuckSessionResumeResource,
    RuckSessionCompleteResource,
    RuckSessionLocationResource,
    RuckSessionEditResource,
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
from .api.ruck_likes_resource import RuckLikesResource, RuckLikesBatchResource # Import for RuckLikesResource and batch
from .api.ruck_comments_resource import RuckCommentsResource # Import for RuckCommentsResource
from .api.notifications_resource import NotificationsResource, NotificationReadResource, ReadAllNotificationsResource # Import for Notification resources
from .api.resources import UserResource # Import UserResource
from .api.duels import DuelListResource, DuelResource, DuelJoinResource, DuelParticipantResource, DuelWithdrawResource, DuelCompletionCheckResource, DuelLeaderboardResource
from .api.duel_participants import DuelParticipantProgressResource, DuelLeaderboardResource
from .api.duel_stats import UserDuelStatsResource, DuelStatsLeaderboardResource, DuelAnalyticsResource
from .api.duel_invitations import DuelInvitationListResource, DuelInvitationResource, SentInvitationsResource
from .api.duel_comments import DuelCommentsResource
from .api.device_tokens import DeviceTokenResource
from .api.test_notification import TestNotificationResource

# Apply rate limiting to RefreshTokenResource to prevent refresh token abuse
app.logger.info("Setting RefreshTokenResource rate limit to: 30 per minute")
rate_limit_resource(RefreshTokenResource, "30 per minute")

# Note: Removed overly restrictive SignInResource rate limit (was 5 per minute)
# SignInResource now uses default limits: 10000 per day, 2000 per hour

# Apply higher rate limit to UserProfileResource for normal profile operations
app.logger.info("Setting UserProfileResource rate limit to: 1000 per hour")
rate_limit_resource(UserProfileResource, "1000 per hour")

# User authentication middleware
@app.before_request
def load_user():
    """Load user from authorization header"""
    g.user = None
    g.user_id = None
    g.access_token = None
    
    auth_header = request.headers.get('Authorization')
    is_development = os.environ.get('FLASK_ENV') == 'development' or app.debug
    
    if auth_header and auth_header.startswith('Bearer '):
        token = auth_header.split("Bearer ")[1].strip()
        try:
            logger.debug(f"Validating token (first 10 chars): {token[:10]}...")
            
            # Use the admin client to validate tokens without creating threads
            # The admin client has service role permissions to validate any user's token
            supabase_admin = get_supabase_admin_client()
            
            # Call the Supabase auth API directly to validate the token
            # This avoids thread creation from the auth refresh logic
            user_response = supabase_admin.auth.get_user(token)
            
            if user_response and hasattr(user_response, 'user') and user_response.user:
                g.user = user_response.user
                g.user_id = user_response.user.id
                g.access_token = token
                logger.debug(f"User {user_response.user.id} authenticated successfully")
                return
            else:
                logger.warning("Token validation failed – no user returned from Supabase")
        except Exception as token_error:
            logger.error(f"Token validation exception: {str(token_error)}")

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
api.add_resource(ForgotPasswordResource, '/api/auth/forgot-password', '/api/auth/password-reset')
api.add_resource(UserProfileResource, '/api/auth/profile', '/api/users/profile')
api.add_resource(UserAvatarUploadResource, '/api/auth/avatar')

# Helper used by Flask-Limiter to uniquely identify the caller (user ID or IP)

def get_user_id():
    """Return a stable identifier for rate-limiting: user_<uuid> if auth, else remote IP."""
    auth_header = request.headers.get('Authorization')
    if auth_header and auth_header.startswith('Bearer '):
        token = auth_header.split("Bearer ")[1]
        try:
            # Decode JWT token locally to extract user ID (avoid additional API calls)
            import base64
            import json
            
            # JWT tokens have 3 parts separated by dots: header.payload.signature
            # We only need the payload which contains the user ID
            parts = token.split('.')
            if len(parts) >= 2:
                # Add padding if needed for base64 decoding
                payload = parts[1]
                payload += '=' * (4 - len(payload) % 4)
                
                # Decode the payload
                decoded_payload = base64.urlsafe_b64decode(payload)
                payload_data = json.loads(decoded_payload.decode('utf-8'))
                
                # Extract user ID from JWT payload
                user_id = payload_data.get('sub')  # 'sub' is the standard JWT claim for user ID
                if user_id:
                    return f"user_{user_id}"
                    
        except Exception as e:
            app.logger.error(f"Error decoding JWT for rate limiting: {e}")
    
    # Fallback to IP address if JWT missing/invalid
    return get_remote_address()

api.add_resource(UserResource, '/api/users/<string:user_id>') # Add registration for DELETE

# Ruck session endpoints (prefixed with /api)
# Apply rate limit to RuckSessionListResource GET endpoint
app.logger.info(f"Setting RuckSessionListResource rate limit to: 6000 per hour (100 per minute)")
# Allow up to 100 requests per minute (6000 per hour) per user/IP
RuckSessionListResource.get = limiter.limit("100 per minute", key_func=get_user_id, override_defaults=True)(RuckSessionListResource.get)
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
api.add_resource(RuckSessionEditResource, '/api/rucks/<int:ruck_id>/edit')

# Heart rate sample upload resource
api.add_resource(HeartRateSampleUploadResource, '/api/rucks/<int:ruck_id>/heartrate') # Ensure this is correctly placed if not already

# Stats Endpoints with higher rate limits
app.logger.info("Setting stats resources rate limit to: 2000 per hour")
rate_limit_resource(WeeklyStatsResource, "2000 per hour")
rate_limit_resource(MonthlyStatsResource, "2000 per hour") 
rate_limit_resource(YearlyStatsResource, "2000 per hour")

api.add_resource(WeeklyStatsResource, '/api/stats/weekly', '/api/statistics/weekly')
api.add_resource(MonthlyStatsResource, '/api/stats/monthly', '/api/statistics/monthly')
api.add_resource(YearlyStatsResource, '/api/stats/yearly', '/api/statistics/yearly')

# Ruck Photos Endpoint

# Set up rate limiting for photo uploads - 100 requests per minute per user
app.logger.info(f"Setting RuckPhotosResource rate limit to: 100 per minute per user")
RuckPhotosResource.get = limiter.limit("100 per minute", key_func=get_user_id, override_defaults=True)(RuckPhotosResource.get)
RuckPhotosResource.post = limiter.limit("100 per minute", key_func=get_user_id, override_defaults=True)(RuckPhotosResource.post)

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

# Ruck Likes Batch Endpoints
app.logger.info(f"Setting RuckLikesBatchResource rate limit to: 100 per minute")
RuckLikesBatchResource.get = limiter.limit("100 per minute", override_defaults=True)(RuckLikesBatchResource.get)
api.add_resource(RuckLikesBatchResource, '/api/ruck-likes/batch')

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
api.add_resource(DuelCompletionCheckResource, '/api/duels/completion-check')

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
api.add_resource(TestNotificationResource, '/api/test-notification')

# Event Deeplink Endpoints
from .api.event_deeplinks import EventDeeplinkResource, WellKnownResource, ClubDeeplinkResource
api.add_resource(ClubDeeplinkResource, '/clubs/<string:club_id>')
api.add_resource(EventDeeplinkResource, '/events/<string:event_id>')
api.add_resource(WellKnownResource, '/.well-known/<string:filename>')

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

@app.route('/auth/callback')
def auth_callback():
    """
    Handle authentication callback from Supabase for password reset and other auth flows.
    This endpoint receives tokens and redirects to the mobile app.
    Supabase sends tokens in URL fragment, so we need JavaScript to extract them.
    """
    # Get tokens from URL parameters (fallback)
    access_token = request.args.get('access_token')
    refresh_token = request.args.get('refresh_token')
    token_type = request.args.get('type')
    expires_in = request.args.get('expires_in')
    
    logger.info(f"Auth callback received - type: {token_type}, access_token: {'present' if access_token else 'missing'}")
    logger.info(f"Request URL: {request.url}")
    logger.info(f"Query params: {dict(request.args)}")
    
    # Create HTML page that handles the redirect
    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Redirecting to RuckTracker...</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            body {{
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                margin: 0;
                padding: 20px;
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
            }}
            .container {{
                background: white;
                padding: 30px;
                border-radius: 10px;
                box-shadow: 0 4px 6px rgba(0,0,0,0.1);
                text-align: center;
                max-width: 400px;
            }}
            .spinner {{
                border: 4px solid #f3f3f3;
                border-top: 4px solid #667eea;
                border-radius: 50%;
                width: 40px;
                height: 40px;
                animation: spin 1s linear infinite;
                margin: 20px auto;
            }}
            @keyframes spin {{
                0% {{ transform: rotate(0deg); }}
                100% {{ transform: rotate(360deg); }}
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <h2>🎒 RuckTracker</h2>
            <div class="spinner"></div>

bileUrl += '?access_token=' + encodeURIComponent(tokens.access_token);
                    if (tokens.type) {{
                        mobileUrl += '&type=' + encodeURIComponent(tokens.type);
                    }}
                    if (tokens.refresh_token) {{
                        mobileUrl += '&refresh_token=' + encodeURIComponent(tokens.refresh_token);
                    }}
                    if (tokens.expires_in) {{
                        mobileUrl += '&expires_in=' + encodeURIComponent(tokens.expires_in);
                    }}
                }}
                
                return mobileUrl;
            }}
            
            // Try to redirect to mobile app immediately
            const mobileUrl = buildMobileUrl();
            console.log('Redirecting to mobile app:', mobileUrl);
            
            // Update the manual link
            document.getElementById('manual-link').href = mobileUrl;
            
            // Redirect to mobile app
            window.location.href = mobileUrl;
            
            // Fallback: show download links if app doesn't open
            setTimeout(() => {{
                document.querySelector('.container').innerHTML = `
                    <h2>🎒 RuckTracker</h2>
                    <p>App not found. Please download the RuckTracker app:</p>
                    <a href="https://apps.apple.com/app/rucktracker/id123456789" style="display: inline-block; margin: 10px; padding: 12px 24px; background: #667eea; color: white; text-decoration: none; border-radius: 6px;">Download for iOS</a>
                    <a href="https://play.google.com/store/apps/details?id=com.getrucky.app" style="display: inline-block; margin: 10px; padding: 12px 24px; background: #667eea; color: white; text-decoration: none; border-radius: 6px;">Download for Android</a>
                `;
            }}, 3000);
        </script>
    </body>
    </html>
    """
    
    return html_content

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

# ============================================================================
# COMPREHENSIVE ERROR HANDLING AND LOGGING
# ============================================================================

@app.after_request
def log_request_info(response):
    """Log requests selectively to reduce log volume"""
    # Skip logging for static files and health checks
    if (request.path.startswith('/static/') or 
        request.path.startswith('/favicon.ico') or 
        request.path.startswith('/apple-app-site-association') or
        request.path.startswith('/health') or
        request.path.startswith('/robots.txt')):
        return response
    
    # Log performance for slow requests
    if hasattr(g, 'start_time'):
        duration = (datetime.now() - g.start_time).total_seconds()
        if duration > 2.0:  # Log slow requests (>2 seconds)
            logger.warning(f"SLOW REQUEST: {request.method} {request.path} took {duration:.2f}s")
    
    # Log errors in detail (but reduce verbosity)
    if response.status_code >= 400:
        logger.error(f"HTTP ERROR {response.status_code}: {request.method} {request.path} - "
                    f"IP: {request.remote_addr}")
    
    # Log successful API requests at DEBUG level only
    elif request.path.startswith('/api/') and response.status_code < 400:
        logger.debug(f"API {request.method} {request.path} - {response.status_code}")
    
    return response

@app.before_request
def before_request_logging():
    """Track request start time for performance monitoring"""
    g.start_time = datetime.now()
    
    # Skip detailed logging for static files and health checks
    if (request.path.startswith('/static/') or 
        request.path.startswith('/favicon.ico') or 
        request.path.startswith('/apple-app-site-association') or
        request.path.startswith('/health') or
        request.path.startswith('/robots.txt')):
        return
    
    # Log authentication failures only (not all auth attempts)
    if request.headers.get('Authorization') and request.path.startswith('/api/'):
        logger.debug(f"AUTH REQUEST: {request.method} {request.path}")

# Error Handlers
@app.errorhandler(400)
def bad_request(error):
    """Handle 400 Bad Request errors"""
    logger.error(f"400 BAD REQUEST: {request.method} {request.path} - "
                f"IP: {request.remote_addr} - Error: {str(error)}")
    return jsonify({
        'error': 'Bad Request',
        'message': 'The request could not be understood by the server',
        'status_code': 400
    }), 400

@app.errorhandler(401)
def unauthorized(error):
    """Handle 401 Unauthorized errors"""
    logger.error(f"401 UNAUTHORIZED: {request.method} {request.path} - "
                  f"IP: {request.remote_addr} - Auth header: {bool(request.headers.get('Authorization'))}")
    return jsonify({
        'error': 'Unauthorized',
        'message': 'Authentication required',
        'status_code': 401
    }), 401

@app.errorhandler(403)
def forbidden(error):
    """Handle 403 Forbidden errors"""
    logger.warning(f"403 FORBIDDEN: {request.method} {request.path} - "
                  f"IP: {request.remote_addr} - User: {getattr(g, 'user_id', 'Unknown')}")
    return jsonify({
        'error': 'Forbidden',
        'message': 'Access denied',
        'status_code': 403
    }), 403

@app.errorhandler(404)
def not_found(error):
    """Handle 404 Not Found errors"""
    # Only log 404s for API endpoints to avoid spam from bots hitting random URLs
    if request.path.startswith('/api/'):
        logger.error(f"404 NOT FOUND: {request.method} {request.path} - "
                    f"IP: {request.remote_addr} - Referrer: {request.headers.get('Referer', 'None')}")
    else:
        # Log bot traffic at debug level (won't appear in production logs)
        logger.debug(f"404 BOT TRAFFIC: {request.method} {request.path} - IP: {request.remote_addr}")
    
    return jsonify({
        'error': 'Not Found',
        'message': 'The requested resource was not found',
        'status_code': 404
    }), 404

@app.errorhandler(429)
def ratelimit_handler(error):
    """Handle rate limit exceeded errors"""
    logger.warning(f"429 RATE LIMIT: {request.method} {request.path} - "
                  f"IP: {request.remote_addr} - Limit: {error.description}")
    return jsonify({
        'error': 'Rate Limit Exceeded',
        'message': 'Too many requests, please try again later',
        'retry_after': getattr(error, 'retry_after', 60),
        'status_code': 429
    }), 429

@app.errorhandler(500)
def internal_error(error):
    """Handle 500 Internal Server Error"""
    logger.error(f"500 INTERNAL ERROR: {request.method} {request.path} - "
                f"IP: {request.remote_addr} - Error: {str(error)}", exc_info=True)
    return jsonify({
        'error': 'Internal Server Error',
        'message': 'An unexpected error occurred',
        'status_code': 500
    }), 500

@app.errorhandler(502)
def bad_gateway(error):
    """Handle 502 Bad Gateway errors"""
    logger.error(f"502 BAD GATEWAY: {request.method} {request.path} - "
                f"IP: {request.remote_addr} - Error: {str(error)}")
    return jsonify({
        'error': 'Bad Gateway',
        'message': 'Upstream service error',
        'status_code': 502
    }), 502

@app.errorhandler(503)
def service_unavailable(error):
    """Handle 503 Service Unavailable errors"""
    logger.error(f"503 SERVICE UNAVAILABLE: {request.method} {request.path} - "
                f"IP: {request.remote_addr} - Error: {str(error)}")
    return jsonify({
        'error': 'Service Unavailable',
        'message': 'Service temporarily unavailable',
        'status_code': 503
    }), 503

@app.errorhandler(Exception)
def handle_exception(error):
    """Handle all unhandled exceptions"""
    logger.error(f"UNHANDLED EXCEPTION: {request.method} {request.path} - "
                f"IP: {request.remote_addr} - Exception: {str(error)}", exc_info=True)
    
    # Return 500 for unhandled exceptions
    return jsonify({
        'error': 'Internal Server Error',
        'message': 'An unexpected error occurred',
        'status_code': 500
    }), 500

# Memory and performance monitoring
@app.route('/api/system/health')
def system_health():
    """System health check with memory and performance metrics"""
    import psutil
    import sys
    
    try:
        # Get memory usage
        process = psutil.Process()
        memory_info = process.memory_info()
        memory_mb = memory_info.rss / 1024 / 1024
        
        # Get system metrics
        cpu_percent = psutil.cpu_percent()
        
        # Check Redis connection
        redis_status = "connected"
        try:
            cache_service = get_cache_service()
            if not cache_service.is_connected():
                redis_status = "disconnected"
        except Exception as e:
            redis_status = f"error: {str(e)}"
        
        health_data = {
            'status': 'ok',
            'timestamp': datetime.now().isoformat(),
            'memory_usage_mb': round(memory_mb, 2),
            'cpu_percent': cpu_percent,
            'python_version': sys.version,
            'redis_status': redis_status,
            'active_connections': len(psutil.Process().connections()),
        }
        
        # Log memory warning if usage is high
        if memory_mb > 400:  # 400MB threshold for 512MB dyno
            logger.warning(f"HIGH MEMORY USAGE: {memory_mb:.2f}MB / 512MB (78%+ usage)")
        
        logger.info(f"HEALTH CHECK: Memory: {memory_mb:.2f}MB, CPU: {cpu_percent}%, Redis: {redis_status}")
        
        return jsonify(health_data)
        
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}", exc_info=True)
        return jsonify({
            'status': 'error',
            'message': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500

logger.info("Error handlers and monitoring configured successfully!")

# Trigger redeploy: Cascade forced comment

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8000))
    app.run(host='0.0.0.0', port=port, debug=True)
