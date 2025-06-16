"""
Clubs API endpoints for club management and membership
"""
import logging
from flask import Blueprint, request, g, jsonify
from flask_restful import Api, Resource
from RuckTracker.api.auth import auth_required, get_user_id
from datetime import datetime
from RuckTracker.supabase_client import get_supabase_admin_client, get_supabase_client
from RuckTracker.services.push_notification_service import PushNotificationService, get_user_device_tokens

logger = logging.getLogger(__name__)

clubs_bp = Blueprint('clubs', __name__)
api = Api(clubs_bp)

# Initialize push notification service
push_service = PushNotificationService()

class ClubListResource(Resource):
    """Handle club listing and creation"""
    
    @auth_required
    def get(self):
        """List clubs with optional search and filtering"""
        try:
            current_user_id = get_user_id()
            logger.info(f"Fetching clubs for user: {current_user_id}")
            
            # Use user client for RLS policy compliance
            user_client = get_supabase_client(user_jwt=getattr(g, 'access_token', None))
            logger.info("Got Supabase user client")
            
            # Get query parameters
            search = request.args.get('search', '')
            is_public = request.args.get('is_public')
            user_clubs_only = request.args.get('user_clubs_only', 'false').lower() == 'true'
            logger.info(f"Query params - search: {search}, is_public: {is_public}, user_clubs_only: {user_clubs_only}")
            
            # First, check if clubs table exists
            try:
                test_query = user_client.table('clubs').select('count', count='exact').limit(1).execute()
                logger.info(f"Clubs table test query successful. Count: {test_query.count}")
            except Exception as table_error:
                logger.error(f"Clubs table does not exist or is inaccessible: {table_error}")
                return {'error': 'Clubs table not found'}, 500
            
            # Base query - simplified to avoid complex joins
            query = user_client.table('clubs').select("""
                *,
                users!admin_user_id(id, first_name, last_name)
            """)
            logger.info("Created base query")
            
            # Apply filters
            if search:
                query = query.ilike('name', f'%{search}%')
                logger.info(f"Applied search filter: {search}")
            
            if is_public is not None:
                query = query.eq('is_public', is_public.lower() == 'true')
                logger.info(f"Applied public filter: {is_public}")
            
            if user_clubs_only:
                logger.info("Applying user clubs only filter")
                # Get user's clubs only
                user_memberships = user_client.table('club_memberships').select('club_id').eq('user_id', current_user_id).eq('status', 'approved').execute()
                if user_memberships.data:
                    club_ids = [membership['club_id'] for membership in user_memberships.data]
                    query = query.in_('id', club_ids)
                    logger.info(f"Found user memberships for {len(club_ids)} clubs")
                else:
                    logger.info("No user memberships found, returning empty list")
                    return {'clubs': [], 'total': 0}, 200
            
            # Execute query
            logger.info("Executing main clubs query")
            result = query.order('created_at', desc=True).execute()
            logger.info(f"Main query returned {len(result.data)} clubs")
            
            clubs = []
            for i, club in enumerate(result.data):
                logger.info(f"Processing club {i+1}/{len(result.data)}: {club.get('name', 'Unknown')}")
                
                # Get member count
                try:
                    member_count_result = user_client.table('club_memberships').select('id', count='exact').eq('club_id', club['id']).eq('status', 'approved').execute()
                    member_count = member_count_result.count
                    logger.info(f"Club {club['id']} has {member_count} members")
                except Exception as member_error:
                    logger.error(f"Error getting member count for club {club['id']}: {member_error}")
                    member_count = 0
                
                # Check if current user is member/admin
                try:
                    user_membership = user_client.table('club_memberships').select('role, status').eq('club_id', club['id']).eq('user_id', current_user_id).execute()
                    user_role = user_membership.data[0]['role'] if user_membership.data else None
                    user_status = user_membership.data[0]['status'] if user_membership.data else None
                    logger.info(f"User membership for club {club['id']}: role={user_role}, status={user_status}")
                except Exception as membership_error:
                    logger.error(f"Error getting user membership for club {club['id']}: {membership_error}")
                    user_role = None
                    user_status = None
                
                club_data = {
                    'id': club['id'],
                    'name': club['name'],
                    'description': club['description'],
                    'logo_url': club['logo_url'],
                    'is_public': club['is_public'],
                    'max_members': club['max_members'],
                    'member_count': member_count,
                    'admin_user': club.get('users'),
                    'user_role': user_role,
                    'user_status': user_status,
                    'created_at': club['created_at'],
                    'latitude': club.get('latitude'),
                    'longitude': club.get('longitude')
                }
                clubs.append(club_data)
            
            logger.info(f"Successfully processed {len(clubs)} clubs")
            return {
                'clubs': clubs,
                'total': len(clubs)
            }, 200
            
        except Exception as e:
            logger.error(f"Error fetching clubs: {e}", exc_info=True)
            return {'error': f'Failed to fetch clubs: {str(e)}'}, 500
    
    @auth_required
    def post(self):
        """Create a new club"""
        try:
            current_user_id = get_user_id()
            data = request.get_json()
            
            # Validate required fields
            if not data.get('name'):
                return {'error': 'Club name is required'}, 400
            
            if not data.get('description'):
                return {'error': 'Club description is required'}, 400
            
            if len(data.get('description', '').strip()) < 20:
                return {'error': 'Club description must be at least 20 characters'}, 400
            
            admin_client = get_supabase_admin_client()
            
            # Check if club name already exists
            existing_club = admin_client.table('clubs').select('id').eq('name', data['name']).execute()
            if existing_club.data:
                return {'error': 'Club name already exists'}, 400
            
            # Create club
            club_data = {
                'name': data['name'],
                'description': data.get('description'),
                'logo_url': data.get('logo_url'),
                'admin_user_id': current_user_id,
                'is_public': data.get('is_public', True),
                'max_members': data.get('max_members', 50),
                'latitude': data.get('latitude'),
                'longitude': data.get('longitude')
            }
            
            result = admin_client.table('clubs').insert(club_data).execute()
            
            if result.data:
                club = result.data[0]
                logger.info(f"Club created: {club['id']} by user {current_user_id}")
                return {
                    'message': 'Club created successfully',
                    'club': club
                }, 201
            else:
                return {'error': 'Failed to create club'}, 500
                
        except Exception as e:
            logger.error(f"Error creating club: {e}", exc_info=True)
            return {'error': f'Failed to create club: {str(e)}'}, 500

