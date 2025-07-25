"""
Response helper utilities for consistent API responses
"""
from flask import jsonify
from typing import Any, Dict, Optional, List


def success_response(data: Any = None, message: str = "Success", status_code: int = 200) -> tuple:
    """
    Create a successful API response
    
    Args:
        data: Response data
        message: Success message
        status_code: HTTP status code (default: 200)
    
    Returns:
        Tuple of (response, status_code)
    """
    response_data = {
        "success": True,
        "message": message
    }
    
    if data is not None:
        response_data["data"] = data
    
    return jsonify(response_data), status_code


def error_response(message: str = "Error", status_code: int = 400, errors: Optional[List[str]] = None) -> tuple:
    """
    Create an error API response
    
    Args:
        message: Error message
        status_code: HTTP status code (default: 400)
        errors: List of specific error details
    
    Returns:
        Tuple of (response, status_code)
    """
    response_data = {
        "success": False,
        "message": message
    }
    
    if errors:
        response_data["errors"] = errors
    
    return jsonify(response_data), status_code


def paginated_response(
    data: List[Any], 
    total: int, 
    page: int = 1, 
    per_page: int = 20,
    message: str = "Success"
) -> tuple:
    """
    Create a paginated API response
    
    Args:
        data: List of data items
        total: Total number of items
        page: Current page number
        per_page: Items per page
        message: Success message
    
    Returns:
        Tuple of (response, status_code)
    """
    total_pages = (total + per_page - 1) // per_page
    has_next = page < total_pages
    has_prev = page > 1
    
    response_data = {
        "success": True,
        "message": message,
        "data": data,
        "pagination": {
            "total": total,
            "page": page,
            "per_page": per_page,
            "total_pages": total_pages,
            "has_next": has_next,
            "has_prev": has_prev
        }
    }
    
    return jsonify(response_data), 200


def validation_error_response(errors: Dict[str, List[str]]) -> tuple:
    """
    Create a validation error response
    
    Args:
        errors: Dictionary of field names to error messages
    
    Returns:
        Tuple of (response, status_code)
    """
    return error_response(
        message="Validation failed",
        status_code=422,
        errors=[f"{field}: {'; '.join(field_errors)}" for field, field_errors in errors.items()]
    )


def not_found_response(resource: str = "Resource") -> tuple:
    """
    Create a not found error response
    
    Args:
        resource: Name of the resource that was not found
    
    Returns:
        Tuple of (response, status_code)
    """
    return error_response(
        message=f"{resource} not found",
        status_code=404
    )


def unauthorized_response(message: str = "Unauthorized") -> tuple:
    """
    Create an unauthorized error response
    
    Args:
        message: Unauthorized message
    
    Returns:
        Tuple of (response, status_code)
    """
    return error_response(
        message=message,
        status_code=401
    )


def forbidden_response(message: str = "Access forbidden") -> tuple:
    """
    Create a forbidden error response
    
    Args:
        message: Forbidden message
    
    Returns:
        Tuple of (response, status_code)
    """
    return error_response(
        message=message,
        status_code=403
    )


def internal_error_response(message: str = "Internal server error") -> tuple:
    """
    Create an internal server error response
    
    Args:
        message: Error message
    
    Returns:
        Tuple of (response, status_code)
    """
    return error_response(
        message=message,
        status_code=500
    )
