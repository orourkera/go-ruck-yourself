from flask import request, g, jsonify
from flask_restful import Resource
import logging
from typing import Dict, List, Any, Optional
import math
from datetime import datetime
import uuid
import json

from ..supabase_client import get_supabase_client, get_supabase_admin_client
from ..utils.response_helper import success_response, error_response

logger = logging.getLogger(__name__)

def _get_coaching_plan_templates(supabase_client) -> Dict[str, Any]:
    """Fetch coaching plan templates from database"""
    try:
        response = supabase_client.table('coaching_plan_templates').select('*').eq('is_active', True).execute()

        templates = {}
        for template in response.data or []:
            templates[template['plan_id']] = {
                'id': template['id'],  # Include the integer ID for foreign key references
                'name': template['name'],
                'duration_weeks': template['duration_weeks'],
                'base_structure': template['base_structure'],
                'progression_rules': template['progression_rules'],
                'non_negotiables': template['non_negotiables'],
                'retests': template['retests'],
                'personalization_knobs': template['personalization_knobs'],
                # New columns for better plan generation
                'weekly_template': template.get('weekly_template', []),
                'hydration_fueling': template.get('hydration_fueling', {}),
                'weekly_volume_increase_cap': template.get('weekly_volume_increase_cap', 10.0),
                'no_dual_progressions': template.get('no_dual_progressions', False),
                'sources': template.get('sources', [])
            }
        
        return templates
    except Exception as e:
        logger.error(f"Failed to fetch coaching plan templates from database: {e}")
        # Fallback to empty dict - could add hardcoded fallback if needed
        return {}

def _get_user_insights(user_id: str) -> Optional[Dict[str, Any]]:
    """Fetch user insights for history-aware plan personalization"""
    try:
        supabase = get_supabase_admin_client()
        
        # Get or refresh user insights
        try:
            supabase.rpc('upsert_user_insights', {'u_id': user_id, 'src': 'plan_creation'}).execute()
        except Exception as e:
            logger.info(f"upsert_user_insights failed/ignored for {user_id}: {e}")
        
        # Fetch the insights
        response = supabase.table('user_insights').select('facts, insights').eq('user_id', user_id).single().execute()
        
        if response.data:
            return {
                'facts': response.data.get('facts', {}),
                'insights': response.data.get('insights', {})
            }
        return None
        
    except Exception as e:
        logger.error(f"Failed to fetch user insights for {user_id}: {e}")
        return None

def _analyze_user_history(facts: Dict[str, Any]) -> Dict[str, Any]:
    """Analyze user history patterns from insights facts"""
    analysis = {
        'experience_level': 'beginner',
        'consistency_score': 0.0,
        'avg_session_distance': 0.0,
        'avg_weekly_sessions': 0.0,
        'performance_trend': 'stable',
        'readiness_for_challenge': 'conservative',
        'proven_patterns': []
    }
    
    try:
        # Determine experience level based on total sessions
        all_time_sessions = facts.get('all_time', {}).get('sessions', 0)
        sessions_30d = facts.get('totals_30d', {}).get('sessions', 0)
        
        if all_time_sessions >= 20:
            analysis['experience_level'] = 'advanced'
        elif all_time_sessions >= 10:
            analysis['experience_level'] = 'intermediate'
        
        # Calculate consistency score (sessions in last 30 days vs expected)
        if sessions_30d > 0:
            expected_sessions_30d = 8  # ~2 sessions per week baseline
            analysis['consistency_score'] = min(1.0, sessions_30d / expected_sessions_30d)
            analysis['avg_weekly_sessions'] = sessions_30d / 4.3
        
        # Calculate average session metrics
        if sessions_30d > 0:
            distance_30d = facts.get('totals_30d', {}).get('distance_km', 0)
            analysis['avg_session_distance'] = distance_30d / sessions_30d
        
        # Analyze performance trends from recent splits
        recent_splits = facts.get('recent_splits', [])
        if len(recent_splits) >= 2:
            # Check for negative splits (getting faster during sessions)
            negative_split_count = 0
            consistent_pacing_count = 0
            
            for session in recent_splits:
                splits = session.get('splits', [])
                if len(splits) >= 2:
                    first_pace = splits[0].get('pace_s_per_km')
                    last_pace = splits[-1].get('pace_s_per_km')
                    
                    if first_pace and last_pace:
                        if last_pace < first_pace:
                            negative_split_count += 1
                        elif abs(last_pace - first_pace) / first_pace < 0.1:  # Within 10%
                            consistent_pacing_count += 1
            
            total_sessions_analyzed = len(recent_splits)
            if negative_split_count / total_sessions_analyzed > 0.5:
                analysis['performance_trend'] = 'improving'
                analysis['readiness_for_challenge'] = 'aggressive'
            elif consistent_pacing_count / total_sessions_analyzed > 0.6:
                analysis['performance_trend'] = 'stable'
                analysis['readiness_for_challenge'] = 'moderate'
        
        # Identify proven patterns
        if analysis['consistency_score'] > 0.8:
            analysis['proven_patterns'].append('high_consistency')
        if analysis['avg_session_distance'] > 5.0:
            analysis['proven_patterns'].append('distance_comfort')
        if analysis['performance_trend'] == 'improving':
            analysis['proven_patterns'].append('performance_progression')
            
    except Exception as e:
        logger.error(f"Error analyzing user history: {e}")
    
    return analysis

