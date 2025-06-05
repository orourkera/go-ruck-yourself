from flask import request, g
from flask_restful import Resource
from marshmallow import Schema, fields, ValidationError
from datetime import datetime
from extensions import db
from utils.auth import auth_required
from utils.error_handling import handle_validation_error, handle_not_found_error

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
            user_id = g.current_user['id']
            
            cursor = db.connection.cursor()
            
            # Verify participant belongs to user and duel is active
            cursor.execute('''
                SELECT dp.id, dp.user_id, dp.current_value, d.status, d.challenge_type,
                       d.ends_at, d.target_value
                FROM duel_participants dp
                JOIN duels d ON dp.duel_id = d.id
                WHERE dp.id = %s AND dp.duel_id = %s AND dp.user_id = %s
            ''', [participant_id, duel_id, user_id])
            
            participant = cursor.fetchone()
            if not participant:
                return handle_not_found_error('Participant not found or unauthorized')
            
            if participant['status'] != 'active':
                return {'error': 'Duel is not active'}, 400
            
            if participant['ends_at'] and datetime.utcnow() > participant['ends_at']:
                return {'error': 'Duel has ended'}, 400
            
            # Verify session exists and belongs to user
            cursor.execute('''
                SELECT id FROM ruck_sessions 
                WHERE id = %s AND user_id = %s AND end_time IS NOT NULL
            ''', [data['session_id'], user_id])
            
            session = cursor.fetchone()
            if not session:
                return {'error': 'Session not found or not completed'}, 400
            
            # Check if session already contributed to this duel
            cursor.execute('''
                SELECT id FROM duel_sessions 
                WHERE duel_id = %s AND session_id = %s
            ''', [duel_id, data['session_id']])
            
            if cursor.fetchone():
                return {'error': 'Session already contributed to this duel'}, 400
            
            # Record the duel session contribution
            duel_session_id = str(uuid.uuid4())
            now = datetime.utcnow()
            
            cursor.execute('''
                INSERT INTO duel_sessions (
                    id, duel_id, participant_id, session_id, 
                    contribution_value, created_at, updated_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            ''', [
                duel_session_id, duel_id, participant_id, 
                data['session_id'], data['contribution_value'], now, now
            ])
            
            # Update participant's current value
            new_current_value = participant['current_value'] + data['contribution_value']
            cursor.execute('''
                UPDATE duel_participants 
                SET current_value = %s, last_session_id = %s, updated_at = %s
                WHERE id = %s
            ''', [new_current_value, data['session_id'], now, participant_id])
            
            # Check if participant reached target and potentially won
            target_reached = new_current_value >= participant['target_value']
            duel_completed = False
            winner_id = None
            
            if target_reached:
                # Check if this is the first to reach target
                cursor.execute('''
                    SELECT dp.user_id, dp.current_value 
                    FROM duel_participants dp
                    WHERE dp.duel_id = %s AND dp.current_value >= %s
                    ORDER BY dp.updated_at ASC
                    LIMIT 1
                ''', [duel_id, participant['target_value']])
                
                first_to_target = cursor.fetchone()
                if first_to_target and first_to_target['user_id'] == user_id:
                    # This user won!
                    winner_id = user_id
                    duel_completed = True
                    
                    # Update duel status
                    cursor.execute('''
                        UPDATE duels 
                        SET status = 'completed', winner_id = %s, updated_at = %s
                        WHERE id = %s
                    ''', [winner_id, now, duel_id])
                    
                    # Update all participants' stats
                    cursor.execute('''
                        SELECT user_id FROM duel_participants 
                        WHERE duel_id = %s AND status = 'accepted'
                    ''', [duel_id])
                    all_participants = cursor.fetchall()
                    
                    for p in all_participants:
                        is_winner = p['user_id'] == winner_id
                        cursor.execute('''
                            INSERT INTO user_duel_stats (
                                user_id, duels_completed, duels_won, duels_lost, 
                                created_at, updated_at
                            ) VALUES (%s, 1, %s, %s, %s, %s)
                            ON CONFLICT (user_id) 
                            DO UPDATE SET 
                                duels_completed = user_duel_stats.duels_completed + 1,
                                duels_won = user_duel_stats.duels_won + %s,
                                duels_lost = user_duel_stats.duels_lost + %s,
                                updated_at = %s
                        ''', [
                            p['user_id'], 1 if is_winner else 0, 0 if is_winner else 1,
                            now, now, 1 if is_winner else 0, 0 if is_winner else 1, now
                        ])
            
            db.connection.commit()
            cursor.close()
            
            result = {
                'message': 'Progress updated successfully',
                'current_value': new_current_value,
                'target_reached': target_reached
            }
            
            if duel_completed:
                result['duel_completed'] = True
                result['winner_id'] = winner_id
                result['is_winner'] = winner_id == user_id
            
            return result
            
        except ValidationError as e:
            return handle_validation_error(e)
        except Exception as e:
            db.connection.rollback()
            return {'error': str(e)}, 500

    @auth_required
    def get(self, duel_id, participant_id):
        """Get participant's detailed progress including sessions"""
        try:
            user_id = g.current_user['id']
            cursor = db.connection.cursor()
            
            # Get participant info
            cursor.execute('''
                SELECT dp.*, u.username, d.challenge_type, d.target_value, d.status as duel_status
                FROM duel_participants dp
                JOIN users u ON dp.user_id = u.id
                JOIN duels d ON dp.duel_id = d.id
                WHERE dp.id = %s AND dp.duel_id = %s
            ''', [participant_id, duel_id])
            
            participant = cursor.fetchone()
            if not participant:
                return handle_not_found_error('Participant not found')
            
            # Get contributing sessions
            cursor.execute('''
                SELECT ds.*, rs.start_time, rs.end_time, rs.distance, 
                       rs.duration, rs.elevation_gain, rs.power_points
                FROM duel_sessions ds
                JOIN ruck_sessions rs ON ds.session_id = rs.id
                WHERE ds.duel_id = %s AND ds.participant_id = %s
                ORDER BY ds.created_at DESC
            ''', [duel_id, participant_id])
            
            sessions = cursor.fetchall()
            cursor.close()
            
            result = dict(participant)
            result['contributing_sessions'] = [dict(s) for s in sessions]
            result['progress_percentage'] = min((participant['current_value'] / participant['target_value']) * 100, 100)
            
            return result
            
        except Exception as e:
            return {'error': str(e)}, 500


