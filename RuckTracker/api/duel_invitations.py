from flask import request, g
from flask_restful import Resource
from marshmallow import Schema, fields, ValidationError
from datetime import datetime, timedelta
import uuid
from RuckTracker.supabase_client import get_supabase_client
from api.auth import auth_required

# ============================================================================
# SCHEMAS
# ============================================================================

class InvitationResponseSchema(Schema):
    action = fields.Str(required=True, validate=lambda x: x in ['accept', 'decline'])

# ============================================================================
# RESOURCES
# ============================================================================

class DuelInvitationListResource(Resource):
    @auth_required
    def get(self):
        """Get user's duel invitations"""
        try:
            user_email = g.user.email
            status = request.args.get('status', 'pending')
            
            supabase = get_supabase_client()
            
            # Get invitations for user's email
            invitations_response = supabase.table('duel_invitations').select('*, duel_id(title, challenge_type, target_value, timeframe_hours, creator_city, creator_state), inviter_id(username)').eq('invitee_email', user_email).eq('status', status).order('created_at', desc=True).execute()
            
            return {
                'invitations': invitations_response.data
            }
            
        except Exception as e:
            return {'error': str(e)}, 500


class DuelInvitationResource(Resource):
    @auth_required
    def put(self, invitation_id):
        """Respond to a duel invitation (accept/decline)"""
        try:
            schema = InvitationResponseSchema()
            data = schema.load(request.get_json())
            user_id = g.user.id
            user_email = g.user.email
            
            supabase = get_supabase_client()
            
            # Get invitation details
            invitation_response = supabase.table('duel_invitations').select('*, duel_id(id, status as duel_status, max_participants, creator_id)').eq('id', invitation_id).eq('invitee_email', user_email).eq('status', 'pending').execute()
            invitation = invitation_response.data[0]
            if not invitation:
                return {'error': 'Invitation not found or already responded'}, 404
            
            # Check if invitation has expired
            if invitation['expires_at'] and datetime.utcnow() > invitation['expires_at']:
                supabase.table('duel_invitations').update({'status': 'expired', 'updated_at': datetime.utcnow()}).eq('id', invitation_id).execute()
                return {'error': 'Invitation has expired'}, 400
            
            # Check if duel is still pending
            if invitation['duel_status'] != 'pending':
                return {'error': 'Duel is no longer accepting participants'}, 400
            
            # Update invitation status
            now = datetime.utcnow()
            supabase.table('duel_invitations').update({'status': data['action'] + 'ed', 'updated_at': now}).eq('id', invitation_id).execute()
            
            if data['action'] == 'accept':
                # Check if user is already participating
                participant_response = supabase.table('duel_participants').select('id').eq('duel_id', invitation['duel_id']).eq('user_id', user_id).execute()
                participant = participant_response.data
                if participant:
                    return {'error': 'Already participating in this duel'}, 400
                
                # Check participant limit
                participant_count_response = supabase.table('duel_participants').select('id').eq('duel_id', invitation['duel_id']).eq('status', 'accepted').execute()
                participant_count = len(participant_count_response.data)
                if participant_count >= invitation['max_participants']:
                    return {'error': 'Duel is already full'}, 400
                
                # Add user as participant
                participant_id = str(uuid.uuid4())
                supabase.table('duel_participants').insert([{'id': participant_id, 'duel_id': invitation['duel_id'], 'user_id': user_id, 'status': 'accepted', 'joined_at': now, 'created_at': now, 'updated_at': now}]).execute()
                
                # Update user stats
                supabase.table('user_duel_stats').upsert([{'user_id': user_id, 'duels_joined': 1, 'created_at': now, 'updated_at': now}], ['user_id']).execute()
                
                # Check if duel should become active (has 2+ participants)
                total_participants_response = supabase.table('duel_participants').select('id').eq('duel_id', invitation['duel_id']).eq('status', 'accepted').execute()
                total_participants = len(total_participants_response.data)
                if total_participants >= 2:
                    # Activate duel
                    timeframe_response = supabase.table('duels').select('timeframe_hours').eq('id', invitation['duel_id']).execute()
                    timeframe = timeframe_response.data[0]['timeframe_hours']
                    starts_at = now
                    ends_at = starts_at + timedelta(hours=timeframe)
                    
                    supabase.table('duels').update({'status': 'active', 'starts_at': starts_at, 'ends_at': ends_at, 'updated_at': now}).eq('id', invitation['duel_id']).execute()
            
            return {'message': f'Invitation {data["action"]}ed successfully'}
            
        except ValidationError as e:
            return {'error': str(e)}, 400
        except Exception as e:
            return {'error': str(e)}, 500

    @auth_required
    def delete(self, invitation_id):
        """Cancel a sent invitation (inviter only)"""
        try:
            user_id = g.user.id
            supabase = get_supabase_client()
            
            # Check if user sent this invitation
            invitation_response = supabase.table('duel_invitations').select('inviter_id, status').eq('id', invitation_id).execute()
            invitation = invitation_response.data[0]
            if not invitation:
                return {'error': 'Invitation not found'}, 404
            
            if invitation['inviter_id'] != user_id:
                return {'error': 'Can only cancel invitations you sent'}, 403
            
            if invitation['status'] != 'pending':
                return {'error': 'Can only cancel pending invitations'}, 400
            
            # Update invitation to cancelled
            supabase.table('duel_invitations').update({'status': 'cancelled', 'updated_at': datetime.utcnow()}).eq('id', invitation_id).execute()
            
            return {'message': 'Invitation cancelled successfully'}
            
        except Exception as e:
            return {'error': str(e)}, 500


class SentInvitationsResource(Resource):
    @auth_required
    def get(self):
        """Get invitations sent by current user"""
        try:
            user_id = g.user.id
            supabase = get_supabase_client()
            
            invitations_response = supabase.table('duel_invitations').select('*, duel_id(title, challenge_type, target_value)').eq('inviter_id', user_id).order('created_at', desc=True).execute()
            
            return {
                'sent_invitations': invitations_response.data
            }
            
        except Exception as e:
            return {'error': str(e)}, 500