def _apply_history_adaptations(personalized_structure: Dict[str, Any], adaptations: List[str],
                              user_analysis: Dict[str, Any], base_plan_id: str, user_insights: Optional[Dict[str, Any]] = None) -> None:
    """Apply adaptations based on user's historical patterns"""
    experience = user_analysis.get('experience_level', 'beginner')
    consistency = user_analysis.get('consistency_score', 0.0)
    avg_distance = user_analysis.get('avg_session_distance', 0.0)
    avg_weekly = user_analysis.get('avg_weekly_sessions', 0.0)
    readiness = user_analysis.get('readiness_for_challenge', 'conservative')
    patterns = user_analysis.get('proven_patterns', [])
    
    # Experience-based starting point adjustments
    if experience == 'beginner' and avg_distance == 0:
        # True beginner - very conservative start
        adaptations.append("Starting with beginner-friendly sessions as this appears to be your first structured plan")
        if base_plan_id == 'fat-loss':
            personalized_structure['weekly_ruck_minutes']['start'] = '60-90'
            personalized_structure['starting_load']['percentage'] = '5-8% bodyweight'
    
    elif experience == 'intermediate' and avg_distance > 0:
        # Has some experience - start above their comfort zone
        target_distance = avg_distance * 1.15  # 15% increase
        adaptations.append(f"Based on your recent {avg_distance:.1f}km average, starting at {target_distance:.1f}km to build on your experience")
        
        if base_plan_id == 'fat-loss':
            if avg_distance >= 5:
                personalized_structure['weekly_ruck_minutes']['start'] = '120-150'
            personalized_structure['starting_load']['percentage'] = '10-15% bodyweight'
    
    elif experience == 'advanced':
        # Experienced rucker - can handle more aggressive progression
        all_time_sessions = user_insights.get('facts', {}).get('all_time', {}).get('sessions', 0) if user_insights else 0
        adaptations.append(f"With your extensive rucking experience ({all_time_sessions} total sessions), using accelerated progression")
        
        if base_plan_id in ['fat-loss', 'get-faster']:
            personalized_structure['progression_rate'] = 'aggressive'
            personalized_structure['starting_load']['percentage'] = '15-20% bodyweight'
    
    # Consistency-based frequency adjustments
    if consistency > 0.8 and avg_weekly > 2.5:
        # High consistency - can handle planned frequency
        adaptations.append(f"Your excellent consistency ({consistency*100:.0f}% adherence) supports the full training frequency")
        
    elif consistency > 0.5 and avg_weekly > 0:
        # Moderate consistency - gradual ramp up
        current_weekly = min(4, max(2, int(avg_weekly * 1.2)))
        if 'sessions_per_week' in personalized_structure:
            if 'rucks' in personalized_structure['sessions_per_week']:
                personalized_structure['sessions_per_week']['rucks'] = current_weekly
        adaptations.append(f"Building gradually from your current {avg_weekly:.1f} sessions/week to {current_weekly}/week")
        
    elif avg_weekly > 0:
        # Low consistency - very gradual approach
        conservative_weekly = max(2, int(avg_weekly * 1.1))
        if 'sessions_per_week' in personalized_structure:
            if 'rucks' in personalized_structure['sessions_per_week']:
                personalized_structure['sessions_per_week']['rucks'] = conservative_weekly
        adaptations.append(f"Taking a conservative approach: building from {avg_weekly:.1f} to {conservative_weekly} sessions/week")
    
    # Performance trend adaptations
    if readiness == 'aggressive' and 'performance_progression' in patterns:
        adaptations.append("Your recent negative splits show you're ready for challenging progression")
        if base_plan_id == 'get-faster':
            personalized_structure['intensity_focus'] = 'high'
            personalized_structure['tempo_sessions_per_week'] = 2
    
    elif readiness == 'moderate':
        adaptations.append("Your consistent pacing indicates readiness for steady progression")
        
    elif readiness == 'conservative':
        adaptations.append("Focusing on building consistency before increasing intensity")
        if 'progression_rate' in personalized_structure:
            personalized_structure['progression_rate'] = 'conservative'
    
    # Pattern-specific adaptations
    if 'high_consistency' in patterns:
        adaptations.append("Your proven consistency allows for ambitious goals")
        
    if 'distance_comfort' in patterns:
        adaptations.append(f"Your comfort with longer distances ({avg_distance:.1f}km average) enables distance-focused progressions")
        
        if base_plan_id == 'load-capacity':
            # Can handle more weight with distance experience
            personalized_structure['load_progression']['weekly_increase'] = '2-3kg'
    
    # Add specific historical context
    if avg_distance > 0 and avg_weekly > 0:
        adaptations.append(f"Plan tailored to your pattern: {avg_weekly:.1f} sessions/week averaging {avg_distance:.1f}km")