class DuelLeaderboardResource(Resource):
    @auth_required
    def get(self, duel_id):
        """Get real-time leaderboard for a duel"""
        try:
            cursor = db.connection.cursor()
            
            # Verify duel exists
            cursor.execute('''
                SELECT id, status, challenge_type, target_value, ends_at
                FROM duels WHERE id = %s
            ''', [duel_id])
            duel = cursor.fetchone()
            
            if not duel:
                return handle_not_found_error('Duel not found')
            
            # Get leaderboard
            cursor.execute('''
                SELECT dp.id, dp.user_id, dp.current_value, dp.status, dp.last_session_id,
                       u.username, u.email,
                       RANK() OVER (ORDER BY dp.current_value DESC, dp.updated_at ASC) as rank,
                       CASE 
                           WHEN dp.current_value >= %s THEN true 
                           ELSE false 
                       END as target_reached
                FROM duel_participants dp
                JOIN users u ON dp.user_id = u.id
                WHERE dp.duel_id = %s AND dp.status = 'accepted'
                ORDER BY dp.current_value DESC, dp.updated_at ASC
            ''', [duel['target_value'], duel_id])
            
            participants = cursor.fetchall()
            
            # Get recent activity
            cursor.execute('''
                SELECT ds.contribution_value, ds.created_at, u.username,
                       rs.distance, rs.duration, rs.elevation_gain, rs.power_points
                FROM duel_sessions ds
                JOIN duel_participants dp ON ds.participant_id = dp.id
                JOIN users u ON dp.user_id = u.id
                JOIN ruck_sessions rs ON ds.session_id = rs.id
                WHERE ds.duel_id = %s
                ORDER BY ds.created_at DESC
                LIMIT 10
            ''', [duel_id])
            
            recent_activity = cursor.fetchall()
            cursor.close()
            
            return {
                'duel': dict(duel),
                'leaderboard': [dict(p) for p in participants],
                'recent_activity': [dict(a) for a in recent_activity]
            }
            
        except Exception as e:
            return {'error': str(e)}, 500

import uuid
