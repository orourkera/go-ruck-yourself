"""
Authentication helper utilities for user identification and authorization
"""
from flask import request, g
from functools import wraps
import jwt
import os
import logging
from typing import Optional

logger = logging.getLogger(__name__)

def get_current_user_id() -> Optional[str]:
    """
    Extract the current user ID from the request
    
    This function uses the Flask g object that is set by the app's 
    @app.before_request middleware which handles Supabase authentication.
    
    Returns:
        User ID as string if authenticated, None otherwise
    """
    # Check if user_id is set in Flask's g object by the middleware
    if hasattr(g, 'user_id') and g.user_id:
        return g.user_id
    
    # If no user_id in g, authentication failed
    return None


def get_current_user_jwt() -> Optional[str]:
    """
    Extract the current user's JWT token from the request
    
    This function uses the Flask g object that is set by the app's 
    @app.before_request middleware which handles Supabase authentication.
    
    Returns:
        JWT token as string if authenticated, None otherwise
    """
    # Check if access_token is set in Flask's g object by the middleware
    if hasattr(g, 'access_token') and g.access_token:
        return g.access_token
    
    # Fallback: try to extract from Authorization header
    auth_header = request.headers.get('Authorization')
    if auth_header and auth_header.startswith('Bearer '):
        return auth_header.split("Bearer ")[1].strip()
    
    return None


def _extract_user_from_supabase_auth(auth_header: str) -> Optional[str]:
    """
    Extract user ID from Supabase authentication header
    
    Args:
        auth_header: Supabase auth header value
        
    Returns:
        User ID if found, None otherwise
    """
    # Placeholder implementation - adjust based on your Supabase setup
    # This would typically involve validating the Supabase JWT token
    try:
        # Example: if auth_header contains a JWT token
        if auth_header.startswith('Bearer '):
            token = auth_header.split(' ')[1]
            # Validate with Supabase JWT secret
            supabase_jwt_secret = os.environ.get('SUPABASE_JWT_SECRET')
            if supabase_jwt_secret:
                payload = jwt.decode(token, supabase_jwt_secret, algorithms=['HS256'])
                return payload.get('sub')  # Supabase uses 'sub' for user ID
    except jwt.InvalidTokenError:
        pass
    
    return None


def require_auth(f):
    """
    Decorator to require authentication for a route
    
    Usage:
        @require_auth
        def protected_route():
            user_id = get_current_user_id()
            # ... route logic
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        user_id = get_current_user_id()
        if not user_id:
            from .response_helper import unauthorized_response
            return unauthorized_response("Authentication required")
        
        # Store user_id in g for easy access in the route
        g.user_id = user_id
        return f(*args, **kwargs)
    
    return decorated_function


def require_user_access(resource_user_id_key: str = 'user_id'):
    """
    Decorator to ensure user can only access their own resources
    
    Args:
        resource_user_id_key: Key in request JSON that contains the resource's user_id
    
    Usage:
        @require_user_access('created_by_user_id')
        def update_route():
            # User can only update routes they created
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            current_user_id = get_current_user_id()
            if not current_user_id:
                from .response_helper import unauthorized_response
                return unauthorized_response("Authentication required")
            
            # Check if the resource belongs to the current user
            request_data = request.get_json() or {}
            resource_user_id = request_data.get(resource_user_id_key)
            
            if resource_user_id and resource_user_id != current_user_id:
                from .response_helper import forbidden_response
                return forbidden_response("Access denied: You can only access your own resources")
            
            g.user_id = current_user_id
            return f(*args, **kwargs)
        
        return decorated_function
    return decorator


def get_user_from_token(token: str) -> Optional[dict]:
    """
    Extract user information from JWT token
    
    Args:
        token: JWT token string
        
    Returns:
        User information dictionary if valid, None otherwise
    """
    try:
        jwt_secret = os.environ.get('JWT_SECRET', 'your-secret-key')
        payload = jwt.decode(token, jwt_secret, algorithms=['HS256'])
        
        return {
            'user_id': payload.get('user_id') or payload.get('sub'),
            'email': payload.get('email'),
            'username': payload.get('username'),
            'exp': payload.get('exp'),
            'iat': payload.get('iat')
        }
    except jwt.InvalidTokenError:
        return None


def is_admin_user(user_id: Optional[str] = None) -> bool:
    """
    Check if the current user (or specified user) has admin privileges
    
    Args:
        user_id: User ID to check (defaults to current user)
        
    Returns:
        True if user is admin, False otherwise
    """
    if not user_id:
        user_id = get_current_user_id()
    
    if not user_id:
        return False
    
    # Check if user is in admin list (environment variable or database)
    admin_users = os.environ.get('ADMIN_USERS', '').split(',')
    return user_id.strip() in [admin.strip() for admin in admin_users if admin.strip()]


def require_admin(f):
    """
    Decorator to require admin privileges for a route
    
    Usage:
        @require_admin
        def admin_only_route():
            # Only admins can access this
    """
    @wraps(f)
    def decorated_function(*args, **kwargs):
        user_id = get_current_user_id()
        if not user_id:
            from .response_helper import unauthorized_response
            return unauthorized_response("Authentication required")
        
        if not is_admin_user(user_id):
            from .response_helper import forbidden_response
            return forbidden_response("Admin privileges required")
        
        g.user_id = user_id
        return f(*args, **kwargs)
    
    return decorated_function


def extract_pagination_params():
    """
    Extract common pagination parameters from request
    
    Returns:
        Dictionary with limit, offset, page parameters
    """
    limit = min(int(request.args.get('limit', 20)), 100)  # Cap at 100
    offset = int(request.args.get('offset', 0))
    page = int(request.args.get('page', 1))
    
    # If page is provided, calculate offset
    if page > 1:
        offset = (page - 1) * limit
    
    return {
        'limit': limit,
        'offset': offset,
        'page': page
    }


def validate_user_owns_resource(resource_user_id: str, current_user_id: Optional[str] = None) -> bool:
    """
    Validate that the current user owns the specified resource
    
    Args:
        resource_user_id: User ID that owns the resource
        current_user_id: Current user ID (defaults to current user)
        
    Returns:
        True if user owns resource or is admin, False otherwise
    """
    if not current_user_id:
        current_user_id = get_current_user_id()
    
    if not current_user_id:
        return False
    
    # User owns the resource
    if current_user_id == resource_user_id:
        return True
    
    # Admin can access any resource
    if is_admin_user(current_user_id):
        return True
    
    return False
