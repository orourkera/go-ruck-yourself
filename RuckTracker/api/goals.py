from flask import request, g, jsonify
from flask_restful import Resource
import logging
from typing import Any, Dict

from ..supabase_client import get_supabase_client
from .schemas import GoalCreateSchema
from ..utils.ai_guardrails import prefilter_user_input

logger = logging.getLogger(__name__)


def _require_auth() -> tuple[bool, Dict[str, Any] | None]:
    if not getattr(g, 'user', None):
        return False, ({"error": "Authentication required"}, 401)
    return True, None


class GoalsListResource(Resource):
    """List and create user goals."""

    def get(self):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            user_id = g.user.id
            status = request.args.get('status')
            page = int(request.args.get('page', 1))
            limit = min(int(request.args.get('limit', 50)), 100)
            offset = (page - 1) * limit

            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            query = client.table('user_custom_goals').select(
                'id, title, description, metric, target_value, unit, window, status, start_at, end_at, deadline_at, created_at, updated_at'
            ).eq('user_id', user_id)
            if status:
                query = query.eq('status', status)
            resp = query.order('created_at', desc=True).range(offset, offset + limit - 1).execute()
            data = resp.data or []
            return jsonify({
                'goals': data,
                'count': len(data),
                'page': page,
                'limit': limit,
                'has_more': len(data) == limit
            })
        except Exception as e:
            logger.error(f"GET /api/goals failed: {e}")
            return {"error": "Internal server error"}, 500

    def post(self):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            payload = request.get_json() or {}
            # Validate with schema
            goal = GoalCreateSchema().load(payload)

            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            insert = {
                'user_id': g.user.id,
                'title': goal['title'],
                'description': goal.get('description'),
                'metric': goal['metric'],
                'target_value': goal['target_value'],
                'unit': goal['unit'],
                'window': goal.get('window'),
                'constraints_json': goal.get('constraints_json'),
                'start_at': goal.get('start_at'),
                'end_at': goal.get('end_at'),
                'deadline_at': goal.get('deadline_at'),
            }
            result = client.table('user_custom_goals').insert(insert).execute()
            if not result.data:
                logger.error(f"Goal create insert returned no data: {result}")
                return {"error": "Failed to create goal"}, 500
            return {"goal": result.data[0]}, 201
        except Exception as e:
            logger.error(f"POST /api/goals failed: {e}")
            return {"error": "Invalid payload"}, 400


class GoalResource(Resource):
    """Patch an existing user goal (owner-only)."""

    def patch(self, goal_id: str):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            # Only allow a strict subset of fields to be updated by clients
            allowed_fields = {
                'title', 'description', 'status', 'end_at', 'deadline_at'
            }
            payload = request.get_json() or {}
            update = {k: v for k, v in payload.items() if k in allowed_fields}
            if not update:
                return {"error": "No updatable fields provided"}, 400

            # Guard: status must be one of allowed values (mirror SQL)
            if 'status' in update and update['status'] not in (
                'active', 'paused', 'completed', 'canceled', 'expired'
            ):
                return {"error": "Invalid status value"}, 400

            client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            result = client.table('user_custom_goals').update(update).eq('id', goal_id).eq('user_id', g.user.id).execute()
            if not result.data:
                return {"error": "Goal not found or not updated"}, 404
            return {"goal": result.data[0]}, 200
        except Exception as e:
            logger.error(f"PATCH /api/goals/{goal_id} failed: {e}")
            return {"error": "Internal server error"}, 500


class GoalParseResource(Resource):
    """Parse a freeform user request into a goal draft (stub until service is implemented)."""

    def post(self):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            body = request.get_json() or {}
            text = body.get('text', '')
            cleaned = prefilter_user_input(text)
            # Service not yet implemented; return a safe placeholder
            return {
                'status': 'not_implemented',
                'message': 'Goal parser service not yet available',
                'input_preview': cleaned[:100]
            }, 501
        except ValueError as ve:
            return {"error": str(ve)}, 400
        except Exception as e:
            logger.error(f"POST /api/goals/parse failed: {e}")
            return {"error": "Internal server error"}, 500


class GoalEvaluateResource(Resource):
    """Trigger evaluation of a goal's progress (stub until scheduler/service implemented)."""

    def post(self, goal_id: str):
        ok, err = _require_auth()
        if not ok:
            return err
        try:
            # In future: enqueue background job; for now return accepted stub
            return {"status": "accepted", "goal_id": goal_id}, 202
        except Exception as e:
            logger.error(f"POST /api/goals/{goal_id}/evaluate failed: {e}")
            return {"error": "Internal server error"}, 500