def _calculate_specific_weights_and_times(personalization: Dict[str, Any], user_analysis: Dict[str, Any], base_plan_id: str) -> Dict[str, Any]:
    """Calculate specific weights and times based on user input and history"""
    calculations = {
        'max_weight_kg': 0,
        'starting_weight_kg': 0,
        'progression_weight_kg': 0,
        'session_times': {},
        'difficulty_assessment': 'appropriate'
    }
    
    # Get user's maximum comfortable weight
    equipment_weight = personalization.get('equipment_weight', 0)
    if equipment_weight > 0:
        calculations['max_weight_kg'] = equipment_weight
        
        # Calculate starting weight based on experience and history
        experience = user_analysis.get('experience_level', 'beginner') if user_analysis else 'beginner'
        avg_distance = user_analysis.get('avg_session_distance', 0) if user_analysis else 0
        
        if experience == 'beginner' or avg_distance == 0:
            # Start conservative: 40-50% of max weight
            calculations['starting_weight_kg'] = round(equipment_weight * 0.45, 1)
            calculations['progression_weight_kg'] = round(equipment_weight * 0.1, 1)  # 10% increments
        elif experience == 'intermediate':
            # Start moderate: 50-60% of max weight
            calculations['starting_weight_kg'] = round(equipment_weight * 0.55, 1)
            calculations['progression_weight_kg'] = round(equipment_weight * 0.08, 1)  # 8% increments
        else:  # advanced
            # Start higher: 60-70% of max weight
            calculations['starting_weight_kg'] = round(equipment_weight * 0.65, 1)
            calculations['progression_weight_kg'] = round(equipment_weight * 0.06, 1)  # 6% increments
    
    # Calculate session times based on history and constraints
    min_session_time = personalization.get('minimum_session_minutes', 30)
    training_days = personalization.get('training_days_per_week', 3)
    
    if user_analysis:
        avg_weekly_sessions = user_analysis.get('avg_weekly_sessions', 0)
        consistency = user_analysis.get('consistency_score', 0)
        
        # Assess if current plan difficulty is appropriate
        if avg_weekly_sessions > 0:
            if training_days > avg_weekly_sessions * 1.5:
                calculations['difficulty_assessment'] = 'too_hard'
            elif training_days < avg_weekly_sessions * 0.8:
                calculations['difficulty_assessment'] = 'too_easy'
        
        # Calculate realistic session times
        if base_plan_id == 'fat-loss':
            if consistency > 0.8:
                calculations['session_times']['long_ruck'] = max(45, min_session_time + 15)
                calculations['session_times']['balance_ruck'] = max(30, min_session_time)
                calculations['session_times']['speed_ruck'] = max(25, min_session_time - 5)
            else:
                calculations['session_times']['long_ruck'] = max(35, min_session_time + 5)
                calculations['session_times']['balance_ruck'] = max(25, min_session_time - 5)
                calculations['session_times']['speed_ruck'] = max(20, min_session_time - 10)
    
    return calculations

