from flask import request, g
from flask_restful import Resource
from marshmallow import Schema, fields, ValidationError, validates_schema
from datetime import datetime, timedelta
import uuid
from extensions import db
from api.auth import auth_required

# ============================================================================
# SCHEMAS
# ============================================================================

class DuelCreateSchema(Schema):
    title = fields.Str(required=True, validate=lambda x: 1 <= len(x) <= 50)
    challenge_type = fields.Str(required=True, validate=lambda x: x in ['distance', 'time', 'elevation', 'power_points'])
    target_value = fields.Float(required=True, validate=lambda x: x > 0)
    timeframe_hours = fields.Int(required=True, validate=lambda x: 1 <= x <= 168)  # 1 hour to 1 week
    is_public = fields.Bool(missing=True)
    max_participants = fields.Int(missing=2, validate=lambda x: 2 <= x <= 20)
    invitee_emails = fields.List(fields.Email(), missing=[])

    @validates_schema
    def validate_schema(self, data, **kwargs):
        if not data.get('is_public', True) and not data.get('invitee_emails', []):
            raise ValidationError('Private duels must include invitee emails')

class DuelUpdateSchema(Schema):
    status = fields.Str(validate=lambda x: x in ['active', 'cancelled'])

class DuelParticipantSchema(Schema):
    status = fields.Str(required=True, validate=lambda x: x in ['accepted', 'declined'])

# ============================================================================
# RESOURCES
# ============================================================================

class DuelListResource(Resource):
    @auth_required
    def get(self):
        """Get list of duels with filtering"""
        try:
            user_id = g.current_user['id']
            
            # Query parameters
            status = request.args.get('status', 'active')
            challenge_type = request.args.get('challenge_type')
            is_public = request.args.get('is_public', 'true').lower() == 'true'
            page = int(request.args.get('page', 1))
            per_page = min(int(request.args.get('per_page', 20)), 100)
            
            # Base query for public duels or user's duels
            query = '''
                SELECT d.*, 
                       u.username as creator_username,
                       COUNT(dp.id) as participant_count,
                       CASE WHEN dp_user.user_id IS NOT NULL THEN true ELSE false END as user_participating
                FROM duels d
                LEFT JOIN users u ON d.creator_id = u.id
                LEFT JOIN duel_participants dp ON d.id = dp.duel_id AND dp.status = 'accepted'
                LEFT JOIN duel_participants dp_user ON d.id = dp_user.duel_id AND dp_user.user_id = %s
                WHERE 1=1
            '''
            params = [user_id]
            
            # Add filters
            if is_public:
                query += ' AND d.is_public = true'
            else:
                query += ' AND (d.creator_id = %s OR dp_user.user_id IS NOT NULL)'
                params.append(user_id)
            
            if status:
                query += ' AND d.status = %s'
                params.append(status)
            
            if challenge_type:
                query += ' AND d.challenge_type = %s'
                params.append(challenge_type)
            
            query += '''
                GROUP BY d.id, u.username, dp_user.user_id
                ORDER BY d.created_at DESC
                LIMIT %s OFFSET %s
            '''
            params.extend([per_page, (page - 1) * per_page])
            
            cursor = db.connection.cursor()
            cursor.execute(query, params)
            duels = cursor.fetchall()
            
            # Get participants for each duel
            result = []
            for duel in duels:
                # Get participants
                cursor.execute('''
                    SELECT dp.*, u.username, u.email
                    FROM duel_participants dp
                    LEFT JOIN users u ON dp.user_id = u.id
                    WHERE dp.duel_id = %s
                    ORDER BY dp.current_value DESC
                ''', [duel['id']])
                participants = cursor.fetchall()
                
                duel_data = dict(duel)
                duel_data['participants'] = [dict(p) for p in participants]
                result.append(duel_data)
            
            cursor.close()
            
            return {
                'duels': result,
                'page': page,
                'per_page': per_page,
                'total': len(result)
            }
            
        except Exception as e:
            return {'error': str(e)}, 500

    @auth_required
    def post(self):
        """Create a new duel"""
        try:
            schema = DuelCreateSchema()
            data = schema.load(request.get_json())
            user_id = g.current_user['id']
            
            # Get user's city and state for duel location
            cursor = db.connection.cursor()
            cursor.execute('SELECT city, state FROM users WHERE id = %s', [user_id])
            user_info = cursor.fetchone()
            
            if not user_info or not user_info['city'] or not user_info['state']:
                return {'error': 'User must have city and state set to create duels'}, 400
            
            # Create duel
            duel_id = str(uuid.uuid4())
            now = datetime.utcnow()
            
            cursor.execute('''
                INSERT INTO duels (
                    id, creator_id, title, challenge_type, target_value, 
                    timeframe_hours, creator_city, creator_state, is_public, 
                    status, max_participants, created_at, updated_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ''', [
                duel_id, user_id, data['title'], data['challenge_type'],
                data['target_value'], data['timeframe_hours'], user_info['city'],
                user_info['state'], data['is_public'], 'pending', 
                data['max_participants'], now, now
            ])
            
            # Add creator as participant
            participant_id = str(uuid.uuid4())
            cursor.execute('''
                INSERT INTO duel_participants (
                    id, duel_id, user_id, status, joined_at, created_at, updated_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            ''', [participant_id, duel_id, user_id, 'accepted', now, now, now])
            
            # Send invitations for private duels
            if not data['is_public'] and data['invitee_emails']:
                for email in data['invitee_emails']:
                    invitation_id = str(uuid.uuid4())
                    expires_at = now + timedelta(days=7)  # 7 day expiry
                    
                    cursor.execute('''
                        INSERT INTO duel_invitations (
                            id, duel_id, inviter_id, invitee_email, 
                            expires_at, created_at, updated_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                    ''', [invitation_id, duel_id, user_id, email, expires_at, now, now])
            
            # Update user stats
            cursor.execute('''
                INSERT INTO user_duel_stats (user_id, duels_created, created_at, updated_at)
                VALUES (%s, 1, %s, %s)
                ON CONFLICT (user_id) 
                DO UPDATE SET 
                    duels_created = user_duel_stats.duels_created + 1,
                    updated_at = %s
            ''', [user_id, now, now, now])
            
            db.connection.commit()
            cursor.close()
            
            return {'message': 'Duel created successfully', 'duel_id': duel_id}, 201
            
        except ValidationError as e:
            return {'error': str(e)}, 400
        except Exception as e:
            db.connection.rollback()
            return {'error': str(e)}, 500


