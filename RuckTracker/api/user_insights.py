from flask import g
from flask_restful import Resource
from ..supabase_client import get_supabase_client
import logging

logger = logging.getLogger(__name__)

class UserInsightsResource(Resource):
    """Return the latest user_insights snapshot for the authenticated user."""

    def get(self):
        if not getattr(g, 'user', None):
            return {"error": "Unauthorized"}, 401

        try:
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            resp = (
                supabase
                .table('user_insights')
                .select('*')
                .eq('user_id', g.user.id)
                .limit(1)
                .execute()
            )
            if hasattr(resp, 'data') and resp.data:
                return {"insights": resp.data[0]}, 200
            else:
                return {"insights": None}, 200
        except Exception as e:
            logger.error(f"GET /api/user-insights failed: {e}")
            return {"error": "Internal server error"}, 500