class ClubResource(Resource):
    """Handle individual club operations"""
    
    @auth_required
    def get(self, club_id):
        """Get club details"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Get club with admin details
            club_result = admin_client.table('clubs').select("""
                *,
                users!admin_user_id(id, first_name, last_name)
            """).eq('id', club_id).execute()
            
            if not club_result.data:
                return {'error': 'Club not found'}, 404
            
            club = club_result.data[0]
            
            # Get club members
            members_result = admin_client.table('club_memberships').select("""
                *,
                users:user_id(id, first_name, last_name)
            """).eq('club_id', club_id).eq('status', 'approved').execute()
            
            # Check user's membership status
            user_membership = admin_client.table('club_memberships').select('role, status').eq('club_id', club_id).eq('user_id', current_user_id).execute()
            user_role = user_membership.data[0]['role'] if user_membership.data else None
            user_status = user_membership.data[0]['status'] if user_membership.data else None
            
            # Get pending membership requests (if user is admin)
            pending_requests = []
            if user_role == 'admin':
                pending_result = admin_client.table('club_memberships').select("""
                    *,
                    users:user_id(id, first_name, last_name)
                """).eq('club_id', club_id).eq('status', 'pending').execute()
                pending_requests = pending_result.data
            
            club_data = {
                'id': club['id'],
                'name': club['name'],
                'description': club['description'],
                'logo_url': club['logo_url'],
                'is_public': club['is_public'],
                'max_members': club['max_members'],
                'admin_user': club['admin_user'],
                'members': members_result.data,
                'member_count': len(members_result.data),
                'pending_requests': pending_requests,
                'user_role': user_role,
                'user_status': user_status,
                'created_at': club['created_at'],
                'latitude': club.get('latitude'),
                'longitude': club.get('longitude')
            }
            
            return {'club': club_data}, 200
            
        except Exception as e:
            logger.error(f"Error fetching club {club_id}: {e}", exc_info=True)
            return {'error': f'Failed to fetch club details: {str(e)}'}, 500
    
    @auth_required
    def put(self, club_id):
        """Update club details (admin only)"""
        try:
            current_user_id = get_user_id()
            data = request.get_json()
            admin_client = get_supabase_admin_client()
            
            # Check if user is club admin
            club_result = admin_client.table('clubs').select('admin_user_id').eq('id', club_id).execute()
            if not club_result.data:
                return {'error': 'Club not found'}, 404
            
            if club_result.data[0]['admin_user_id'] != current_user_id:
                return {'error': 'Only club admin can update club details'}, 403
            
            # Update club
            update_data = {}
            allowed_fields = ['name', 'description', 'logo_url', 'is_public', 'max_members', 'latitude', 'longitude']
            
            for field in allowed_fields:
                if field in data:
                    update_data[field] = data[field]
            
            if update_data:
                result = admin_client.table('clubs').update(update_data).eq('id', club_id).execute()
                
                if result.data:
                    logger.info(f"Club {club_id} updated by user {current_user_id}")
                    return {
                        'message': 'Club updated successfully',
                        'club': result.data[0]
                    }, 200
                else:
                    return {'error': 'Failed to update club'}, 500
            else:
                return {'error': 'No valid fields to update'}, 400
                
        except Exception as e:
            logger.error(f"Error updating club {club_id}: {e}", exc_info=True)
            return {'error': f'Failed to update club: {str(e)}'}, 500
    
    @auth_required
    def delete(self, club_id):
        """Delete club (admin only)"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Check if user is club admin
            club_result = admin_client.table('clubs').select('admin_user_id, name').eq('id', club_id).execute()
            if not club_result.data:
                return {'error': 'Club not found'}, 404
            
            club = club_result.data[0]
            if club['admin_user_id'] != current_user_id:
                return {'error': 'Only club admin can delete club'}, 403
            
            # Get all club members for notification
            members_result = admin_client.table('club_memberships').select('user_id').eq('club_id', club_id).eq('status', 'approved').execute()
            member_user_ids = [member['user_id'] for member in members_result.data if member['user_id'] != current_user_id]
            
            # Delete club (will cascade delete memberships)
            delete_result = admin_client.table('clubs').delete().eq('id', club_id).execute()
            
            if delete_result.data:
                logger.info(f"Club {club_id} deleted by user {current_user_id}")
                
                # Send notifications to former members
                if member_user_ids:
                    device_tokens = get_user_device_tokens(member_user_ids)
                    if device_tokens:
                        push_service.send_club_deleted_notification(
                            device_tokens=device_tokens,
                            club_name=club['name']
                        )
                
                return {'message': 'Club deleted successfully'}, 200
            else:
                return {'error': 'Failed to delete club'}, 500
                
        except Exception as e:
            logger.error(f"Error deleting club {club_id}: {e}", exc_info=True)
            return {'error': f'Failed to delete club: {str(e)}'}, 500