class DuelResource(Resource):
    @auth_required
    def get(self, duel_id):
        """Get duel details"""
        try:
            cursor = db.connection.cursor()
            
            # Get duel with creator info
            cursor.execute('''
                SELECT d.*, u.username as creator_username
                FROM duels d
                LEFT JOIN users u ON d.creator_id = u.id
                WHERE d.id = %s
            ''', [duel_id])
            duel = cursor.fetchone()
            
            if not duel:
                return {'error': 'Duel not found'}, 404
            
            # Get participants with user info and progress
            cursor.execute('''
                SELECT dp.*, u.username, u.email
                FROM duel_participants dp
                LEFT JOIN users u ON dp.user_id = u.id
                WHERE dp.duel_id = %s
                ORDER BY dp.current_value DESC, dp.joined_at ASC
            ''', [duel_id])
            participants = cursor.fetchall()
            
            cursor.close()
            
            result = dict(duel)
            result['participants'] = [dict(p) for p in participants]
            
            return result
            
        except Exception as e:
            return {'error': str(e)}, 500

    @auth_required
    def put(self, duel_id):
        """Update duel (status changes)"""
        try:
            schema = DuelUpdateSchema()
            data = schema.load(request.get_json())
            user_id = g.current_user['id']
            
            cursor = db.connection.cursor()
            
            # Check if user is creator
            cursor.execute('SELECT creator_id FROM duels WHERE id = %s', [duel_id])
            duel = cursor.fetchone()
            
            if not duel:
                return {'error': 'Duel not found'}, 404
            
            if duel['creator_id'] != user_id:
                return {'error': 'Only duel creator can update duel'}, 403
            
            # Update duel
            cursor.execute('''
                UPDATE duels 
                SET status = %s, updated_at = %s
                WHERE id = %s
            ''', [data['status'], datetime.utcnow(), duel_id])
            
            db.connection.commit()
            cursor.close()
            
            return {'message': 'Duel updated successfully'}
            
        except ValidationError as e:
            return {'error': str(e)}, 400
        except Exception as e:
            db.connection.rollback()
            return {'error': str(e)}, 500


