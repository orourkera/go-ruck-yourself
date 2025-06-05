from flask import request, g
from flask_restful import Resource
from marshmallow import Schema, fields, ValidationError
from datetime import datetime
import uuid
from extensions import db
from utils.auth import auth_required
from utils.error_handling import handle_validation_error, handle_not_found_error

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
            user_email = g.user['email']
            status = request.args.get('status', 'pending')
            
            cursor = db.connection.cursor()
            
            # Get invitations for user's email
            cursor.execute('''
                SELECT di.*, d.title, d.challenge_type, d.target_value, 
                       d.timeframe_hours, d.creator_city, d.creator_state,
                       u.username as inviter_username
                FROM duel_invitations di
                JOIN duels d ON di.duel_id = d.id
                JOIN users u ON di.inviter_id = u.id
                WHERE di.invitee_email = %s AND di.status = %s
                ORDER BY di.created_at DESC
            ''', [user_email, status])
            
            invitations = cursor.fetchall()
            cursor.close()
            
            return {
                'invitations': [dict(inv) for inv in invitations]
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
            user_id = g.user['id']
            user_email = g.user['email']
            
            cursor = db.connection.cursor()
            
            # Get invitation details
            cursor.execute('''
                SELECT di.*, d.id as duel_id, d.status as duel_status, 
                       d.max_participants, d.creator_id
                FROM duel_invitations di
                JOIN duels d ON di.duel_id = d.id
                WHERE di.id = %s AND di.invitee_email = %s AND di.status = 'pending'
            ''', [invitation_id, user_email])
            
            invitation = cursor.fetchone()
            if not invitation:
                return handle_not_found_error('Invitation not found or already responded')
            
            # Check if invitation has expired
            if invitation['expires_at'] and datetime.utcnow() > invitation['expires_at']:
                cursor.execute('''
                    UPDATE duel_invitations 
                    SET status = 'expired', updated_at = %s 
                    WHERE id = %s
                ''', [datetime.utcnow(), invitation_id])
                db.connection.commit()
                return {'error': 'Invitation has expired'}, 400
            
            # Check if duel is still pending
            if invitation['duel_status'] != 'pending':
                return {'error': 'Duel is no longer accepting participants'}, 400
            
            # Update invitation status
            now = datetime.utcnow()
            cursor.execute('''
                UPDATE duel_invitations 
                SET status = %s, updated_at = %s 
                WHERE id = %s
            ''', [data['action'] + 'ed', now, invitation_id])  # accepted/declined
            
            if data['action'] == 'accept':
                # Check if user is already participating
                cursor.execute('''
                    SELECT id FROM duel_participants 
                    WHERE duel_id = %s AND user_id = %s
                ''', [invitation['duel_id'], user_id])
                
                if cursor.fetchone():
                    db.connection.commit()
                    return {'error': 'Already participating in this duel'}, 400
                
                # Check participant limit
                cursor.execute('''
                    SELECT COUNT(*) as count FROM duel_participants 
                    WHERE duel_id = %s AND status = 'accepted'
                ''', [invitation['duel_id']])
                participant_count = cursor.fetchone()['count']
                
                if participant_count >= invitation['max_participants']:
                    db.connection.commit()
                    return {'error': 'Duel is already full'}, 400
                
                # Add user as participant
                participant_id = str(uuid.uuid4())
                cursor.execute('''
                    INSERT INTO duel_participants (
                        id, duel_id, user_id, status, joined_at, created_at, updated_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                ''', [participant_id, invitation['duel_id'], user_id, 'accepted', now, now, now])
                
                # Update user stats
                cursor.execute('''
                    INSERT INTO user_duel_stats (user_id, duels_joined, created_at, updated_at)
                    VALUES (%s, 1, %s, %s)
                    ON CONFLICT (user_id) 
                    DO UPDATE SET 
                        duels_joined = user_duel_stats.duels_joined + 1,
                        updated_at = %s
                ''', [user_id, now, now, now])
                
                # Check if duel should become active (has 2+ participants)
                cursor.execute('''
                    SELECT COUNT(*) as count FROM duel_participants 
                    WHERE duel_id = %s AND status = 'accepted'
                ''', [invitation['duel_id']])
                
                total_participants = cursor.fetchone()['count']
                if total_participants >= 2:
                    # Activate duel
                    cursor.execute('SELECT timeframe_hours FROM duels WHERE id = %s', [invitation['duel_id']])
                    timeframe = cursor.fetchone()['timeframe_hours']
                    starts_at = now
                    ends_at = starts_at + timedelta(hours=timeframe)
                    
                    cursor.execute('''
                        UPDATE duels 
                        SET status = 'active', starts_at = %s, ends_at = %s, updated_at = %s
                        WHERE id = %s
                    ''', [starts_at, ends_at, now, invitation['duel_id']])
            
            db.connection.commit()
            cursor.close()
            
            action_past = 'accepted' if data['action'] == 'accept' else 'declined'
            return {'message': f'Invitation {action_past} successfully'}
            
        except ValidationError as e:
            return handle_validation_error(e)
        except Exception as e:
            db.connection.rollback()
            return {'error': str(e)}, 500

    @auth_required
    def delete(self, invitation_id):
        """Cancel a sent invitation (inviter only)"""
        try:
            user_id = g.user['id']
            cursor = db.connection.cursor()
            
            # Check if user sent this invitation
            cursor.execute('''
                SELECT inviter_id, status FROM duel_invitations 
                WHERE id = %s
            ''', [invitation_id])
            
            invitation = cursor.fetchone()
            if not invitation:
                return handle_not_found_error('Invitation not found')
            
            if invitation['inviter_id'] != user_id:
                return {'error': 'Can only cancel invitations you sent'}, 403
            
            if invitation['status'] != 'pending':
                return {'error': 'Can only cancel pending invitations'}, 400
            
            # Update invitation to cancelled
            cursor.execute('''
                UPDATE duel_invitations 
                SET status = 'cancelled', updated_at = %s 
                WHERE id = %s
            ''', [datetime.utcnow(), invitation_id])
            
            db.connection.commit()
            cursor.close()
            
            return {'message': 'Invitation cancelled successfully'}
            
        except Exception as e:
            db.connection.rollback()
            return {'error': str(e)}, 500


class SentInvitationsResource(Resource):
    @auth_required
    def get(self):
        """Get invitations sent by current user"""
        try:
            user_id = g.user['id']
            cursor = db.connection.cursor()
            
            cursor.execute('''
                SELECT di.*, d.title, d.challenge_type, d.target_value
                FROM duel_invitations di
                JOIN duels d ON di.duel_id = d.id
                WHERE di.inviter_id = %s
                ORDER BY di.created_at DESC
            ''', [user_id])
            
            invitations = cursor.fetchall()
            cursor.close()
            
            return {
                'sent_invitations': [dict(inv) for inv in invitations]
            }
            
        except Exception as e:
            return {'error': str(e)}, 500

from datetime import timedelta
