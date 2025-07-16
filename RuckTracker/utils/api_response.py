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


def api_response(data=None, message=None, status_code=200):
    """
    Create a successful API response
    
    Args:
        data: The data to include in the response
        message: Optional success message
        status_code: HTTP status code (default: 200)
        
    Returns:
        tuple: (response_body, status_code)
    """
    response_body = {"success": True}
    if data is not None:
        response_body["data"] = data
    if message is not None:
        response_body["message"] = message
    return response_body, status_code


def api_error(message, status_code=400, details=None):
    """
    Create an error API response
    
    Args:
        message: Error message
        status_code: HTTP status code (default: 400)
        details: Optional error details
        
    Returns:
        tuple: (response_body, status_code)
    """
    response_body = {
        "success": False,
        "error": message
    }
    if details is not None:
        response_body["details"] = details
    return response_body, status_code
