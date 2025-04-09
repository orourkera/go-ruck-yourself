import logging
from flask import request, jsonify
from flask_restful import Resource
from werkzeug.security import generate_password_hash, check_password_hash
import jwt
import datetime
import os

from app import db
from models import User
from api.schemas import UserSchema

# Create schema instance
user_schema = UserSchema()

logger = logging.getLogger(__name__)

# Get secret key from environment or use a default one for development
SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "dev-secret-key")


class LoginResource(Resource):
    """Resource for user authentication"""
    
    def post(self):
        """Authenticate a user and return a token"""
        data = request.get_json()
        
        # Check if required fields are provided
        if not data or not data.get('email') or not data.get('password'):
            return {"message": "Email and password are required"}, 400
        
        # Find user by email
        user = User.query.filter_by(email=data['email']).first()
        
        # Check if user exists and password is correct
        if not user or not check_password_hash(user.password_hash, data['password']):
            return {"message": "Invalid email or password"}, 401
        
        # Generate JWT token
        token = jwt.encode({
            'user_id': user.id,
            'exp': datetime.datetime.utcnow() + datetime.timedelta(days=7)
        }, SECRET_KEY, algorithm="HS256")
        
        return {
            'token': token,
            'user': user.to_dict()
        }, 200


class RegisterResource(Resource):
    """Resource for user registration"""
    
    def post(self):
        """Register a new user"""
        data = request.get_json()
        
        # Validate data
        errors = user_schema.validate(data)
        if errors:
            return {"errors": errors}, 400
        
        # Check if user with email already exists
        if User.query.filter_by(email=data['email']).first():
            return {"message": "User with this email already exists"}, 409
        
        # Check if user with username already exists
        if User.query.filter_by(username=data.get('username', '')).first():
            return {"message": "User with this username already exists"}, 409
        
        # Create new user
        user = User(
            username=data.get('username', data['email'].split('@')[0]),  # Default username if not provided
            email=data['email'],
            weight_kg=data.get('weight_kg'),
            password_hash=generate_password_hash(data['password'])
        )
        
        db.session.add(user)
        db.session.commit()
        
        # Generate JWT token
        token = jwt.encode({
            'user_id': user.id,
            'exp': datetime.datetime.utcnow() + datetime.timedelta(days=7)
        }, SECRET_KEY, algorithm="HS256")
        
        return {
            'token': token,
            'user': user.to_dict()
        }, 201


class UserProfileResource(Resource):
    """Resource for managing current user profile"""
    
    def get(self):
        """Get the current user's profile"""
        # Get the token from the Authorization header
        auth_header = request.headers.get('Authorization', '')
        
        if not auth_header.startswith('Bearer '):
            return {"message": "Missing or invalid Authorization header"}, 401
        
        token = auth_header.split(' ')[1]
        
        try:
            # Decode the token
            payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
            user_id = payload['user_id']
            
            # Find user by ID
            user = User.query.get(user_id)
            if not user:
                return {"message": "User not found"}, 404
            
            return {"user": user.to_dict()}, 200
            
        except jwt.ExpiredSignatureError:
            return {"message": "Token has expired"}, 401
        except jwt.InvalidTokenError:
            return {"message": "Invalid token"}, 401
    
    def put(self):
        """Update the current user's profile"""
        # Get the token from the Authorization header
        auth_header = request.headers.get('Authorization', '')
        
        if not auth_header.startswith('Bearer '):
            return {"message": "Missing or invalid Authorization header"}, 401
        
        token = auth_header.split(' ')[1]
        
        try:
            # Decode the token
            payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
            user_id = payload['user_id']
            
            # Find user by ID
            user = User.query.get(user_id)
            if not user:
                return {"message": "User not found"}, 404
            
            # Update user fields
            data = request.get_json()
            
            # Validate data
            errors = user_schema.validate(data, partial=True)
            if errors:
                return {"errors": errors}, 400
            
            # Update user fields
            if 'username' in data:
                user.username = data['username']
            if 'email' in data:
                user.email = data['email']
            if 'weight_kg' in data:
                user.weight_kg = data['weight_kg']
            if 'password' in data:
                user.password_hash = generate_password_hash(data['password'])
            
            db.session.commit()
            return {"user": user.to_dict()}, 200
            
        except jwt.ExpiredSignatureError:
            return {"message": "Token has expired"}, 401
        except jwt.InvalidTokenError:
            return {"message": "Invalid token"}, 401 