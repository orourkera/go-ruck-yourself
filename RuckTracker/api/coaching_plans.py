from flask import request, g, jsonify
from flask_restful import Resource
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime
import uuid
import json

from ..supabase_client import get_supabase_client
from ..utils.response_helper import success_response, error_response

logger = logging.getLogger(__name__)

def _get_coaching_plan_templates(supabase_client) -> Dict[str, Any]:
    """Fetch coaching plan templates from database"""
    try:
        response = supabase_client.table('coaching_plan_templates').select('*').eq('is_active', True).execute()
        
        templates = {}
        for template in response.data or []:
            templates[template['plan_id']] = {
                'name': template['name'],
                'duration_weeks': template['duration_weeks'],
                'base_structure': template['base_structure'],
                'progression_rules': template['progression_rules'],
                'non_negotiables': template['non_negotiables'],
                'retests': template['retests'],
                'personalization_knobs': template['personalization_knobs']
            }
        
        return templates
    except Exception as e:
        logger.error(f"Failed to fetch coaching plan templates from database: {e}")
        # Fallback to empty dict - could add hardcoded fallback if needed
        return {}

def personalize_plan(base_plan_id: str, personalization: Dict[str, Any], supabase_client) -> Dict[str, Any]:
    """
    Generate a personalized plan based on the base plan and user's personalization data
    """
    templates = _get_coaching_plan_templates(supabase_client)
    base_plan = templates.get(base_plan_id)
    if not base_plan:
        raise ValueError(f"Unknown base plan: {base_plan_id}")
    
    # Start with the base structure
    personalized_structure = json.loads(json.dumps(base_plan['base_structure']))  # Deep copy
    adaptations = []
    
    # Apply personalization based on the 6 questions
    
    # 1. Adjust training days per week
    training_days_per_week = personalization.get('training_days_per_week')
    if training_days_per_week:
        if base_plan_id == 'fat-loss':
            # For fat loss, maintain cardio but adjust ruck frequency
            if training_days_per_week < 5:
                personalized_structure['sessions_per_week']['rucks'] = min(3, training_days_per_week)
                personalized_structure['sessions_per_week']['unloaded_cardio'] = max(0, training_days_per_week - personalized_structure['sessions_per_week']['rucks'])
                adaptations.append(f"Adjusted to {training_days_per_week} days/week while maintaining cardio focus")
        
        elif base_plan_id == 'daily-discipline':
            # Daily discipline is inherently daily, but adjust intensity
            if training_days_per_week < 6:
                adaptations.append("Modified for lower frequency while maintaining daily movement habit")
    
    # 2. Adjust for time constraints and minimum sessions
    minimum_session_minutes = personalization.get('minimum_session_minutes')
    if minimum_session_minutes:
        min_time = minimum_session_minutes
        if min_time <= 15:
            # Very time-constrained user
            adaptations.append(f"Optimized for {min_time}-minute minimum sessions")
            if base_plan_id == 'fat-loss':
                personalized_structure['weekly_ruck_minutes']['start'] = '90-120'
                personalized_structure['strength_duration'] = '20-25 min'
    
    # 3. Adjust for challenges
    challenges = personalization.get('challenges', [])
    if challenges:
        if 'Time' in challenges:
            adaptations.append("Time-efficient session options prioritized")
        
        if 'Motivation' in challenges:
            adaptations.append("Streak-friendly modifications and backup plans included")
        
        if 'Travel' in challenges:
            adaptations.append("Travel-friendly bodyweight and minimal equipment alternatives")
        
        if 'Weather' in challenges:
            adaptations.append("Indoor alternatives for all outdoor sessions")
        
        if 'Injury worries' in challenges:
            # Conservative load progression
            if base_plan_id in ['fat-loss', 'load-capacity']:
                personalized_structure['starting_load']['percentage'] = '8-12% bodyweight'
                adaptations.append("Conservative load progression for injury prevention")
    
    # 4. Adjust based on success definition (affects focus areas)
    success_definition = personalization.get('success_definition', '')
    if success_definition:
        success_lower = success_definition.lower()
        if any(word in success_lower for word in ['weight', 'kg', 'lb', 'fat', 'body']):
            if base_plan_id == 'fat-loss':
                # Emphasize cardio component
                personalized_structure['sessions_per_week']['unloaded_cardio'] = 3
                adaptations.append("Enhanced cardio focus for weight loss goals")
        
        elif any(word in success_lower for word in ['time', 'pace', 'speed', 'faster']):
            # Performance-oriented modifications
            adaptations.append("Performance-focused pacing and tempo work emphasized")
    
    # 5. Preferred days scheduling
    training_schedule = []
    preferred_days = personalization.get('preferred_days', [])
    if preferred_days:
        sessions_per_week = personalized_structure.get('sessions_per_week', {})
        total_sessions = sum([
            sessions_per_week.get('rucks', 0),
            sessions_per_week.get('unloaded_cardio', 0),
            sessions_per_week.get('strength', 0),
        ])
        
        # Create basic weekly template
        for i, day in enumerate(preferred_days[:total_sessions]):
            session_type = 'ruck' if i < sessions_per_week.get('rucks', 0) else 'cardio'
            training_schedule.append({
                'day': day,
                'session_type': session_type,
                'flexible': True
            })
    
    return {
        'base_plan_id': base_plan_id,
        'personalized_structure': personalized_structure,
        'training_schedule': training_schedule,
        'adaptations': adaptations
    }

