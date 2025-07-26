"""
Utility functions for API responses
"""

def build_api_response(data=None, success=True, error=None, status_code=200):
    """
    Build a standardized API response
    
    Args:
        data: The data to include in the response
        success: Whether the operation was successful
        error: Error message if any
        status_code: HTTP status code
        
    Returns:
        tuple: (response_body, status_code)
    """
    response_body = {"success": success}
    if data is not None:
        response_body["data"] = data
    if error is not None:
        response_body["error"] = error
    return response_body, status_code


def success_response(data=None, message=None, status_code=200):
    response_body = {"success": True}
    if data is not None:
        response_body["data"] = data
    if message is not None:
        response_body["message"] = message
    return response_body, status_code


def error_response(message, details=None, status_code=400):
    response_body = {
        "success": False,
        "error": message
    }
    if details is not None:
        response_body["details"] = details
    return response_body, status_code


def check_auth_and_respond(user_id):
    """Check authentication and return appropriate response if failed."""
    from flask import g
    
    # Check if token was expired
    if hasattr(g, 'token_expired') and g.token_expired:
        return error_response("Token expired. Please refresh your authentication.", status_code=401)
    
    # Check if user_id is missing
    if not user_id:
        return error_response("Authentication required", status_code=401)
    
    return None  # Authentication successful


# Legacy function names for backward compatibility
def api_response(data=None, success=True, error=None, status_code=200):
    """Legacy function name for build_api_response"""
    return build_api_response(data, success, error, status_code)


def api_error(message, details=None):
    """Legacy function name for error_response"""
    return error_response(message, details)
