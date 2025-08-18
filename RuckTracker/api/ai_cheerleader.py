from flask import request, g
from flask_restful import Resource
import logging
from ..supabase_client import get_supabase_client

logger = logging.getLogger(__name__)

class AICheerleaderLogResource(Resource):
    """Simple logging endpoint for AI cheerleader responses"""
    
    def post(self):
        try:
            data = request.get_json()
            
            if not data:
                return {"error": "No data provided"}, 400
            
            session_id = data.get('session_id')
            personality = data.get('personality')
            openai_response = data.get('openai_response')
            
            if not all([session_id, personality, openai_response]):
                return {"error": "Missing required fields: session_id, personality, openai_response"}, 400
            
            # Get Supabase client
            supabase = get_supabase_client()
            
            # Insert log entry
            result = supabase.table('ai_cheerleader_logs').insert({
                'session_id': session_id,
                'personality': personality,
                'openai_response': openai_response
            }).execute()
            
            if result.data:
                logger.info(f"AI cheerleader response logged for session {session_id}")
                return {"status": "success", "message": "AI response logged"}, 201
            else:
                logger.error(f"Failed to log AI response: {result}")
                return {"error": "Failed to log response"}, 500
                
        except Exception as e:
            logger.error(f"Error logging AI cheerleader response: {str(e)}")
            return {"error": "Internal server error"}, 500