class CoachingPlanTemplatesResource(Resource):
    """Resource for managing coaching plan templates"""
    
    def get(self):
        """Get all available coaching plan templates"""
        try:
            supabase = get_supabase_client()
            templates = _get_coaching_plan_templates(supabase)
            
            return success_response({
                "templates": templates
            })
            
        except Exception as e:
            logger.error(f"Error fetching coaching plan templates: {str(e)}")
            return error_response(f"Error fetching coaching plan templates: {str(e)}", 500)

class CoachingPlansResource(Resource):
    """Resource for managing coaching plans"""
    
    def post(self):
        """Create a new personalized coaching plan for the user"""
        try:
            if not hasattr(g, 'user_id') or not g.user_id:
                return error_response("Unauthorized", 401)
            
            data = request.get_json()
            if not data:
                return error_response("Request body required", 400)
            
            # Validate required fields
            required_fields = ['base_plan_id', 'coaching_personality', 'personalization']
            for field in required_fields:
                if field not in data:
                    return error_response(f"Missing required field: {field}", 400)
            
            base_plan_id = data['base_plan_id']
            coaching_personality = data['coaching_personality']
            personalization = data['personalization']
            
            # Get Supabase client
            supabase = get_supabase_client()
            
            # Get coaching plan templates from database
            templates = _get_coaching_plan_templates(supabase)
            
            # Validate base plan exists
            if base_plan_id not in templates:
                return error_response(f"Invalid base plan ID: {base_plan_id}", 400)
            
            base_plan = templates[base_plan_id]
            
            # Generate personalized plan
            personalized_plan = personalize_plan(base_plan_id, personalization, supabase)
            
            # Check if user already has an active plan of this type
            existing_response = supabase.table("coaching_plans").select("id").eq(
                "user_id", g.user_id
            ).eq("base_plan_id", base_plan_id).eq("status", "active").execute()
            
            if existing_response.data:
                # Archive the existing plan
                supabase.table("coaching_plans").update({
                    "status": "archived"
                }).eq("id", existing_response.data[0]["id"]).execute()
            
            # Create new coaching plan
            plan_data = {
                "user_id": g.user_id,
                "base_plan_id": base_plan_id,
                "plan_name": base_plan["name"],
                "duration_weeks": base_plan["duration_weeks"],
                "personalization": personalization,
                "plan_structure": personalized_plan['personalized_structure'],
                "coaching_personality": coaching_personality,
                "status": "active"
            }
            
            response = supabase.table("coaching_plans").insert(plan_data).execute()
            
            if not response.data:
                return error_response("Failed to create coaching plan", 500)
            
            created_plan = response.data[0]
            
            return success_response({
                "coaching_plan": created_plan,
                "personalized_adaptations": personalized_plan['adaptations'],
                "training_schedule": personalized_plan['training_schedule']
            })
            
        except Exception as e:
            logger.error(f"Error creating coaching plan: {str(e)}")
            return error_response(f"Error creating coaching plan: {str(e)}", 500)
    
    def get(self):
        """Get all coaching plans for the current user"""
        try:
            if not hasattr(g, 'user_id') or not g.user_id:
                return error_response("Unauthorized", 401)
            
            status = request.args.get('status')
            
            supabase = get_supabase_client()
            query = supabase.table("coaching_plans").select("*").eq("user_id", g.user_id)
            
            if status:
                query = query.eq("status", status)
            
            query = query.order("created_at", desc=True)
            response = query.execute()
            
            return success_response({
                "coaching_plans": response.data
            })
            
        except Exception as e:
            logger.error(f"Error fetching coaching plans: {str(e)}")
            return error_response(f"Error fetching coaching plans: {str(e)}", 500)

