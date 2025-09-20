from flask import request, g
from flask_restful import Resource
import logging
from typing import Dict, Any, Optional

from ..supabase_client import get_supabase_client
from ..utils.api_response import success_response, error_response

logger = logging.getLogger(__name__)

class CoachingPlanTemplateResource(Resource):
    """Get a specific coaching plan template including custom questions"""

    def get(self, plan_id: str):
        """Get plan template by ID"""
        try:
            supabase = get_supabase_client()

            # Fetch the plan template
            response = supabase.table('coaching_plan_templates').select('*').eq('plan_id', plan_id).eq('is_active', True).single().execute()

            if not response.data:
                return error_response(f'Plan template {plan_id} not found', status_code=404)

            template = response.data

            # Parse JSON fields if they're strings
            json_fields = ['base_structure', 'progression_rules', 'non_negotiables', 'retests',
                          'personalization_knobs', 'expert_tips', 'custom_questions',
                          'weekly_template', 'hydration_fueling', 'sources']

            for field in json_fields:
                if field in template and isinstance(template[field], str):
                    try:
                        import json
                        template[field] = json.loads(template[field])
                    except:
                        pass

            return success_response(template)

        except Exception as e:
            logger.error(f"Failed to fetch plan template {plan_id}: {e}")
            return error_response(f'Failed to fetch plan template: {str(e)}', status_code=500)

class CoachingPlanTemplatesResource(Resource):
    """Get all active coaching plan templates"""

    def get(self):
        """Get all active plan templates"""
        try:
            supabase = get_supabase_client()

            # Fetch all active templates
            response = supabase.table('coaching_plan_templates').select('*').eq('is_active', True).execute()

            templates = response.data or []

            # Parse JSON fields
            json_fields = ['base_structure', 'progression_rules', 'non_negotiables', 'retests',
                          'personalization_knobs', 'expert_tips', 'custom_questions',
                          'weekly_template', 'hydration_fueling', 'sources']

            for template in templates:
                for field in json_fields:
                    if field in template and isinstance(template[field], str):
                        try:
                            import json
                            template[field] = json.loads(template[field])
                        except:
                            pass

            return success_response({'templates': templates})

        except Exception as e:
            logger.error(f"Failed to fetch plan templates: {e}")
            return error_response(f'Failed to fetch plan templates: {str(e)}', status_code=500)
