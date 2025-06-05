from flask import request, g
from flask_restful import Resource
from marshmallow import Schema, fields, ValidationError, validates_schema
from datetime import datetime, timedelta
import uuid
from RuckTracker.supabase_client import get_supabase_client
from api.auth import auth_required
import logging

# ============================================================================
# SCHEMAS
# ============================================================================

class DuelCreateSchema(Schema):
    title = fields.Str(required=True, validate=lambda x: 1 <= len(x) <= 50)
    challenge_type = fields.Str(required=True, validate=lambda x: x in ['distance', 'time', 'elevation', 'power_points'])
    target_value = fields.Float(required=True, validate=lambda x: x > 0)
    timeframe_hours = fields.Int(required=True, validate=lambda x: 1 <= x <= 720)  # 1 hour to 30 days
    is_public = fields.Bool(missing=True)
    max_participants = fields.Int(missing=2, validate=lambda x: 2 <= x <= 20)
    invitee_emails = fields.List(fields.Email(), missing=[])
    description = fields.Str(missing=None, allow_none=True)

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
            user_id = g.user.id
            
            # Query parameters
            status = request.args.get('status', 'active')
            challenge_type = request.args.get('challenge_type')
            is_public = request.args.get('is_public', 'true').lower() == 'true'
            page = int(request.args.get('page', 1))
            per_page = min(int(request.args.get('per_page', 20)), 100)
            
            supabase = get_supabase_client()
            
            # Base query for public duels or user's duels
            query = supabase.table('duels').select('*')
            
            # Add filters
            if is_public:
                query = query.eq('is_public', True)
            else:
                # For private duels, show duels where user is creator or participant
                query = query.or_(f'creator_id.eq.{user_id}')
            
            if status:
                query = query.eq('status', status)
            
            if challenge_type:
                query = query.eq('challenge_type', challenge_type)
            
            query = query.range((page - 1) * per_page, page * per_page - 1).order('created_at', desc=True)
            
            duels_response = query.execute()
            
            # Get participants for each duel and enrich with creator info
            result = []
            for duel in duels_response.data:
                # Get creator username
                creator_query = supabase.table('users').select('username').eq('id', duel['creator_id'])
                creator_response = creator_query.execute()
                creator_username = creator_response.data[0]['username'] if creator_response.data else 'Unknown'
                
                # Get participants for this duel
                participants_query = supabase.table('duel_participants').select('*').eq('duel_id', duel['id']).order('current_value', desc=True)
                participants_response = participants_query.execute()
                
                # Get user info for each participant
                enriched_participants = []
                for participant in participants_response.data:
                    user_query = supabase.table('users').select('username, email').eq('id', participant['user_id'])
                    user_response = user_query.execute()
                    if user_response.data:
                        participant_data = dict(participant)
                        participant_data['user_username'] = user_response.data[0]['username']
                        participant_data['user_email'] = user_response.data[0]['email']
                        enriched_participants.append(participant_data)
                
                duel_data = dict(duel)
                duel_data['creator_username'] = creator_username
                duel_data['participants'] = enriched_participants
                result.append(duel_data)
            
            return {
                'duels': result,
                'page': page,
                'per_page': per_page,
                'total': len(result)
            }
            
        except Exception as e:
            logging.error(f"Error in DuelList.get: {str(e)}", exc_info=True)
            return {'error': str(e)}, 500

    @auth_required
    def post(self):
        """Create a new duel"""
        try:
            schema = DuelCreateSchema()
            data = schema.load(request.get_json())
            user_id = g.user.id
            
            # Create duel
            duel_id = str(uuid.uuid4())
            now = datetime.utcnow()
            supabase = get_supabase_client()
            
            supabase.table('duels').insert({
                'id': duel_id,
                'creator_id': user_id,
                'title': data['title'],
                'challenge_type': data['challenge_type'],
                'target_value': data['target_value'],
                'timeframe_hours': data['timeframe_hours'],
                'is_public': data['is_public'],
                'status': 'pending',
                'max_participants': data['max_participants'],
                'created_at': now.isoformat(),
                'updated_at': now.isoformat()
            }).execute()
            
            # Add creator as participant
            participant_id = str(uuid.uuid4())
            supabase.table('duel_participants').insert({
                'id': participant_id,
                'duel_id': duel_id,
                'user_id': user_id,
                'status': 'accepted',
                'joined_at': now.isoformat(),
                'created_at': now.isoformat(),
                'updated_at': now.isoformat()
            }).execute()
            
            # Send invitations for private duels
            if not data['is_public'] and data['invitee_emails']:
                for email in data['invitee_emails']:
                    invitation_id = str(uuid.uuid4())
                    expires_at = now + timedelta(days=7)  # 7 day expiry
                    
                    supabase.table('duel_invitations').insert({
                        'id': invitation_id,
                        'duel_id': duel_id,
                        'inviter_id': user_id,
                        'invitee_email': email,
                        'expires_at': expires_at.isoformat(),
                        'created_at': now.isoformat(),
                        'updated_at': now.isoformat()
                    }).execute()
            
            # Update user stats
            supabase.table('user_duel_stats').upsert({
                'user_id': user_id,
                'duels_created': 1,
                'created_at': now.isoformat(),
                'updated_at': now.isoformat()
            }).execute()
            
            return {'message': 'Duel created successfully', 'duel_id': duel_id}, 201
            
        except ValidationError as e:
            return {'error': str(e)}, 400
        except Exception as e:
            logging.error(f"Error in DuelList.post: {str(e)}", exc_info=True)
            return {'error': str(e)}, 500