class CoachingPlanResource(Resource):
    """Resource for managing individual coaching plans"""
    
    def get(self, plan_id):
        """Get a specific coaching plan"""
        try:
            if not hasattr(g, 'user_id') or not g.user_id:
                return error_response("Unauthorized", 401)
            
            supabase = get_supabase_client()
            response = supabase.table("coaching_plans").select("*").eq("id", plan_id).eq("user_id", g.user_id).execute()
            
            if not response.data:
                return error_response("Coaching plan not found", 404)
            
            return success_response({
                "coaching_plan": response.data[0]
            })
            
        except Exception as e:
            logger.error(f"Error fetching coaching plan: {str(e)}")
            return error_response(f"Error fetching coaching plan: {str(e)}", 500)
    
    def patch(self, plan_id):
        """Update a coaching plan (e.g., status)"""
        try:
            if not hasattr(g, 'user_id') or not g.user_id:
                return error_response("Unauthorized", 401)
            
            data = request.get_json()
            if not data:
                return error_response("Request body required", 400)
            
            supabase = get_supabase_client()
            
            update_data = {}
            
            # Handle status updates
            if 'status' in data:
                valid_statuses = ['active', 'paused', 'completed', 'archived']
                if data['status'] not in valid_statuses:
                    return error_response(f"Invalid status. Must be one of: {valid_statuses}", 400)
                
                update_data['status'] = data['status']
                
                if data['status'] == 'completed':
                    update_data['completed_at'] = datetime.utcnow().isoformat()
            
            if not update_data:
                return error_response("No valid fields to update", 400)
            
            response = supabase.table("coaching_plans").update(update_data).eq("id", plan_id).eq("user_id", g.user_id).execute()
            
            if not response.data:
                return error_response("Coaching plan not found", 404)
            
            return success_response({
                "message": "Coaching plan updated successfully",
                "coaching_plan": response.data[0]
            })
            
        except Exception as e:
            logger.error(f"Error updating coaching plan: {str(e)}")
            return error_response(f"Error updating coaching plan: {str(e)}", 500)


# Register API resources
from flask import Blueprint
from flask_restful import Api

coaching_plans_bp = Blueprint('coaching_plans', __name__)
coaching_plans_api = Api(coaching_plans_bp)

# Add resources
coaching_plans_api.add_resource(CoachingPlanTemplatesResource, '/coaching-plan-templates')
coaching_plans_api.add_resource(CoachingPlansResource, '/coaching-plans')
coaching_plans_api.add_resource(CoachingPlanResource, '/coaching-plans/<string:plan_id>')