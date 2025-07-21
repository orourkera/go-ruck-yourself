"""
Clubs API endpoints for club management and membership
"""
import logging
import time
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
        start_time = time.time()
        logger.info(f"ClubListResource.get: Starting request processing")
        
        try:
            current_user_id = get_user_id()
            logger.info(f"Fetching clubs for user: {current_user_id}")
            
            # Use admin client to avoid RLS infinite recursion issues
            admin_client = get_supabase_admin_client()
            logger.info("Got Supabase admin client")
            
            # Get query parameters
            search = request.args.get('search', '')
            is_public = request.args.get('is_public')
            user_clubs_only = request.args.get('user_clubs_only', 'false').lower() == 'true'
            logger.info(f"Query params - search: {search}, is_public: {is_public}, user_clubs_only: {user_clubs_only}")
            
            # First, check if clubs table exists
            try:
                test_query = admin_client.table('clubs').select('count', count='exact').limit(1).execute()
                logger.info(f"Clubs table test query successful. Count: {test_query.count}")
            except Exception as table_error:
                logger.error(f"Clubs table does not exist or is inaccessible: {table_error}")
                return {'error': 'Clubs table not found'}, 500
            
            # Base query - simplified to avoid complex joins
            query = admin_client.table('clubs').select("""
                *,
                admin_user:admin_user_id(id, username, avatar_url)
            """)
            logger.info("Created base query")
            
            # Apply filters
            if search:
                query = query.ilike('name', f'%{search}%')
                logger.info(f"Applied search filter: {search}")
            
            if is_public is not None:
                query = query.eq('is_public', is_public.lower() == 'true')
                logger.info(f"Applied public filter: {is_public}")
            
            # Execute query
            logger.info("Executing main clubs query")
            result = query.order('created_at', desc=True).execute()
            logger.info(f"Main query returned {len(result.data)} clubs")
            
            # Get user's club memberships for filtering
            user_memberships = admin_client.table('club_memberships').select('club_id').eq('user_id', current_user_id).eq('status', 'approved').execute()
            user_club_ids = {membership['club_id'] for membership in user_memberships.data} if user_memberships.data else set()
            logger.info(f"User is member of {len(user_club_ids)} clubs")
            
            # OPTIMIZATION: Get all member counts and user memberships in batch queries
            # instead of N+1 individual queries per club
            
            # Get all club IDs that we need to process
            club_ids = [club['id'] for club in result.data]
            
            # Batch query for member counts for all clubs
            member_counts = {}
            if club_ids:
                member_count_query = admin_client.table('club_memberships')\
                    .select('club_id')\
                    .eq('status', 'approved')\
                    .in_('club_id', club_ids)\
                    .execute()
                
                # Count members per club
                for membership in member_count_query.data:
                    club_id = membership['club_id']
                    member_counts[club_id] = member_counts.get(club_id, 0) + 1
            
            # Batch query for current user's memberships in all these clubs  
            user_memberships_batch = {}
            if club_ids:
                user_membership_query = admin_client.table('club_memberships')\
                    .select('club_id, role, status')\
                    .eq('user_id', current_user_id)\
                    .in_('club_id', club_ids)\
                    .execute()
                
                for membership in user_membership_query.data:
                    user_memberships_batch[membership['club_id']] = {
                        'role': membership['role'],
                        'status': membership['status']
                    }
            
            logger.info(f"Batch queries completed - member counts for {len(member_counts)} clubs, user memberships for {len(user_memberships_batch)} clubs")
            
            clubs = []
            for i, club in enumerate(result.data):
                logger.debug(f"Processing club {i+1}/{len(result.data)}: {club.get('name', 'Unknown')}")
                
                # Apply RLS policy manually: show only public clubs OR clubs user is member of
                is_public_club = club.get('is_public', False)
                is_user_member = club['id'] in user_club_ids
                
                # If user_clubs_only is true, only show clubs the user is a member of
                if user_clubs_only and not is_user_member:
                    continue
                
                # Apply RLS policy: show only public clubs OR clubs user is member of
                if not (is_public_club or is_user_member):
                    continue
                
                # Get member count from batch result
                member_count = member_counts.get(club['id'], 0)
                
                # Get user membership from batch result
                user_membership_data = user_memberships_batch.get(club['id'])
                user_role = user_membership_data['role'] if user_membership_data else None
                user_status = user_membership_data['status'] if user_membership_data else None

                # Ensure only designated club admin is treated as 'admin'
                if user_role == 'admin' and club['admin_user_id'] != current_user_id:
                    logger.warning(
                        f"User {current_user_id} has admin role in memberships table for club {club['id']} "
                        f"but is NOT the designated admin_user_id ({club['admin_user_id']}). Downgrading role to 'member'."
                    )
                    user_role = 'member'
                    
                club_data = {
                    'id': club['id'],
                    'name': club['name'],
                    'description': club['description'],
                    'logo_url': club['logo_url'],
                    'is_public': club['is_public'],
                    'max_members': club['max_members'],
                    'member_count': member_count,
                    'admin_user_id': club['admin_user_id'],  # Add direct admin_user_id field
                    'user_role': user_role,
                    'user_status': user_status,
                    'created_at': club['created_at'],
                    'latitude': club.get('latitude'),
                    'longitude': club.get('longitude')
                }
                
                # Only include admin_user if the join data exists and is valid
                admin_user_data = club.get('admin_user')
                if admin_user_data and isinstance(admin_user_data, dict):
                    club_data['admin_user'] = admin_user_data
                
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
                club_id = club['id']
                logger.info(f"Club created: {club_id} by user {current_user_id}")
                
                # Automatically add the club admin as a member
                try:
                    membership_data = {
                        'club_id': club_id,
                        'user_id': current_user_id,
                        'role': 'admin',
                        'status': 'approved'
                    }
                    membership_result = admin_client.table('club_memberships').insert(membership_data).execute()
                    if membership_result.data:
                        logger.info(f"Admin user {current_user_id} added as member to club {club_id}")
                    else:
                        logger.warning(f"Failed to add admin user as member to club {club_id}")
                except Exception as membership_error:
                    logger.error(f"Error adding admin as member: {membership_error}")
                    # Don't fail the club creation if membership fails
                
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
            logger.info(f"Fetching club details for club_id: {club_id}")
            
            # Try multiple join syntaxes since Supabase can be finicky
            try:
                # First try the standard join syntax (matching club_memberships pattern)
                club_result = admin_client.table('clubs').select("""
                    *,
                    admin_user:admin_user_id(id, username, avatar_url)
                """).eq('id', club_id).execute()
                
                if club_result.data and club_result.data[0].get('admin_user'):
                    logger.info("Standard join syntax worked")
                else:
                    # Try alternative syntax
                    logger.info("Standard join failed, trying alternative syntax")
                    club_result = admin_client.table('clubs').select("""
                        *,
                        user:admin_user_id(id, username, avatar_url)
                    """).eq('id', club_id).execute()
                    
                    if club_result.data and club_result.data[0].get('user'):
                        logger.info("Alternative join syntax worked")
                        # Rename the field for consistency
                        club_result.data[0]['admin_user'] = club_result.data[0].pop('user')
                    else:
                        # Join failed, fetch basic club data
                        logger.info("All join syntaxes failed, fetching basic club data")
                        club_result = admin_client.table('clubs').select('*').eq('id', club_id).execute()
                        
            except Exception as join_error:
                logger.warning(f"Join query failed: {join_error}")
                # Fall back to basic club query
                club_result = admin_client.table('clubs').select('*').eq('id', club_id).execute()
            
            logger.info(f"Club query result: {club_result.data}")
            
            if not club_result.data:
                return {'error': 'Club not found'}, 404
            
            club = club_result.data[0]
            logger.info(f"Club data: {club}")
            logger.info(f"Admin user join data: {club.get('admin_user') or club.get('user')}")
            
            # Get club members
            members_result = admin_client.table('club_memberships').select('*').eq('club_id', club_id).eq('status', 'approved').execute()
            logger.info(f"Raw members result: {members_result.data}")
            
            # Fetch user data for members manually
            members_with_user_data = []
            if members_result.data:
                user_ids = [member['user_id'] for member in members_result.data]
                logger.info(f"User IDs to fetch: {user_ids}")
                if user_ids:
                    try:
                        users_result = admin_client.table('user').select('id, username, avatar_url').in_('id', user_ids).execute()
                        logger.info(f"Users query result: {users_result.data}")
                        logger.info(f"Users query error: {getattr(users_result, 'error', None)}")
                        users_dict = {user['id']: user for user in users_result.data} if users_result.data else {}
                        logger.info(f"Users dict: {users_dict}")
                        
                        for member in members_result.data:
                            member_with_user = member.copy()
                            if member['user_id'] in users_dict:
                                member_with_user['user'] = users_dict[member['user_id']]
                                logger.info(f"Added user data for member {member['user_id']}: {users_dict[member['user_id']]}")
                            else:
                                logger.warning(f"No user data found for member {member['user_id']}")
                            members_with_user_data.append(member_with_user)
                    except Exception as e:
                        logger.error(f"Error fetching user data: {e}")
                        members_with_user_data = members_result.data  # Fallback to original data
        
            logger.info(f"Final members with user data: {members_with_user_data}")
            
            # Check user's membership status
            user_membership = admin_client.table('club_memberships').select('role, status').eq('club_id', club_id).eq('user_id', current_user_id).execute()
            user_role = user_membership.data[0]['role'] if user_membership.data else None
            user_status = user_membership.data[0]['status'] if user_membership.data else None

            # Guarantee that the designated club admin is always recognised as admin even
            # if their membership row is missing or has been tampered with.
            if club['admin_user_id'] == current_user_id:
                logger.info(f"ADMIN OVERRIDE: User {current_user_id} is the designated admin for club {club_id}. Setting role=admin, status=approved")
                user_role = 'admin'
                user_status = user_status or 'approved'
            else:
                logger.info(f"ADMIN CHECK: User {current_user_id} is NOT the designated admin (admin_user_id={club['admin_user_id']}) for club {club_id}")
            
            # Ensure only the designated club admin is treated as 'admin'
            if user_role == 'admin' and club['admin_user_id'] != current_user_id:
                logger.warning(
                    f"User {current_user_id} has admin role in memberships table for club {club_id} "
                    f"but is NOT the designated admin_user_id ({club['admin_user_id']}). Downgrading role to 'member'."
                )
                user_role = 'member'
                        
            # Get pending membership requests (if user is admin)
            pending_requests = []
            if user_role == 'admin':
                pending_result = admin_client.table('club_memberships').select('*').eq('club_id', club_id).eq('status', 'pending').execute()
                
                logger.info(f"Raw pending requests result: {pending_result.data}")
                
                # Fetch user data for pending requests manually
                if pending_result.data:
                    pending_user_ids = [req['user_id'] for req in pending_result.data]
                    logger.info(f"Pending user IDs to fetch: {pending_user_ids}")
                    if pending_user_ids:
                        try:
                            pending_users_result = admin_client.table('user').select('id, username, avatar_url').in_('id', pending_user_ids).execute()
                            logger.info(f"Pending users query result: {pending_users_result.data}")
                            logger.info(f"Pending users query error: {getattr(pending_users_result, 'error', None)}")
                            pending_users_dict = {user['id']: user for user in pending_users_result.data} if pending_users_result.data else {}
                            logger.info(f"Pending users dict: {pending_users_dict}")
                            
                            for request in pending_result.data:
                                request_with_user = request.copy()
                                if request['user_id'] in pending_users_dict:
                                    request_with_user['user'] = pending_users_dict[request['user_id']]
                                    logger.info(f"Added user data for pending request {request['user_id']}: {pending_users_dict[request['user_id']]}")
                                else:
                                    logger.warning(f"No user data found for pending request {request['user_id']}")
                                pending_requests.append(request_with_user)
                        except Exception as e:
                            logger.error(f"Error fetching pending users data: {e}")
                            pending_requests = pending_result.data  # Fallback to original data
            
                logger.info(f"Final pending requests with user data: {pending_requests}")
            
            logger.info(f"FINAL VALUES: user_role={user_role}, user_status={user_status} for user {current_user_id} in club {club_id}")
            
            club_data = {
                'id': club['id'],
                'name': club['name'],
                'description': club['description'],
                'logo_url': club['logo_url'],
                'is_public': club['is_public'],
                'max_members': club['max_members'],
                'admin_user_id': club['admin_user_id'],  # Add direct admin_user_id field
                'members': members_with_user_data,
                'member_count': len(members_with_user_data),
                'pending_requests': pending_requests,
                'user_role': user_role,
                'user_status': user_status,
                'created_at': club['created_at'],
                'latitude': club.get('latitude'),
                'longitude': club.get('longitude')
            }
            
            # Only include admin_user if the join data exists and is valid
            admin_user_data = club.get('admin_user')
            if admin_user_data and isinstance(admin_user_data, dict):
                logger.info(f"Found admin user data: {admin_user_data}")
                club_data['admin_user'] = admin_user_data
            else:
                logger.warning(f"No admin user data found in join. Raw club data: {club}")
                # Try to fetch admin user separately
                if club.get('admin_user_id'):
                    logger.info(f"Fetching admin user separately for admin_user_id: {club['admin_user_id']}")
                    admin_user_result = admin_client.table('user').select('id, username, avatar_url').eq('id', club['admin_user_id']).execute()
                    if admin_user_result.data:
                        logger.info(f"Found admin user: {admin_user_result.data[0]}")
                        club_data['admin_user'] = admin_user_result.data[0]
                    else:
                        logger.warning(f"Admin user not found for ID: {club['admin_user_id']}")
            
            logger.info(f"Final club_data: {club_data}")
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
                    
                    # Fetch updated club with member count
                    updated_club_result = admin_client.table('clubs').select('''
                        *,
                        member_count:club_memberships!club_memberships_club_id_fkey(count)
                    ''').eq('id', club_id).single().execute()
                    
                    if updated_club_result.data:
                        # Process member count
                        club_data = updated_club_result.data
                        club_data['member_count'] = club_data.get('member_count', [{}])[0].get('count', 0)
                        
                        return {
                            'message': 'Club updated successfully',
                            'club': club_data
                        }, 200
                    else:
                        # Fallback to basic club data if member count query fails
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
                'role': 'member',  
                'status': 'pending'
            }
            
            logger.info(f"[DEBUG] About to insert club membership data: {membership_data}")
            result = admin_client.table('club_memberships').insert(membership_data).execute()
            
            if result.data:
                logger.info(f"User {current_user_id} requested to join club {club_id}")
                
                # Notify club admin
                admin_tokens = get_user_device_tokens([club['admin_user_id']])
                if admin_tokens:
                    user_result = admin_client.table('user').select('username').eq('id', current_user_id).execute()
                    user_name = user_result.data[0]['username'] if user_result.data else "A user"
                    
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
            
            # Handle 'action' field from frontend (convert to status)
            if 'action' in data:
                if data['action'] == 'approve':
                    update_data['status'] = 'approved'
                    # Explicitly set role to 'member' when approving (unless explicitly specified otherwise)
                    if 'role' not in data:
                        update_data['role'] = 'member'
                elif data['action'] == 'reject':
                    update_data['status'] = 'rejected'
                elif data['action'] == 'deny':
                    update_data['status'] = 'rejected'
                elif data['action'] == 'admin':
                    update_data['role'] = 'admin'
                elif data['action'] == 'member':
                    update_data['role'] = 'member'
            
            # Direct status/role updates
            if 'status' in data:
                update_data['status'] = data['status']
            if 'role' in data:
                update_data['role'] = data['role']
            
            if update_data:
                result = admin_client.table('club_memberships').update(update_data).eq('club_id', club_id).eq('user_id', user_id).execute()
                
                if result.data:
                    logger.info(f"Membership for user {user_id} in club {club_id} updated by admin {current_user_id}")
                    
                    # Send push notifications (database notifications handled by trigger)
                    user_tokens = get_user_device_tokens([user_id])
                    if user_tokens:
                        if update_data.get('status') == 'approved':
                            push_service.send_club_membership_approved_notification(
                                device_tokens=user_tokens,
                                club_name=club['name'],
                                club_id=club_id
                            )
                        elif update_data.get('status') == 'rejected':
                            push_service.send_club_membership_rejected_notification(
                                device_tokens=user_tokens,
                                club_name=club['name'],
                                club_id=club_id
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
