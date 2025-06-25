from flask import request, g
from flask_restful import Resource
from marshmallow import Schema, fields, ValidationError, validates_schema
from datetime import datetime, timedelta, timezone
import uuid
from RuckTracker.supabase_client import get_supabase_client, get_supabase_admin_client
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
    start_mode = fields.Str(missing='auto', validate=lambda x: x in ['auto', 'manual'])
    min_participants = fields.Int(missing=2, validate=lambda x: 2 <= x <= 20)

    @validates_schema
    def validate_schema(self, data, **kwargs):
        if not data.get('is_public', True) and not data.get('invitee_emails', []):
            raise ValidationError('Private duels must include invitee emails')

class DuelUpdateSchema(Schema):
    status = fields.Str(validate=lambda x: x in ['active', 'cancelled', 'start'])
    # 'start' is a special value used only for manually starting a duel

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
            status = request.args.get('status')
            challenge_type = request.args.get('challenge_type')
            is_public = request.args.get('is_public', 'true').lower() == 'true'
            user_participating = request.args.get('user_participating')
            page = int(request.args.get('page', 1))
            per_page = min(int(request.args.get('per_page', 20)), 100)
            
            logging.info(f"DuelList.get filters: status={status}, is_public={is_public}, challenge_type={challenge_type}, user_participating={user_participating}, user_id={user_id}")
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            if user_participating == 'true':
                # My Duels - get duels where user is participating or created
                # First get all duel_ids where user is a participant
                participant_duels_response = supabase.table('duel_participants').select('duel_id').eq('user_id', user_id).execute()
                participant_duel_ids = [p['duel_id'] for p in participant_duels_response.data]
                
                # Get duels where user is creator OR participant
                if participant_duel_ids:
                    # Create OR condition for participant duels and creator duels
                    duel_ids_str = ','.join(participant_duel_ids)
                    query = supabase.table('duels').select('*').or_(f'creator_id.eq.{user_id},id.in.({duel_ids_str})')
                else:
                    # Only get duels where user is creator
                    query = supabase.table('duels').select('*').eq('creator_id', user_id)
                    
            elif user_participating == 'false':
                # Discover - get public duels where user is NOT participating
                # First get all duel_ids where user is already participating
                participant_duels_response = supabase.table('duel_participants').select('duel_id').eq('user_id', user_id).execute()
                participant_duel_ids = [p['duel_id'] for p in participant_duels_response.data]
                
                # Get public duels where user is not creator and not participant
                query = supabase.table('duels').select('*').eq('is_public', True).neq('creator_id', user_id)
                
                if participant_duel_ids:
                    duel_ids_str = ','.join(participant_duel_ids)
                    query = query.not_.in_('id', participant_duel_ids)
                    
            else:
                # Default behavior - get public duels or user's duels
                query = supabase.table('duels').select('*')
                if is_public:
                    query = query.eq('is_public', True)
                else:
                    query = query.or_(f'creator_id.eq.{user_id}')
            
            # Add additional filters
            # Always exclude cancelled duels unless explicitly requested
            if status != 'cancelled':
                query = query.neq('status', 'cancelled')
            
            if status:
                query = query.eq('status', status)
                logging.info(f"Applied status filter: {status}")
            
            if challenge_type:
                query = query.eq('challenge_type', challenge_type)
                logging.info(f"Applied challenge_type filter: {challenge_type}")
            
            query = query.range((page - 1) * per_page, page * per_page - 1).order('created_at', desc=True)
            
            duels_response = query.execute()
            logging.info(f"Found {len(duels_response.data)} duels after filtering")
            
            # Get participants for each duel and enrich with creator info
            result = []
            for duel in duels_response.data:
                # Get creator username
                creator_query = supabase.table('user').select('username').eq('id', duel['creator_id'])
                creator_response = creator_query.execute()
                creator_username = creator_response.data[0]['username'] if creator_response.data else 'Unknown'
                
                # Get participants for this duel (exclude withdrawn)
                participants_query = supabase.table('duel_participants').select('*').eq('duel_id', duel['id']).neq('status', 'withdrawn').order('current_value', desc=True)
                participants_response = participants_query.execute()
                
                # Enrich participants with user info (username, email, avatar_url)
                enriched_participants = []
                for participant in participants_response.data:
                    user_query = supabase.table('user').select('username, email, avatar_url').eq('id', participant['user_id'])
                    user_response = user_query.execute()
                    if user_response.data:
                        participant_data = dict(participant)
                        user_data = user_response.data[0]
                        participant_data['username'] = user_data['username']
                        participant_data['email'] = user_data['email']
                        participant_data['avatar_url'] = user_data.get('avatar_url')
                        
                        # Set role based on whether this participant is the creator
                        if participant['user_id'] == duel['creator_id']:
                            participant_data['role'] = 'Creator'
                        else:
                            participant_data['role'] = 'Participant'
                        
                        enriched_participants.append(participant_data)
                    else:
                        # Fallback if user not found
                        participant_data = dict(participant)
                        participant_data['username'] = 'Unknown User'
                        participant_data['email'] = None
                        participant_data['avatar_url'] = None
                        
                        # Set role based on whether this participant is the creator
                        if participant['user_id'] == duel['creator_id']:
                            participant_data['role'] = 'Creator'
                        else:
                            participant_data['role'] = 'Participant'
                        
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
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            supabase.table('duels').insert({
                'id': duel_id,
                'creator_id': user_id,
                'title': data['title'],
                'challenge_type': data['challenge_type'],
                'target_value': data['target_value'],
                'timeframe_hours': data['timeframe_hours'],
                'creator_city': 'Unknown',  # Default value since user table doesn't have city
                'creator_state': 'Unknown',  # Default value since user table doesn't have state
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
            
            # Update user stats (optional - don't fail duel creation if this fails)
            try:
                supabase_admin = get_supabase_admin_client()
                now = datetime.utcnow()
                # First try to get existing stats
                existing_stats = supabase_admin.table('user_duel_stats').select('duels_created').eq('user_id', user_id).execute()
                
                if existing_stats.data:
                    # Update existing record
                    current_created = existing_stats.data[0].get('duels_created', 0)
                    supabase_admin.table('user_duel_stats').update({
                        'duels_created': current_created + 1,
                        'updated_at': now.isoformat()
                    }).eq('user_id', user_id).execute()
                else:
                    # Insert new record
                    supabase_admin.table('user_duel_stats').insert({
                        'user_id': user_id,
                        'duels_created': 1,
                        'duels_joined': 0,
                        'created_at': now.isoformat(),
                        'updated_at': now.isoformat()
                    }).execute()
            except Exception as e:
                # Log the error but don't fail duel creation
                logging.warning(f"Failed to update user duel stats: {e}")
            
            # Get the created duel to return complete data
            created_duel = supabase.table('duels').select('*').eq('id', duel_id).execute()
            
            return {'message': 'Duel created successfully', 'duel': created_duel.data[0]}, 201
            
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
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Get duel with creator info
            duel_response = supabase.table('duels').select('*').eq('id', duel_id).execute()
            duel = duel_response.data[0] if duel_response.data else None
            
            if not duel:
                return {'error': 'Duel not found'}, 404
            
            # Get participants with user info and progress (exclude withdrawn)
            participants_response = supabase.table('duel_participants').select('*').eq('duel_id', duel_id).neq('status', 'withdrawn').order('current_value', desc=True).execute()
            participants = participants_response.data
            
            # Enrich participants with user info (username, email, avatar_url)
            enriched_participants = []
            for participant in participants:
                user_query = supabase.table('user').select('username, email, avatar_url').eq('id', participant['user_id'])
                user_response = user_query.execute()
                if user_response.data:
                    participant_data = dict(participant)
                    user_data = user_response.data[0]
                    participant_data['username'] = user_data['username']
                    participant_data['email'] = user_data['email']
                    participant_data['avatar_url'] = user_data.get('avatar_url')
                    
                    # Set role based on whether this participant is the creator
                    if participant['user_id'] == duel['creator_id']:
                        participant_data['role'] = 'Creator'
                    else:
                        participant_data['role'] = 'Participant'
                    
                    enriched_participants.append(participant_data)
                else:
                    # Fallback if user not found
                    participant_data = dict(participant)
                    participant_data['username'] = 'Unknown User'
                    participant_data['email'] = None
                    participant_data['avatar_url'] = None
                    
                    # Set role based on whether this participant is the creator
                    if participant['user_id'] == duel['creator_id']:
                        participant_data['role'] = 'Creator'
                    else:
                        participant_data['role'] = 'Participant'
                    
                    enriched_participants.append(participant_data)
            
            result = dict(duel)
            result['participants'] = enriched_participants
            
            return result
            
        except Exception as e:
            logging.error(f"Error in DuelResource.get: {str(e)}", exc_info=True)
            return {'error': str(e)}, 500

    @auth_required
    def put(self, duel_id):
        """Update duel (status changes or manual start)"""
        try:
            schema = DuelUpdateSchema()
            data = schema.load(request.get_json())
            user_id = g.user.id
            now = datetime.utcnow()
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Check if user is the creator
            duel_response = supabase.table('duels').select('creator_id,status,timeframe_hours,start_mode').eq('id', duel_id).execute()
            duel = duel_response.data[0] if duel_response.data else None
            
            if not duel:
                return {'error': 'Duel not found'}, 404
            
            if duel['creator_id'] != user_id:
                return {'error': 'Only the creator can update this duel'}, 403
            
            if duel['status'] == 'completed':
                return {'error': 'Cannot update a completed duel'}, 400
                
            # Special handling for manual start
            if data['status'] == 'start' and duel['status'] == 'pending':
                # Allow manual start for both auto and manual mode duels
                # (Auto mode might not have triggered due to timing/permission issues)
                    
                # Count accepted participants
                participant_count_response = supabase.table('duel_participants')\
                    .select('id', count='exact')\
                    .eq('duel_id', duel_id)\
                    .eq('status', 'accepted')\
                    .execute()
                participant_count = participant_count_response.count
                
                # Make sure there are at least 2 participants
                if participant_count < 2:
                    return {'error': 'At least 2 accepted participants are required to start a duel'}, 400
                    
                # Calculate start and end times
                starts_at = now
                timeframe = duel['timeframe_hours']
                ends_at = starts_at + timedelta(hours=timeframe)
                
                # Update the duel to active status
                updates = {
                    'status': 'active',
                    'starts_at': starts_at.isoformat(),
                    'ends_at': ends_at.isoformat(),
                    'updated_at': now.isoformat()
                }
                
                supabase.table('duels').update(updates).eq('id', duel_id).execute()
                
                return {'message': 'Duel has been started successfully'}
            
            # Normal status updates (e.g., cancelled)
            updates = {
                'status': data['status'],
                'updated_at': now.isoformat()
            }
            
            supabase.table('duels').update(updates).eq('id', duel_id).execute()
            
            return {'message': f"Duel status updated to {data['status']}"}
            
        except ValidationError as e:
            return {'error': str(e)}, 400
        except Exception as e:
            logging.error(f"Error in DuelResource.put: {str(e)}", exc_info=True)
            return {'error': str(e)}, 500

    @auth_required
    def delete(self, duel_id):
        """Delete a duel (creator only, and only if it hasn't started)"""
        try:
            user_id = g.user.id
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # First check if the duel exists and get its details
            duel_response = supabase.table('duels').select('creator_id, status').eq('id', duel_id).execute()
            
            if not duel_response.data:
                return {'error': 'Duel not found'}, 404
                
            duel = duel_response.data[0]
            
            # Check if the current user is the creator
            if duel['creator_id'] != user_id:
                return {'error': 'Only the duel creator can delete this duel'}, 403
            
            # Check if the duel hasn't started yet
            if duel['status'] != 'pending':
                return {'error': 'Cannot delete a duel that has already started'}, 400
            
            # Soft delete the duel by updating status to cancelled
            supabase.table('duels').update({
                'status': 'cancelled',
                'updated_at': datetime.utcnow().isoformat()
            }).eq('id', duel_id).execute()
            
            # Notification handled by database trigger
            # from api.duel_comments import create_duel_deleted_notification
            # create_duel_deleted_notification(duel_id, user_id)
            
            return {'message': 'Duel deleted successfully'}
            
        except Exception as e:
            logging.error(f"Error in DuelResource.delete: {str(e)}", exc_info=True)
            return {'error': str(e)}, 500


class DuelJoinResource(Resource):
    @auth_required
    def post(self, duel_id):
        """Join a public duel"""
        try:
            user_id = g.user.id
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
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
            
            # Get user name for notification
            user_response = supabase.table('user').select('username').eq('id', user_id).single().execute()
            user_name = user_response.data.get('username', 'Unknown User') if user_response.data else 'Unknown User'
            
            # Notification handled by database trigger
            # from api.duel_comments import create_duel_joined_notification
            # create_duel_joined_notification(duel_id, user_id, user_name)
            
            # Update user stats (optional - don't fail duel join if this fails)
            try:
                supabase_admin = get_supabase_admin_client()
                now = datetime.utcnow()
                # First try to get existing stats
                existing_stats = supabase_admin.table('user_duel_stats').select('duels_joined').eq('user_id', user_id).execute()
                
                if existing_stats.data:
                    # Update existing record
                    current_joined = existing_stats.data[0].get('duels_joined', 0)
                    supabase_admin.table('user_duel_stats').update({
                        'duels_joined': current_joined + 1,
                        'updated_at': now.isoformat()
                    }).eq('user_id', user_id).execute()
                else:
                    # Insert new record
                    supabase_admin.table('user_duel_stats').insert({
                        'user_id': user_id,
                        'duels_created': 0,
                        'duels_joined': 1,
                        'created_at': now.isoformat(),
                        'updated_at': now.isoformat()
                    }).execute()
            except Exception as e:
                # Log the error but don't fail duel join
                logging.warning(f"Failed to update user duel join stats: {e}")
            
            # Check if duel should become active based on start_mode
            participant_count_response = supabase.table('duel_participants').select('id', count='exact').eq('duel_id', duel_id).eq('status', 'accepted').execute()
            participant_count = participant_count_response.count
            
            logging.info(f"Auto-start check - duel_id: {duel_id}, participant_count: {participant_count}")
            
            # Get duel configuration
            duel_config = supabase.table('duels').select('start_mode', 'min_participants', 'timeframe_hours').eq('id', duel_id).execute()
            
            if not duel_config.data:
                return {'error': 'Duel not found'}, 404
                
            # Extract duel settings
            duel_settings = duel_config.data[0]
            start_mode = duel_settings.get('start_mode', 'auto')
            min_participants = duel_settings.get('min_participants', 2)
            timeframe = duel_settings.get('timeframe_hours')
            
            logging.info(f"Duel settings - start_mode: {start_mode}, min_participants: {min_participants}, timeframe: {timeframe}")
            
            # Only auto-start the duel if:
            # 1. Start mode is auto AND
            # 2. We have at least the minimum required participants
            if start_mode == 'auto' and participant_count >= min_participants:
                logging.info(f"AUTO-START TRIGGERED! Starting duel {duel_id}")
                # Activate duel
                starts_at = now
                ends_at = starts_at + timedelta(hours=timeframe)
                
                supabase.table('duels').update({
                    'status': 'active', 
                    'starts_at': starts_at.isoformat(), 
                    'ends_at': ends_at.isoformat(), 
                    'updated_at': now.isoformat()
                }).eq('id', duel_id).execute()
                
                # Create duel started notifications for all participants
                from api.duel_comments import create_duel_started_notification
                create_duel_started_notification(duel_id)
            
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
            
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
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


class DuelWithdrawResource(Resource):
    @auth_required
    def post(self, duel_id):
        """Withdraw from a duel"""
        try:
            user_id = g.user.id
            supabase = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            
            # Find the user's participation in this duel
            participant_response = supabase.table('duel_participants').select('id, status').eq('duel_id', duel_id).eq('user_id', user_id).execute()
            
            if not participant_response.data:
                return {'error': 'You are not participating in this duel'}, 404
            
            participant = participant_response.data[0]
            
            # Check if user is in a state where they can withdraw
            if participant['status'] not in ['accepted', 'pending']:
                return {'error': 'Cannot withdraw from duel in current status'}, 400
            
            # Update participant status to withdrawn
            supabase.table('duel_participants').update({
                'status': 'withdrawn',
                'updated_at': datetime.utcnow().isoformat()
            }).eq('id', participant['id']).execute()
            
            return {'message': 'Successfully withdrew from duel'}
            
        except Exception as e:
            logging.error(f"Error in DuelWithdrawResource.post: {str(e)}", exc_info=True)
            return {'error': str(e)}, 500


class DuelCompletionCheckResource(Resource):
    def post(self):
        """Check and complete expired duels - for system use (no auth required)"""
        try:
            from datetime import timezone
            now = datetime.now(timezone.utc)
            supabase = get_supabase_admin_client()
            
            # Get all active duels that have expired
            expired_duels_response = supabase.table('duels').select('*').eq('status', 'active').lt('ends_at', now.isoformat()).execute()
            
            completed_duels = []
            
            for duel in expired_duels_response.data:
                try:
                    result = self._complete_expired_duel(duel, now, supabase)
                    completed_duels.append(result)
                except Exception as e:
                    logging.error(f"Error completing duel {duel['id']}: {str(e)}")
                    continue
            
            return {
                'message': f'Completed {len(completed_duels)} expired duels',
                'completed_duels': completed_duels
            }
            
        except Exception as e:
            logging.error(f"Error in DuelCompletionCheckResource.post: {str(e)}", exc_info=True)
            return {'error': str(e)}, 500
    
    def _complete_expired_duel(self, duel, now, supabase):
        """Complete a single expired duel and determine winner"""
        duel_id = duel['id']
        
        # Get all active participants with their progress
        participants_response = supabase.table('duel_participants').select('*').eq('duel_id', duel_id).eq('status', 'accepted').order('current_value', desc=True).execute()
        
        participants = participants_response.data
        
        if not participants:
            # No participants, just mark as completed
            supabase.table('duels').update({
                'status': 'completed',
                'completed_at': now.isoformat(),
                'updated_at': now.isoformat()
            }).eq('id', duel_id).execute()
            
            return {
                'duel_id': duel_id,
                'title': duel['title'],
                'result': 'no_participants',
                'winner_id': None
            }
        
        # Check if anyone made progress
        max_value = max((p['current_value'] for p in participants), default=0)
        
        if max_value == 0:
            # No one made any progress
            supabase.table('duels').update({
                'status': 'completed',
                'completed_at': now.isoformat(),
                'updated_at': now.isoformat()
            }).eq('id', duel_id).execute()
            
            # Send no-winner notification
            from api.duel_comments import create_duel_completed_notification
            create_duel_completed_notification(duel_id)
            
            return {
                'duel_id': duel_id,
                'title': duel['title'],
                'result': 'no_progress',
                'winner_id': None
            }
        
        # Find participants with highest progress
        winners = [p for p in participants if p['current_value'] == max_value]
        
        if len(winners) == 1:
            # Clear winner
            winner = winners[0]
            winner_id = winner['user_id']
            
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
            
            # Send completion notification
            from api.duel_comments import create_duel_completed_notification
            create_duel_completed_notification(duel_id)
            
            return {
                'duel_id': duel_id,
                'title': duel['title'],
                'result': 'winner',
                'winner_id': winner_id
            }
        else:
            # Tie between multiple participants
            supabase.table('duels').update({
                'status': 'completed',
                'completed_at': now.isoformat(),
                'updated_at': now.isoformat()
            }).eq('id', duel_id).execute()
            
            # Send completion notification
            from api.duel_comments import create_duel_completed_notification
            create_duel_completed_notification(duel_id)
            
            return {
                'duel_id': duel_id,
                'title': duel['title'],
                'result': 'tie',
                'winner_id': None,
                'tied_participants': len(winners)
            }
