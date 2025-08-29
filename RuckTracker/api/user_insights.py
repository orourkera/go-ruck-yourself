from flask import g, request
from flask_restful import Resource
from ..supabase_client import get_supabase_client
from ..services.user_insights_llm import refresh_user_insights_with_llm
import logging

logger = logging.getLogger(__name__)

class UserInsightsResource(Resource):
    """Return the latest user_insights snapshot for the authenticated user."""

    def get(self):
        if not getattr(g, 'user', None):
            return {"error": "Unauthorized"}, 401

        try:
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            # Optional on-demand recompute: /api/user-insights?fresh=1
            fresh = request.args.get('fresh') in ("1", "true", "True")
            if fresh:
                try:
                    supabase.rpc('upsert_user_insights', { 'u_id': str(g.user.id), 'src': 'adhoc' }).execute()
                except Exception as e:
                    logger.info(f"[INSIGHTS] upsert_user_insights adhoc failed/ignored for {g.user.id}: {e}")
            # Optional LLM candidates: /api/user-insights?with_llm=1 (runs after facts refresh)
            with_llm = request.args.get('with_llm') in ("1", "true", "True")
            if with_llm:
                try:
                    refresh_user_insights_with_llm(str(g.user.id))
                except Exception as e:
                    logger.info(f"[INSIGHTS] LLM refresh failed for {g.user.id}: {e}")
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
