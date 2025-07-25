"""
Authentication helper utilities for user identification and authorization
"""
from flask import request, g
from functools import wraps
import jwt
import os
from typing import Optional

def get_current_user_id() -> Optional[str]:
    """
    Extract the current user ID from the request
    
    This function checks for authentication in the following order:
    1. JWT token in Authorization header
    2. User ID from Flask's g object (if set by middleware)
    3. Falls back to None if no authentication found
    
    Returns:
        User ID as string if authenticated, None otherwise
    """
    # First, check if user_id is already set in Flask's g object
    if hasattr(g, 'user_id') and g.user_id:
        return g.user_id
    
    # Try to extract from Authorization header
    auth_header = request.headers.get('Authorization')
    if auth_header and auth_header.startswith('Bearer '):
        token = auth_header.split(' ')[1]
        try:
            # Decode JWT token (replace with your actual JWT secret)
            jwt_secret = os.environ.get('JWT_SECRET', 'your-secret-key')
            payload = jwt.decode(token, jwt_secret, algorithms=['HS256'])
            user_id = payload.get('user_id') or payload.get('sub')
            
            # Cache in g for this request
            g.user_id = user_id
            return user_id
        except jwt.InvalidTokenError:
            # Token is invalid, continue to other methods
            pass
    
    # Try to get from Supabase auth (if available)
    supabase_auth = request.headers.get('X-Supabase-Auth')
    if supabase_auth:
        try:
            # Parse Supabase auth header - adjust based on your implementation
            # This is a placeholder - implement based on your Supabase setup
            return _extract_user_from_supabase_auth(supabase_auth)
        except Exception:
            pass
    
    # Fallback: check for user_id in session or other sources
    # This is application-specific - adjust as needed
    return request.form.get('user_id') or request.args.get('user_id')


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