def _generate_weekly_template_with_specifics(base_plan_id: str, calculations: Dict[str, Any], 
                                           personalization: Dict[str, Any], user_analysis: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Generate weekly template with specific weights and times instead of placeholders"""
    weekly_template = []
    
    start_weight = calculations.get('starting_weight_kg', 20)
    progression_weight = calculations.get('progression_weight_kg', 2)
    session_times = calculations.get('session_times', {})
    
    # Get user constraints
    min_session_time = personalization.get('minimum_session_minutes', 30)
    training_days = personalization.get('training_days_per_week', 3)
    equipment_type = personalization.get('equipment_type', 'rucksack')
    
    if base_plan_id == 'posture-balance-age-strong':
        # Tuesday: Long Posture Ruck
        tuesday_weight = start_weight * 0.8  # 80% of starting weight for posture work
        tuesday_time = session_times.get('long_ruck', max(40, min_session_time + 10))
        
        weekly_template.append({
            'day': 'tuesday',
            'session_type': 'Long Posture Ruck',
            'duration_minutes': f'{tuesday_time}-{tuesday_time + 10}',
            'weight_kg': round(tuesday_weight, 1),
            'description': f'{tuesday_time}-{tuesday_time + 10} min @ {round(tuesday_weight, 1)}kg, steady pace',
            'notes': 'Every 10 min, pause for 1 min suitcase carry (switch hands)',
            'equipment': equipment_type
        })
        
        # Thursday: Balance & Mobility Ruck
        thursday_weight = start_weight * 0.6  # 60% for balance work
        thursday_time = session_times.get('balance_ruck', max(30, min_session_time))
        
        weekly_template.append({
            'day': 'thursday',
            'session_type': 'Balance & Mobility Ruck',
            'duration_minutes': thursday_time,
            'weight_kg': round(thursday_weight, 1),
            'description': f'{thursday_time} min @ {round(thursday_weight, 1)}kg',
            'notes': '2x stair step-ups (5 min unloaded), 2x sit-to-stand after ruck',
            'equipment': equipment_type
        })
        
        # Saturday: Speed/Confidence Ruck
        saturday_weight = start_weight * 1.0  # Full starting weight for confidence
        saturday_time = session_times.get('speed_ruck', max(20, min_session_time - 10))
        
        weekly_template.append({
            'day': 'saturday',
            'session_type': 'Speed/Confidence Ruck',
            'duration_minutes': f'{saturday_time}-{saturday_time + 10}',
            'weight_kg': round(saturday_weight, 1),
            'description': f'{saturday_time}-{saturday_time + 10} min @ {round(saturday_weight, 1)}kg',
            'notes': 'Brisk pace (can talk, not sing), focus on upright posture',
            'equipment': equipment_type
        })
        
        # Sunday: Form Walk
        weekly_template.append({
            'day': 'sunday',
            'session_type': 'Form Walk',
            'duration_minutes': 20,
            'weight_kg': 0,
            'description': '20 min unloaded (rain/recovery option)',
            'notes': 'Focus on posture and breathing patterns',
            'equipment': 'none'
        })
    
    elif base_plan_id == 'fat-loss':
        # Generate fat-loss specific template with calculated weights/times
        base_ruck_time = session_times.get('long_ruck', max(45, min_session_time + 15))
        
        weekly_template.extend([
            {
                'day': 'monday',
                'session_type': 'Base Ruck',
                'duration_minutes': base_ruck_time,
                'weight_kg': round(start_weight * 0.7, 1),
                'description': f'{base_ruck_time} min @ {round(start_weight * 0.7, 1)}kg, conversational pace',
                'equipment': equipment_type
            },
            {
                'day': 'wednesday',
                'session_type': 'Interval Ruck',
                'duration_minutes': 35,
                'weight_kg': round(start_weight * 0.8, 1),
                'description': f'35 min @ {round(start_weight * 0.8, 1)}kg, 5x (3min brisk / 2min easy)',
                'equipment': equipment_type
            },
            {
                'day': 'friday',
                'session_type': 'Recovery Ruck',
                'duration_minutes': 25,
                'weight_kg': round(start_weight * 0.5, 1),
                'description': f'25 min @ {round(start_weight * 0.5, 1)}kg, very easy pace',
                'equipment': equipment_type
            }
        ])
    
    # Add difficulty assessment to each session
    difficulty = calculations.get('difficulty_assessment', 'appropriate')
    for session in weekly_template:
        if difficulty == 'too_hard':
            session['difficulty_note'] = 'Reduced intensity based on your current training frequency'
        elif difficulty == 'too_easy':
            session['difficulty_note'] = 'Can progress faster given your training history'
        else:
            session['difficulty_note'] = 'Appropriate challenge level for your experience'
    
    return weekly_template

def personalize_plan(base_plan_id: str, personalization: Dict[str, Any], supabase_client, user_id: str = None) -> Dict[str, Any]:
    """
    Generate a personalized plan based on the base plan, user's personalization data, and historical patterns
    """
    templates = _get_coaching_plan_templates(supabase_client)
    base_plan = templates.get(base_plan_id)
    if not base_plan:
        raise ValueError(f"Unknown base plan: {base_plan_id}")
    
    # Get user insights for history-aware personalization
    user_insights = None
    user_analysis = None
    if user_id:
        user_insights = _get_user_insights(user_id)
        if user_insights:
            user_analysis = _analyze_user_history(user_insights['facts'])
            logger.info(f"User analysis for {user_id}: {user_analysis}")
    
    # Calculate specific weights and times
    calculations = _calculate_specific_weights_and_times(personalization, user_analysis, base_plan_id)
    
    # Start with the base structure
    personalized_structure = json.loads(json.dumps(base_plan['base_structure']))  # Deep copy
    adaptations = []

    # Generate specific weekly template with calculated weights and times
    specific_weekly_template = _generate_weekly_template_with_specifics(
        base_plan_id, calculations, personalization, user_analysis
    )
    
    # Add new template fields to personalized structure
    personalized_structure['weekly_template'] = specific_weekly_template
    personalized_structure['hydration_fueling'] = base_plan.get('hydration_fueling', {})
    personalized_structure['weekly_volume_cap'] = base_plan.get('weekly_volume_increase_cap', 10.0)
    personalized_structure['no_dual_progressions'] = base_plan.get('no_dual_progressions', False)
    personalized_structure['sources'] = base_plan.get('sources', [])

    # Apply history-based adaptations first
    if user_analysis:
        _apply_history_adaptations(personalized_structure, adaptations, user_analysis, base_plan_id, user_insights)

        # Apply volume cap based on user's recent increases
        if personalized_structure.get('weekly_volume_cap'):
            volume_cap = personalized_structure['weekly_volume_cap']
            # If user has been increasing volume too quickly, enforce the cap
            adaptations.append(f"Volume increases capped at {volume_cap}% per week for safe progression")

        # Apply no dual progressions rule if set
        if personalized_structure.get('no_dual_progressions'):
            adaptations.append("Focusing on one progression variable at a time (distance OR weight, not both)")
            personalized_structure['progression_strategy'] = 'single_variable'
    
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
    
    # 4. Handle equipment preferences
    equipment_type = personalization.get('equipment_type')
    equipment_weight = personalization.get('equipment_weight')

    if equipment_type:
        if equipment_type == 'none':
            adaptations.append("Bodyweight and alternative loading methods emphasized until equipment acquired")
            personalized_structure['equipment_notes'] = 'Start with household items in a regular backpack'
        elif equipment_type == 'vest':
            adaptations.append("Weighted vest adaptations provided for all sessions")
            personalized_structure['equipment_notes'] = 'Vest-specific form cues included'
        elif equipment_type == 'both':
            adaptations.append("Mix of ruck and vest sessions for variety")
            personalized_structure['equipment_notes'] = 'Alternate between ruck and vest for different stimulus'

        if equipment_weight and equipment_weight > 0:
            # Use calculated specific weights instead of percentages
            start_weight = calculations['starting_weight_kg']
            progression_weight = calculations['progression_weight_kg']
            
            personalized_structure['starting_load'] = {
                'weight_kg': start_weight,
                'progression_kg': progression_weight,
                'max_weight_kg': equipment_weight
            }
            
            # Add difficulty assessment
            difficulty = calculations['difficulty_assessment']
            if difficulty == 'too_hard':
                adaptations.append(f"Starting conservatively at {start_weight}kg (reduced from typical progression) based on your current training frequency")
            elif difficulty == 'too_easy':
                adaptations.append(f"Starting at {start_weight}kg with faster progression available given your consistent training history")
            else:
                adaptations.append(f"Starting at {start_weight}kg with {progression_weight}kg increments, progressing toward your {equipment_weight}kg capacity")

    # 5. Adjust based on success definition (affects focus areas)
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

    # 6. Process custom question responses from plan-specific questions
    custom_responses = personalization.get('customResponses', {})
    if custom_responses:
        # Load Capacity Builder specific
        if base_plan_id == 'load-capacity':
            target_load_kg = custom_responses.get('targetLoadKg')
            current_max_load_kg = custom_responses.get('currentMaxLoadKg')
            injury_concerns = custom_responses.get('injuryConcerns', [])

            if target_load_kg and current_max_load_kg:
                load_gap = target_load_kg - current_max_load_kg
                weeks_needed = int(load_gap / 2.5) + 4  # ~2.5kg per fortnight + buffer
                personalized_structure['target_load'] = f"{target_load_kg}kg target in ~{weeks_needed} weeks"
                adaptations.append(f"Progressing from {current_max_load_kg}kg to {target_load_kg}kg goal")

            if injury_concerns:
                if 'Back' in injury_concerns:
                    adaptations.append("Core strengthening and posture focus for back protection")
                if 'Knees' in injury_concerns:
                    adaptations.append("Emphasis on flat terrain initially with gradual hill introduction")

        # Fat Loss specific
        elif base_plan_id == 'fat-loss':
            weight_loss_target = custom_responses.get('weightLossTargetKg')
            activity_level = custom_responses.get('currentActivityLevel')

            if weight_loss_target:
                weekly_target = weight_loss_target / 12  # 12-week plan
                personalized_structure['calorie_deficit_target'] = f"{weekly_target:.1f}kg/week deficit"
                adaptations.append(f"Calibrated for {weight_loss_target}kg loss over 12 weeks")

            if activity_level:
                if activity_level in ['sedentary', 'light']:
                    personalized_structure['starting_volume'] = 'Conservative 90-minute weekly start'
                    adaptations.append("Gradual volume build for sustainable habit formation")

        # Event Prep specific
        elif base_plan_id == 'event-prep':
            event_date = custom_responses.get('eventDate')
            event_distance = custom_responses.get('eventDistanceKm')
            event_load = custom_responses.get('eventLoadKg')

            if event_date:
                from datetime import datetime
                event_dt = datetime.fromisoformat(event_date.replace('Z', '+00:00'))
                days_until = (event_dt - datetime.now()).days
                personalized_structure['taper_week'] = max(1, (days_until // 7) - 1)
                adaptations.append(f"Taper scheduled for week {personalized_structure['taper_week']}")

            if event_distance:
                personalized_structure['event_distance'] = f"{event_distance}km"
                if event_distance > 20:
                    adaptations.append("Extended long ruck progression for ultra-distance preparation")

            if event_load:
                personalized_structure['event_load'] = f"{event_load}kg required"
                adaptations.append(f"Progressive loading to reach {event_load}kg event weight")

        # Get Faster specific
        elif base_plan_id == 'get-faster':
            current_pace = custom_responses.get('currentPaceMinPerKm')
            target_pace = custom_responses.get('targetPaceMinPerKm')
            speed_experience = custom_responses.get('speedWorkExperience')

            if current_pace and target_pace:
                pace_improvement = current_pace - target_pace
                personalized_structure['pace_targets'] = {
                    'current': f"{current_pace} min/km",
                    'target': f"{target_pace} min/km",
                    'improvement': f"{pace_improvement} min/km"
                }
                adaptations.append(f"Targeting {pace_improvement} min/km pace improvement")

            if speed_experience == 'none':
                personalized_structure['interval_progression'] = 'Conservative with education focus'
                adaptations.append("Gradual introduction to interval training with form emphasis")

        # Age Strong specific
        elif base_plan_id == 'age-strong':
            primary_goals = custom_responses.get('primaryGoals', [])
            mobility_concerns = custom_responses.get('mobilityConcerns', [])

            if 'Better posture' in primary_goals:
                adaptations.append("Core and upper back strengthening for posture improvement")
            if 'Improved balance' in primary_goals:
                adaptations.append("Single-leg and stability work integrated throughout")

            if 'Stairs difficult' in mobility_concerns:
                personalized_structure['progression'] = 'Flat terrain focus with gradual incline introduction'
                adaptations.append("Building strength for stair climbing confidence")
    
    # 6. Preferred days scheduling
    training_schedule = []
    preferred_days = personalization.get('preferred_days', [])

    # Use weekly_template to structure the week if available
    if personalized_structure.get('weekly_template'):
        weekly_template = personalized_structure['weekly_template']
        if weekly_template and len(weekly_template) > 0:
            # Map template sessions to preferred days
            adaptations.append("Using science-based weekly template for optimal recovery and progression")
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
    
    # Add hydration/fueling guidance if available
    hydration_fueling_guidance = personalized_structure.get('hydration_fueling', {})
    if hydration_fueling_guidance:
        adaptations.append("Includes specific hydration and fueling recommendations")

    return {
        'base_plan_id': base_plan_id,
        'personalized_structure': personalized_structure,
        'training_schedule': training_schedule,
        'adaptations': adaptations,
        'user_analysis': user_analysis,
        'calculations': calculations,
        'hydration_fueling': hydration_fueling_guidance,
        'weekly_template': specific_weekly_template,
        'sources': personalized_structure.get('sources', [])
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

            # Check if user already has an active coaching plan
            existing_plan = supabase.table('user_coaching_plans').select('id').eq(
                'user_id', g.user_id
            ).eq('current_status', 'active').limit(1).execute()

            if existing_plan.data:
                return error_response("User already has an active coaching plan", 409)

            # Get coaching plan templates from database
            templates = _get_coaching_plan_templates(supabase)
            
            # Validate base plan exists
            if base_plan_id not in templates:
                return error_response(f"Invalid base plan ID: {base_plan_id}", 400)
            
            base_plan = templates[base_plan_id]
            
            # Generate personalized plan with user history
            try:
                personalized_plan = personalize_plan(base_plan_id, personalization, supabase, g.user_id)
            except Exception as e:
                logger.error(f"Error in personalize_plan: {e}")
                return error_response(f"Error personalizing plan: {str(e)}", 500)
            
            # Check if user already has an active plan of this type
            existing_response = supabase.table("user_coaching_plans").select("id").eq(
                "user_id", g.user_id
            ).eq("coaching_plan_id", base_plan['id']).eq("current_status", "active").execute()

            if existing_response.data:
                # Archive the existing plan using admin client
                admin_supabase = get_supabase_admin_client()
                admin_supabase.table("user_coaching_plans").update({
                    "current_status": "archived"
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

            # Insert into user_coaching_plans table (not coaching_plans!)
            user_plan_data = {
                "user_id": g.user_id,
                "coaching_plan_id": base_plan['id'],  # Use the integer ID from the template
                "coaching_personality": coaching_personality,
                "start_date": datetime.now().isoformat(),
                "current_week": 1,
                "current_status": "active",
                "plan_modifications": {
                    "personalization": personalization,
                    "plan_structure": personalized_plan['personalized_structure'],
                    "adaptations": personalized_plan['adaptations'],
                    "plan_type": base_plan_id  # Keep the string ID for reference
                }
            }

            # Use admin client to bypass RLS for insert
            admin_supabase = get_supabase_admin_client()
            response = admin_supabase.table("user_coaching_plans").insert(user_plan_data).execute()

            # Also save equipment preferences to user profile
            equipment_type = personalization.get('equipment_type')
            equipment_weight = personalization.get('equipment_weight')
            if equipment_type or equipment_weight:
                user_update = {}
                if equipment_type:
                    user_update['equipment_type'] = equipment_type
                if equipment_weight:
                    user_update['equipment_weight_kg'] = equipment_weight

                admin_supabase.table("users").update(user_update).eq("id", g.user_id).execute()
            
            if not response.data:
                return error_response("Failed to create coaching plan", 500)
            
            created_plan = response.data[0]
            
            # Clean response data to prevent JSON serialization errors
            clean_plan = {}
            for key, value in created_plan.items():
                if hasattr(value, '__dict__') and hasattr(value, 'data'):
                    # Skip Supabase Response objects
                    continue
                clean_plan[key] = value
            
            return success_response({
                "coaching_plan": clean_plan,
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
            query = supabase.table("user_coaching_plans").select("*").eq("user_id", g.user_id)
            
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
            response = supabase.table("user_coaching_plans").select("*").eq("id", plan_id).eq("user_id", g.user_id).execute()
            
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
            
            response = supabase.table("user_coaching_plans").update(update_data).eq("id", plan_id).eq("user_id", g.user_id).execute()
            
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