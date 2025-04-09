import os
import logging
import sys

from flask import Flask, render_template
from flask_restful import Api
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import DeclarativeBase
from werkzeug.middleware.proxy_fix import ProxyFix


# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)
logger.info("Starting RuckTracker API server...")

# Define SQLAlchemy base
class Base(DeclarativeBase):
    pass


# Initialize SQLAlchemy
db = SQLAlchemy(model_class=Base)

# Create Flask app
app = Flask(__name__)
app.secret_key = os.environ.get("SESSION_SECRET", "dev-secret-key")
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

# Configure database - always use SQLite for local development
# Create the database directory if it doesn't exist
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
os.makedirs(DATA_DIR, exist_ok=True)
DB_PATH = os.path.join(DATA_DIR, "rucktracker.db")
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL", f"sqlite:///{DB_PATH}")
logger.info(f"Using database: {app.config['SQLALCHEMY_DATABASE_URI']}")

app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
    "pool_recycle": 300,
    "pool_pre_ping": True,
}
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

# Initialize database
db.init_app(app)

# Initialize API
api = Api(app)

# Create tables and register resources
with app.app_context():
    try:
        # Import models
        import models  # noqa: F401
        
        # Create tables
        logger.info("Creating database tables...")
        db.create_all()
        logger.info("Database tables created successfully")
        
        # Import and register API resources
        from api.resources import (
            UserResource, UserListResource,
            SessionResource, SessionListResource,
            SessionStatisticsResource, SessionReviewResource,
            WeeklyStatisticsResource, MonthlyStatisticsResource, YearlyStatisticsResource
        )
        from api.apple_health import (
            AppleHealthSyncResource, AppleHealthIntegrationStatusResource
        )
        
        # User endpoints
        api.add_resource(UserResource, '/api/users/<int:user_id>')
        api.add_resource(UserListResource, '/api/users')
        
        # Session endpoints
        api.add_resource(SessionResource, '/api/sessions/<int:session_id>')
        api.add_resource(SessionListResource, '/api/sessions')
        api.add_resource(SessionStatisticsResource, '/api/sessions/<int:session_id>/statistics')
        api.add_resource(SessionReviewResource, '/api/sessions/<int:session_id>/review')
        
        # Aggregated statistics endpoints
        api.add_resource(WeeklyStatisticsResource, '/api/statistics/weekly')
        api.add_resource(MonthlyStatisticsResource, '/api/statistics/monthly')
        api.add_resource(YearlyStatisticsResource, '/api/statistics/yearly')
        
        # Apple Health integration endpoints
        api.add_resource(AppleHealthSyncResource, '/api/users/<int:user_id>/apple-health/sync')
        api.add_resource(AppleHealthIntegrationStatusResource, '/api/users/<int:user_id>/apple-health/status')
        
        # Add route for homepage
        @app.route('/')
        def index():
            return render_template('index.html')
            
        logger.info("Application initialized successfully! All API endpoints registered.")
    except Exception as e:
        logger.error(f"Error during application initialization: {str(e)}", exc_info=True)
        raise