class DuelJoinResource(Resource):
    @auth_required
    def post(self, duel_id):
        """Join a public duel"""
        try:
            user_id = g.current_user['id']
            cursor = db.connection.cursor()
            
            # Check duel exists and is public
            cursor.execute('''
                SELECT id, is_public, status, max_participants, creator_id
                FROM duels WHERE id = %s
            ''', [duel_id])
            duel = cursor.fetchone()
            
            if not duel:
                return {'error': 'Duel not found'}, 404
            
            if not duel['is_public']:
                return {'error': 'Cannot join private duel without invitation'}, 403
            
            if duel['status'] != 'pending':
                return {'error': 'Cannot join duel that is not pending'}, 400
            
            if duel['creator_id'] == user_id:
                return {'error': 'Cannot join your own duel'}, 400
            
            # Check if user already participating
            cursor.execute('''
                SELECT id FROM duel_participants 
                WHERE duel_id = %s AND user_id = %s
            ''', [duel_id, user_id])
            
            if cursor.fetchone():
                return {'error': 'Already participating in this duel'}, 400
            
            # Check participant limit
            cursor.execute('''
                SELECT COUNT(*) as count FROM duel_participants 
                WHERE duel_id = %s AND status = 'accepted'
            ''', [duel_id])
            participant_count = cursor.fetchone()['count']
            
            if participant_count >= duel['max_participants']:
                return {'error': 'Duel is full'}, 400
            
            # Add participant
            participant_id = str(uuid.uuid4())
            now = datetime.utcnow()
            
            cursor.execute('''
                INSERT INTO duel_participants (
                    id, duel_id, user_id, status, joined_at, created_at, updated_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            ''', [participant_id, duel_id, user_id, 'accepted', now, now, now])
            
            # Update user stats
            cursor.execute('''
                INSERT INTO user_duel_stats (user_id, duels_joined, created_at, updated_at)
                VALUES (%s, 1, %s, %s)
                ON CONFLICT (user_id) 
                DO UPDATE SET 
                    duels_joined = user_duel_stats.duels_joined + 1,
                    updated_at = %s
            ''', [user_id, now, now, now])
            
            # Check if duel should become active
            cursor.execute('''
                SELECT COUNT(*) as count FROM duel_participants 
                WHERE duel_id = %s AND status = 'accepted'
            ''', [duel_id])
            
            if cursor.fetchone()['count'] >= 2:
                # Activate duel
                starts_at = now
                cursor.execute('SELECT timeframe_hours FROM duels WHERE id = %s', [duel_id])
                timeframe = cursor.fetchone()['timeframe_hours']
                ends_at = starts_at + timedelta(hours=timeframe)
                
                cursor.execute('''
                    UPDATE duels 
                    SET status = 'active', starts_at = %s, ends_at = %s, updated_at = %s
                    WHERE id = %s
                ''', [starts_at, ends_at, now, duel_id])
            
            db.connection.commit()
            cursor.close()
            
            return {'message': 'Successfully joined duel'}
            
        except Exception as e:
            db.connection.rollback()
            return {'error': str(e)}, 500


class DuelParticipantResource(Resource):
    @auth_required
    def put(self, duel_id, participant_id):
        """Update participant status (accept/decline invitation)"""
        try:
            schema = DuelParticipantSchema()
            data = schema.load(request.get_json())
            user_id = g.current_user['id']
            
            cursor = db.connection.cursor()
            
            # Check if user owns this participant record
            cursor.execute('''
                SELECT user_id FROM duel_participants 
                WHERE id = %s AND duel_id = %s
            ''', [participant_id, duel_id])
            participant = cursor.fetchone()
            
            if not participant:
                return {'error': 'Participant not found'}, 404
            
            if participant['user_id'] != user_id:
                return {'error': 'Can only update your own participation'}, 403
            
            # Update participant status
            cursor.execute('''
                UPDATE duel_participants 
                SET status = %s, updated_at = %s
                WHERE id = %s
            ''', [data['status'], datetime.utcnow(), participant_id])
            
            db.connection.commit()
            cursor.close()
            
            return {'message': 'Participation status updated'}
            
        except ValidationError as e:
            return {'error': str(e)}, 400
        except Exception as e:
            db.connection.rollback()
            return {'error': str(e)}, 500
