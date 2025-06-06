from flask import request, g
from flask_restful import Resource
from marshmallow import Schema, fields, ValidationError
from datetime import datetime
from RuckTracker.supabase_client import get_supabase_client
from api.auth import auth_required

# ============================================================================
# SCHEMAS
# ============================================================================

class DuelProgressUpdateSchema(Schema):
    session_id = fields.Str(required=True)
    contribution_value = fields.Float(required=True, validate=lambda x: x >= 0)

# ============================================================================
# RESOURCES
# ============================================================================

class DuelParticipantProgressResource(Resource):
    @auth_required
    def post(self, duel_id, participant_id):
        """Update participant progress from completed session"""
        try:
            schema = DuelProgressUpdateSchema()
            data = schema.load(request.get_json())
            user_id = g.user.id
            
            supabase = get_supabase_client()
            
            # Verify participant belongs to user and duel is active
            participant_response = supabase.table('duel_participants').select('id, user_id, current_value, duel_id(status, challenge_type, ends_at, target_value)').eq('id', participant_id).eq('duel_id', duel_id).eq('user_id', user_id).execute()
            
            participant = participant_response.data[0] if participant_response.data else None
            if not participant:
                return {'error': 'Participant not found or unauthorized'}, 404
            
            duel = participant['duel_id']
            if duel['status'] != 'active':
                return {'error': 'Duel is not active'}, 400
            
            if duel['ends_at'] and datetime.utcnow() > datetime.fromisoformat(duel['ends_at']):
                return {'error': 'Duel has ended'}, 400
            
            # Verify session exists and belongs to user
            session_response = supabase.table('ruck_sessions').select('id, user_id, status, distance_km, duration_minutes, completed_at').eq('id', data['session_id']).eq('user_id', user_id).execute()
            
            session = session_response.data[0] if session_response.data else None
            if not session:
                return {'error': 'Session not found or unauthorized'}, 404
            
            if session['status'] != 'completed':
                return {'error': 'Session is not completed'}, 400
            
            # Check if session was already counted for this duel
            duel_session_response = supabase.table('duel_sessions').select('id').eq('duel_id', duel_id).eq('participant_id', participant_id).eq('session_id', data['session_id']).execute()
            
            if duel_session_response.data:
                return {'error': 'Session already counted for this duel'}, 400
            
            # Calculate contribution based on challenge type
            contribution = 0
            if duel['challenge_type'] == 'distance':
                contribution = session['distance_km']
            elif duel['challenge_type'] == 'duration':
                contribution = session['duration_minutes']
            else:
                contribution = data['contribution_value']  # For custom challenges
            
            # Update participant progress
            new_value = participant['current_value'] + contribution
            now = datetime.utcnow()
            
            supabase.table('duel_participants').update({
                'current_value': new_value,
                'updated_at': now.isoformat()
            }).eq('id', participant_id).execute()
            
            # Record the session contribution
            supabase.table('duel_sessions').insert([{
                'duel_id': duel_id,
                'participant_id': participant_id,
                'session_id': data['session_id'],
                'contribution_value': contribution,
                'created_at': now.isoformat()
            }]).execute()
            
            # Get user name for notification
            user_response = supabase.table('users').select('username').eq('id', user_id).single().execute()
            user_name = user_response.data.get('username', 'Unknown User') if user_response.data else 'Unknown User'
            
            # Create duel progress notification for other participants
            from api.duel_comments import create_duel_progress_notification
            create_duel_progress_notification(duel_id, user_id, user_name, data['session_id'])
            
            # Check if participant reached target
            achievement = None
            if new_value >= duel['target_value']:
                achievement = 'target_reached'
                supabase.table('duel_participants').update({
                    'target_reached_at': now.isoformat()
                }).eq('id', participant_id).execute()
            
            # Check if duel should be completed (all active participants reached target or time expired)
            participants_response = supabase.table('duel_participants').select('id, current_value, target_reached_at').eq('duel_id', duel_id).eq('status', 'accepted').execute()
            
            all_completed = all(p['target_reached_at'] for p in participants_response.data)
            
            if all_completed or (duel['ends_at'] and datetime.utcnow() > datetime.fromisoformat(duel['ends_at'])):
                # Complete the duel and determine winner
                max_value = max((p['current_value'] for p in participants_response.data), default=0)
                winners = [p for p in participants_response.data if p['current_value'] == max_value]
                
                if len(winners) == 1:
                    winner_participant = winners[0]
                    winner_response = supabase.table('duel_participants').select('user_id').eq('id', winner_participant['id']).execute()
                    winner_id = winner_response.data[0]['user_id']
                    
                    supabase.table('duels').update({
                        'status': 'completed',
                        'winner_id': winner_id,
                        'completed_at': now.isoformat(),
                        'updated_at': now.isoformat()
                    }).eq('id', duel_id).execute()
                    
                    # Update winner stats
                    supabase.table('user_duel_stats').upsert([{
                        'user_id': winner_id,
                        'duels_won': 1,
                        'updated_at': now.isoformat()
                    }], on_conflict='user_id').execute()
                    
                    # Create duel completed notification for all participants
                    from api.duel_comments import create_duel_completed_notification
                    create_duel_completed_notification(duel_id)
                else:
                    # Tie
                    supabase.table('duels').update({
                        'status': 'completed',
                        'completed_at': now.isoformat(),
                        'updated_at': now.isoformat()
                    }).eq('id', duel_id).execute()
                    
                    # Create duel completed notification for all participants
                    from api.duel_comments import create_duel_completed_notification
                    create_duel_completed_notification(duel_id)
            
            return {
                'message': 'Progress updated successfully',
                'new_value': new_value,
                'contribution': contribution,
                'achievement': achievement
            }
            
        except ValidationError as e:
            return {'error': str(e)}, 400
        except Exception as e:
            return {'error': str(e)}, 500

    @auth_required
    def get(self, duel_id, participant_id):
        """Get participant's detailed progress including sessions"""
        try:
            user_id = g.user.id
            supabase = get_supabase_client()
            
            # Get participant info
            participant_response = supabase.table('duel_participants').select('id, user_id, current_value, duel_id(challenge_type, target_value, status as duel_status)').eq('id', participant_id).eq('duel_id', duel_id).execute()
            
            participant = participant_response.data[0] if participant_response.data else None
            if not participant:
                return {'error': 'Participant not found'}, 404
            
            # Get contributing sessions
            sessions_response = supabase.table('duel_sessions').select('id, session_id, contribution_value, created_at').eq('duel_id', duel_id).eq('participant_id', participant_id).order('created_at', desc=True).execute()
            
            sessions = sessions_response.data
            
            # Get session details
            session_ids = [s['session_id'] for s in sessions]
            session_response = supabase.table('ruck_sessions').select('id, start_time, end_time, distance, duration, elevation_gain, power_points').in_('id', session_ids).execute()
            
            session_details = {s['id']: s for s in session_response.data}
            
            # Combine session details with contributions
            sessions = [{'id': s['id'], 'session_id': s['session_id'], 'contribution_value': s['contribution_value'], 'created_at': s['created_at'], **session_details[s['session_id']]} for s in sessions]
            
            result = dict(participant)
            result['contributing_sessions'] = sessions
            result['progress_percentage'] = min((participant['current_value'] / participant['duel_id']['target_value']) * 100, 100)
            
            return result
            
        except Exception as e:
            return {'error': str(e)}, 500