class ClubMembershipResource(Resource):
    """Handle club membership operations"""
    
    @auth_required
    def post(self, club_id):
        """Request to join club"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Check if club exists
            club_result = admin_client.table('clubs').select('name, admin_user_id, max_members').eq('id', club_id).execute()
            if not club_result.data:
                return {'error': 'Club not found'}, 404
            
            club = club_result.data[0]
            
            # Check if user is already a member
            existing_membership = admin_client.table('club_memberships').select('id, status').eq('club_id', club_id).eq('user_id', current_user_id).execute()
            if existing_membership.data:
                status = existing_membership.data[0]['status']
                if status == 'approved':
                    return {'error': 'You are already a member of this club'}, 400
                elif status == 'pending':
                    return {'error': 'Your membership request is already pending'}, 400
                elif status == 'rejected':
                    return {'error': 'Your membership request was rejected'}, 400
            
            # Check if club is at capacity
            current_members = admin_client.table('club_memberships').select('id', count='exact').eq('club_id', club_id).eq('status', 'approved').execute()
            if current_members.count >= club['max_members']:
                return {'error': 'Club is at maximum capacity'}, 400
            
            # Create membership request
            membership_data = {
                'club_id': club_id,
                'user_id': current_user_id,
                'status': 'pending'
            }
            
            result = admin_client.table('club_memberships').insert(membership_data).execute()
            
            if result.data:
                logger.info(f"User {current_user_id} requested to join club {club_id}")
                
                # Notify club admin
                admin_tokens = get_user_device_tokens([club['admin_user_id']])
                if admin_tokens:
                    user_result = admin_client.table('profiles').select('first_name, last_name').eq('id', current_user_id).execute()
                    user_name = f"{user_result.data[0]['first_name']} {user_result.data[0]['last_name']}" if user_result.data else "A user"
                    
                    push_service.send_club_join_request_notification(
                        device_tokens=admin_tokens,
                        requester_name=user_name,
                        club_name=club['name'],
                        club_id=club_id
                    )
                
                return {
                    'message': 'Membership request sent successfully',
                    'membership': result.data[0]
                }, 201
            else:
                return {'error': 'Failed to send membership request'}, 500
                
        except Exception as e:
            logger.error(f"Error requesting to join club {club_id}: {e}", exc_info=True)
            return {'error': f'Failed to request club membership: {str(e)}'}, 500

class ClubMemberManagementResource(Resource):
    """Handle club member management (admin operations)"""
    
    @auth_required
    def put(self, club_id, user_id):
        """Approve/deny membership request or update member role"""
        try:
            current_user_id = get_user_id()
            data = request.get_json()
            admin_client = get_supabase_admin_client()
            
            # Check if current user is club admin
            club_result = admin_client.table('clubs').select('admin_user_id, name').eq('id', club_id).execute()
            if not club_result.data:
                return {'error': 'Club not found'}, 404
            
            club = club_result.data[0]
            if club['admin_user_id'] != current_user_id:
                return {'error': 'Only club admin can manage memberships'}, 403
            
            # Get membership
            membership_result = admin_client.table('club_memberships').select('*').eq('club_id', club_id).eq('user_id', user_id).execute()
            if not membership_result.data:
                return {'error': 'Membership not found'}, 404
            
            # Update membership
            update_data = {}
            if 'status' in data:
                update_data['status'] = data['status']
            if 'role' in data:
                update_data['role'] = data['role']
            
            if update_data:
                result = admin_client.table('club_memberships').update(update_data).eq('club_id', club_id).eq('user_id', user_id).execute()
                
                if result.data:
                    logger.info(f"Membership for user {user_id} in club {club_id} updated by admin {current_user_id}")
                    
                    # Send notification to user
                    user_tokens = get_user_device_tokens([user_id])
                    if user_tokens and 'status' in data:
                        if data['status'] == 'approved':
                            push_service.send_club_membership_approved_notification(
                                device_tokens=user_tokens,
                                club_name=club['name'],
                                club_id=club_id
                            )
                        elif data['status'] == 'rejected':
                            push_service.send_club_membership_rejected_notification(
                                device_tokens=user_tokens,
                                club_name=club['name']
                            )
                    
                    return {
                        'message': 'Membership updated successfully',
                        'membership': result.data[0]
                    }, 200
                else:
                    return {'error': 'Failed to update membership'}, 500
            else:
                return {'error': 'No valid fields to update'}, 400
                
        except Exception as e:
            logger.error(f"Error updating membership for user {user_id} in club {club_id}: {e}", exc_info=True)
            return {'error': f'Failed to update membership: {str(e)}'}, 500
    
    @auth_required
    def delete(self, club_id, user_id):
        """Remove member from club or leave club"""
        try:
            current_user_id = get_user_id()
            admin_client = get_supabase_admin_client()
            
            # Check if club exists
            club_result = admin_client.table('clubs').select('admin_user_id, name').eq('id', club_id).execute()
            if not club_result.data:
                return {'error': 'Club not found'}, 404
            
            club = club_result.data[0]
            
            # Check permissions: user can leave themselves or admin can remove others
            if current_user_id != user_id and club['admin_user_id'] != current_user_id:
                return {'error': 'You can only leave clubs yourself or admin can remove members'}, 403
            
            # Cannot remove club admin
            if user_id == club['admin_user_id']:
                return {'error': 'Club admin cannot be removed from club'}, 400
            
            # Remove membership
            result = admin_client.table('club_memberships').delete().eq('club_id', club_id).eq('user_id', user_id).execute()
            
            if result.data:
                logger.info(f"User {user_id} removed from club {club_id} by {current_user_id}")
                return {'message': 'Successfully left/removed from club'}, 200
            else:
                return {'error': 'Membership not found'}, 404
                
        except Exception as e:
            logger.error(f"Error removing user {user_id} from club {club_id}: {e}", exc_info=True)
            return {'error': f'Failed to remove from club: {str(e)}'}, 500

# Register API endpoints
api.add_resource(ClubListResource, '/clubs')
api.add_resource(ClubResource, '/clubs/<club_id>')
api.add_resource(ClubMembershipResource, '/clubs/<club_id>/join')
api.add_resource(ClubMemberManagementResource, '/clubs/<club_id>/members/<user_id>')