class DuelResource(Resource):
    @auth_required
    def get(self, duel_id):
        """Get duel details"""
        try:
            supabase = get_supabase_client()
            
            # Get duel with creator info
            duel_response = supabase.table('duels').select('*').eq('id', duel_id).execute()
            duel = duel_response.data[0] if duel_response.data else None
            
            if not duel:
                return {'error': 'Duel not found'}, 404
            
            # Get participants with user info and progress
            participants_response = supabase.table('duel_participants').select('*').eq('duel_id', duel_id).order('current_value', desc=True).execute()
            participants = participants_response.data
            
            result = dict(duel)
            result['participants'] = [dict(p) for p in participants]
            
            return result
            
        except Exception as e:
            logging.error(f"Error in DuelResource.get: {str(e)}", exc_info=True)
            return {'error': str(e)}, 500

    @auth_required
    def put(self, duel_id):
        """Update duel (status changes)"""
        try:
            schema = DuelUpdateSchema()
            data = schema.load(request.get_json())
            user_id = g.user.id
            
            supabase = get_supabase_client()
            
            # Check if user is creator
            duel_response = supabase.table('duels').select('creator_id').eq('id', duel_id).execute()
            duel = duel_response.data[0] if duel_response.data else None
            
            if not duel:
                return {'error': 'Duel not found'}, 404
            if duel['creator_id'] != user_id:
                return {'error': 'Only duel creator can update duel'}, 403
            
            # Update duel
            supabase.table('duels').update({
                'status': data['status'], 
                'updated_at': datetime.utcnow().isoformat()
            }).eq('id', duel_id).execute()
            
            return {'message': 'Duel updated successfully'}
            
        except ValidationError as e:
            return {'error': str(e)}, 400
        except Exception as e:
            logging.error(f"Error in DuelResource.put: {str(e)}", exc_info=True)
            return {'error': str(e)}, 500


class DuelJoinResource(Resource):
    @auth_required
    def post(self, duel_id):
        """Join a public duel"""
        try:
            user_id = g.user.id
            supabase = get_supabase_client()
            
            # Check duel exists and is public
            duel_response = supabase.table('duels').select('id, is_public, status, max_participants, creator_id').eq('id', duel_id).execute()
            duel = duel_response.data[0] if duel_response.data else None
            
            if not duel:
                return {'error': 'Duel not found'}, 404
            if not duel['is_public']:
                return {'error': 'Can only join public duels'}, 403
            if duel['status'] != 'pending':
                return {'error': 'Duel is not accepting participants'}, 400
            if duel['creator_id'] == user_id:
                return {'error': 'Cannot join your own duel'}, 400
            
            # Check if user already participating
            participant_response = supabase.table('duel_participants').select('id').eq('duel_id', duel_id).eq('user_id', user_id).execute()
            
            if participant_response.data:
                return {'error': 'Already participating in this duel'}, 400
            
            # Check participant limit
            participant_count_response = supabase.table('duel_participants').select('id', count='exact').eq('duel_id', duel_id).eq('status', 'accepted').execute()
            participant_count = participant_count_response.count
            
            if participant_count >= duel['max_participants']:
                return {'error': 'Duel is full'}, 400
            
            # Add participant
            participant_id = str(uuid.uuid4())
            now = datetime.utcnow()
            
            supabase.table('duel_participants').insert({
                'id': participant_id,
                'duel_id': duel_id,
                'user_id': user_id,
                'status': 'accepted',
                'joined_at': now.isoformat(),
                'created_at': now.isoformat(),
                'updated_at': now.isoformat()
            }).execute()
            
            # Update user stats
            supabase.table('user_duel_stats').upsert({
                'user_id': user_id,
                'duels_joined': 1,
                'created_at': now.isoformat(),
                'updated_at': now.isoformat()
            }).execute()
            
            # Check if duel should become active
            participant_count_response = supabase.table('duel_participants').select('id', count='exact').eq('duel_id', duel_id).eq('status', 'accepted').execute()
            participant_count = participant_count_response.count
            
            if participant_count >= 2:
                # Activate duel
                starts_at = now
                timeframe_response = supabase.table('duels').select('timeframe_hours').eq('id', duel_id).execute()
                timeframe = timeframe_response.data[0]['timeframe_hours']
                ends_at = starts_at + timedelta(hours=timeframe)
                
                supabase.table('duels').update({
                    'status': 'active', 
                    'starts_at': starts_at.isoformat(), 
                    'ends_at': ends_at.isoformat(), 
                    'updated_at': now.isoformat()
                }).eq('id', duel_id).execute()
            
            return {'message': 'Successfully joined duel'}
            
        except Exception as e:
            logging.error(f"Error in DuelJoinResource.post: {str(e)}", exc_info=True)
            return {'error': str(e)}, 500


class DuelParticipantResource(Resource):
    @auth_required
    def put(self, duel_id, participant_id):
        """Update participant status (accept/decline invitation)"""
        try:
            schema = DuelParticipantSchema()
            data = schema.load(request.get_json())
            user_id = g.user.id
            
            supabase = get_supabase_client()
            
            # Check if user owns this participant record
            participant_response = supabase.table('duel_participants').select('user_id').eq('id', participant_id).eq('duel_id', duel_id).execute()
            participant = participant_response.data[0] if participant_response.data else None
            
            if not participant:
                return {'error': 'Participant not found'}, 404
            
            if participant['user_id'] != user_id:
                return {'error': 'Can only update your own participation'}, 403
            
            # Update participant status
            supabase.table('duel_participants').update({
                'status': data['status'], 
                'updated_at': datetime.utcnow().isoformat()
            }).eq('id', participant_id).execute()
            
            return {'message': 'Participation status updated'}
            
        except ValidationError as e:
            return {'error': str(e)}, 400
        except Exception as e:
            logging.error(f"Error in DuelParticipantResource.put: {str(e)}", exc_info=True)
            return {'error': str(e)}, 500