class DuelLeaderboardResource(Resource):
    @auth_required
    def get(self, duel_id):
        """Get real-time leaderboard for a duel"""
        try:
            supabase = get_supabase_client()
            
            # Verify duel exists
            duel_response = supabase.table('duels').select('id, status, challenge_type, target_value, ends_at').eq('id', duel_id).execute()
            
            duel = duel_response.data[0] if duel_response.data else None
            if not duel:
                return {'error': 'Duel not found'}, 404
            
            # Get leaderboard
            leaderboard_response = supabase.table('duel_participants').select('id, user_id, current_value, status, last_session_id, duel_id(challenge_type, target_value)').eq('duel_id', duel_id).eq('status', 'accepted').order('current_value', desc=True).execute()
            
            participants = leaderboard_response.data
            
            # Get user details
            user_ids = [p['user_id'] for p in participants]
            user_response = supabase.table('users').select('id, username, email').in_('id', user_ids).execute()
            
            user_details = {u['id']: u for u in user_response.data}
            
            # Combine participant details with user details
            participants = [{'id': p['id'], 'user_id': p['user_id'], 'current_value': p['current_value'], 'status': p['status'], 'last_session_id': p['last_session_id'], 'duel_id': p['duel_id'], **user_details[p['user_id']]} for p in participants]
            
            # Get recent activity
            recent_activity_response = supabase.table('duel_sessions').select('id, duel_id, participant_id, session_id, contribution_value, created_at').eq('duel_id', duel_id).order('created_at', desc=True).limit(10).execute()
            
            recent_activity = recent_activity_response.data
            
            # Get session details
            session_ids = [a['session_id'] for a in recent_activity]
            session_response = supabase.table('ruck_sessions').select('id, start_time, end_time, distance, duration, elevation_gain, power_points').in_('id', session_ids).execute()
            
            session_details = {s['id']: s for s in session_response.data}
            
            # Combine recent activity with session details
            recent_activity = [{'id': a['id'], 'duel_id': a['duel_id'], 'participant_id': a['participant_id'], 'session_id': a['session_id'], 'contribution_value': a['contribution_value'], 'created_at': a['created_at'], **session_details[a['session_id']]} for a in recent_activity]
            
            return {
                'duel': dict(duel),
                'leaderboard': participants,
                'recent_activity': recent_activity
            }
            
        except Exception as e:
            return {'error': str(e)}, 500
