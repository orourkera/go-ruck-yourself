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
