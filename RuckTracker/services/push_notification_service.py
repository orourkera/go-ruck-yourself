
"""
Push notification service using Firebase Cloud Messaging (FCM)
"""
import json
import logging
import os
import requests
import firebase_admin
from firebase_admin import credentials, messaging
from typing import List, Dict, Any
import time
from google.auth.transport.requests import Request
from google.oauth2 import service_account
from .redis_cache_service import cache_get, cache_set

logger = logging.getLogger(__name__)

class PushNotificationService:
    """Service for sending push notifications via Firebase Cloud Messaging"""
    
    def __init__(self):
        """
        Initialize FCM service using service account authentication
        """
        logger.info("🔧 FIREBASE PUSH SERVICE INITIALIZATION START")
        
        self.project_id = os.getenv('FIREBASE_PROJECT_ID')
        self.service_account_path = os.getenv('FIREBASE_SERVICE_ACCOUNT_PATH')
        self.service_account_json = os.getenv('FIREBASE_SERVICE_ACCOUNT_JSON')
        
        logger.info(f"🔧 Firebase Project ID: {self.project_id}")
        logger.info(f"🔧 Service Account Path: {self.service_account_path}")
        logger.info(f"🔧 Service Account JSON: {'✅ Present' if self.service_account_json else '❌ Missing'}")
        
        # Firebase Admin SDK uses projectId implicitly; keep REST URL for fallback but prefer SDK
        self.fcm_url = f"https://fcm.googleapis.com/v1/projects/{self.project_id}/messages:send"
        self._access_token = None
        self._token_expiry = 0

        # Initialize Firebase Admin SDK once globally
        try:
            if not firebase_admin._apps:
                logger.info("🔧 Firebase Admin SDK not initialized, initializing now...")
                cred = None
                
                # Prioritize JSON over path, and only use path if file actually exists
                if self.service_account_json:
                    logger.info("🔧 Using Firebase service account JSON from environment variable")
                    try:
                        # Handle double-escaped newlines in private key that can occur with Heroku config
                        service_account_data = json.loads(self.service_account_json)
                        logger.info(f"🔧 Parsed service account data - Project ID: {service_account_data.get('project_id')}")
                        
                        if 'private_key' in service_account_data:
                            # Fix double-escaped newlines in private key
                            original_key_length = len(service_account_data['private_key'])
                            service_account_data['private_key'] = service_account_data['private_key'].replace('\\n', '\n')
                            new_key_length = len(service_account_data['private_key'])
                            logger.info(f"🔧 Fixed private key newlines: {original_key_length} -> {new_key_length} chars")
                            
                        cred = credentials.Certificate(service_account_data)
                        logger.info("✅ Service account credentials created from JSON")
                    except json.JSONDecodeError as e:
                        logger.error(f"❌ Failed to parse service account JSON: {e}")
                    except Exception as e:
                        logger.error(f"❌ Failed to create credentials from JSON: {e}")
                        
                elif self.service_account_path and os.path.isfile(self.service_account_path):
                    logger.info(f"🔧 Using Firebase service account file: {self.service_account_path}")
                    try:
                        cred = credentials.Certificate(self.service_account_path)
                        logger.info("✅ Service account credentials created from file")
                    except Exception as e:
                        logger.error(f"❌ Failed to create credentials from file: {e}")
                elif self.service_account_path:
                    logger.error(f"❌ Firebase service account path specified but file does not exist: {self.service_account_path}")
                
                if not cred:
                    logger.warning("⚠️ No valid Firebase service account credentials found, trying default application credentials")

                if cred:
                    firebase_admin.initialize_app(cred, {
                        'projectId': self.project_id,
                    })
                    logger.info(f"✅ Firebase Admin SDK initialized successfully for project {self.project_id}")
                else:
                    # If no explicit credentials, try default application creds
                    firebase_admin.initialize_app()
                    logger.info(f"✅ Firebase Admin SDK initialized with default credentials for project {self.project_id}")
            else:
                logger.info("✅ Firebase Admin SDK already initialized")
                    
        except Exception as e:
            logger.error(f"❌ CRITICAL: Failed to initialize Firebase Admin SDK: {e}", exc_info=True)
            # Don't raise exception - allow service to continue without push notifications
            logger.warning("⚠️ Push notifications will be disabled due to Firebase initialization failure")

        # Validate configuration
        if not self.project_id:
            logger.error("❌ CRITICAL: FIREBASE_PROJECT_ID environment variable not set")
        if not self.service_account_json and not (self.service_account_path and os.path.isfile(self.service_account_path)):
            logger.error("❌ CRITICAL: No valid Firebase credentials found. Either FIREBASE_SERVICE_ACCOUNT_JSON must be set or FIREBASE_SERVICE_ACCOUNT_PATH must point to an existing file")
        
        # Test Firebase connectivity
        try:
            if firebase_admin._apps:
                logger.info("🧪 Testing Firebase connectivity...")
                # Try to create a test message (don't send it)
                test_message = messaging.Message(
                    notification=messaging.Notification(title="Test", body="Test"),
                    token="test_token_for_validation"
                )
                logger.info("✅ Firebase message creation test passed")
            else:
                logger.error("❌ Firebase Admin SDK not available for testing")
        except Exception as test_error:
            logger.error(f"❌ Firebase connectivity test failed: {test_error}")
            
        logger.info("🔧 FIREBASE PUSH SERVICE INITIALIZATION COMPLETE")
        
        if not self.project_id:
            logger.error("❌ FIREBASE_PROJECT_ID environment variable not set")
        if not self.service_account_json and not (self.service_account_path and os.path.isfile(self.service_account_path)):
            logger.error("❌ No valid Firebase credentials found. Either FIREBASE_SERVICE_ACCOUNT_JSON must be set or FIREBASE_SERVICE_ACCOUNT_PATH must point to an existing file")
    
    def _get_access_token(self) -> str:
        """Get OAuth2 access token for Firebase V1 API"""
        # Check if we have a valid cached token
        if self._access_token and time.time() < self._token_expiry:
            return self._access_token
            
        try:
            # Load service account credentials - prioritize JSON over path, check file existence
            if self.service_account_json:
                # Handle double-escaped newlines in private key that can occur with Heroku config
                service_account_data = json.loads(self.service_account_json)
                if 'private_key' in service_account_data:
                    # Fix double-escaped newlines in private key
                    service_account_data['private_key'] = service_account_data['private_key'].replace('\\n', '\n')
                credentials = service_account.Credentials.from_service_account_info(
                    service_account_data,
                    scopes=['https://www.googleapis.com/auth/firebase.messaging']
                )
            elif self.service_account_path and os.path.isfile(self.service_account_path):
                credentials = service_account.Credentials.from_service_account_file(
                    self.service_account_path,
                    scopes=['https://www.googleapis.com/auth/firebase.messaging']
                )
            else:
                if self.service_account_path:
                    logger.error(f"Firebase service account file does not exist: {self.service_account_path}")
                logger.error("No valid Firebase service account credentials configured for access token")
                return None
            
            # Refresh the token
            credentials.refresh(Request())
            
            self._access_token = credentials.token
            # Set expiry time (tokens usually last 1 hour, we refresh 5 minutes early)
            self._token_expiry = time.time() + 3300  # 55 minutes
            
            return self._access_token
            
        except Exception as e:
            logger.error(f"Failed to get Firebase access token: {e}")
            return None
    
    def send_notification(
        self,
        device_tokens: List[str],
        title: str,
        body: str,
        notification_data: Dict[str, Any] = None
    ) -> bool:
        """
        Send push notification to multiple devices using V1 API
        
        Args:
            device_tokens: List of FCM device tokens
            title: Notification title
            body: Notification body
            notification_data: Additional data to include
            
        Returns:
            bool: True if all successful, False otherwise
        """
        if not device_tokens:
            logger.info("📱 No device tokens provided - user likely has notifications disabled")
            return True  # Return True to indicate graceful handling, not a failure
        
        logger.info(f"🚀 PUSH NOTIFICATION START - Sending to {len(device_tokens)} devices")
        logger.info(f"📋 Title: '{title}'")
        logger.info(f"📋 Body: '{body}'") 
        logger.info(f"📋 Data: {notification_data}")
        logger.info(f"🎯 Device tokens: {device_tokens[:2]}{'...' if len(device_tokens) > 2 else ''}")
        
        if not self.project_id:
            logger.error("❌ FIREBASE_PROJECT_ID not configured")
            return False
            
        if not firebase_admin._apps:
            logger.error("❌ Firebase Admin SDK not initialized")
            return False
        
        success_count = 0
        failure_count = 0
        
        # Idempotency check (dedupe per event/user, not globally)
        notif_type = notification_data.get('type', 'generic')
        event_id = (
            notification_data.get('session_id')
            or notification_data.get('ruck_id')
            or notification_data.get('like_id')
            or notification_data.get('duel_id')
            or notification_data.get('event_id')
            or notification_data.get('recipient_id')
            or 'global'
        )
        notif_id = f"{notif_type}_{event_id}"
        if cache_get(f"notif_sent:{notif_id}"):
            logger.warning(f"Duplicate notification skipped: {notif_id}")
            return True

        for i, token in enumerate(device_tokens):
            logger.info(f"📱 Sending notification {i+1}/{len(device_tokens)} to token: {token[:20]}...")
            
            try:
                # Convert all data values to strings (Firebase requirement)
                string_data = {}
                if notification_data:
                    for key, value in notification_data.items():
                        string_data[key] = str(value)
                
                logger.info(f"📦 Notification data payload: {string_data}")
                
                # Create message using Firebase Admin SDK
                message = messaging.Message(
                    notification=messaging.Notification(
                        title=title,
                        body=body,
                    ),
                    data=string_data,
                    token=token,
                    android=messaging.AndroidConfig(
                        notification=messaging.AndroidNotification(
                            click_action='FLUTTER_NOTIFICATION_CLICK',
                            channel_id='default',
                            priority='high'
                        )
                    ),
                    apns=messaging.APNSConfig(
                        payload=messaging.APNSPayload(
                            aps=messaging.Aps(
                                alert=messaging.ApsAlert(
                                    title=title,
                                    body=body
                                ),
                                category='FLUTTER_NOTIFICATION_CLICK',
                                sound='default'
                            )
                        )
                    )
                )
                
                logger.info(f"🔄 Attempting to send message via Firebase Admin SDK...")
                response = messaging.send(message)
                logger.info(f"✅ Push notification sent successfully! Response: {response}")
                success_count += 1
                
            except messaging.UnregisteredError:
                logger.warning(f"⚠️ Device token is unregistered (invalid): {token[:20]}...")
                # Deactivate invalid token in DB
                try:
                    from RuckTracker.supabase_client import get_supabase_admin_client
                    admin_client = get_supabase_admin_client()
                    admin_client.table('user_device_tokens') \
                        .update({'is_active': False}) \
                        .eq('fcm_token', token) \
                        .execute()
                except Exception as deact_err:
                    logger.error(f"Failed to deactivate invalid token: {deact_err}")
                failure_count += 1
            except messaging.SenderIdMismatchError:
                logger.error(f"❌ Sender ID mismatch for token: {token[:20]}...")
                failure_count += 1
            except messaging.QuotaExceededError:
                logger.error(f"❌ FCM quota exceeded")
                failure_count += 1
            except Exception as e:
                logger.error(f"❌ Failed to send notification to {token[:20]}...: {str(e)}", exc_info=True)
                failure_count += 1
        
        total_tokens = len(device_tokens)
        logger.info(f"📊 PUSH NOTIFICATION SUMMARY:")
        logger.info(f"   ✅ Successful: {success_count}/{total_tokens}")
        logger.info(f"   ❌ Failed: {failure_count}/{total_tokens}")
        logger.info(f"   📈 Success rate: {(success_count/total_tokens)*100:.1f}%")
        
        # After successful send
        cache_set(f"notif_sent:{notif_id}", True, 86400)

        return success_count > 0

    def send_duel_comment_notification(
        self,
        device_tokens: List[str],
        commenter_name: str,
        duel_name: str,
        duel_id: str,
        comment_id: str
    ) -> bool:
        """Send duel comment notification"""
        title = "New Duel Comment"
        body = f"{commenter_name} commented on '{duel_name}'"
        
        data = {
            'type': 'duel_comment',
            'duel_id': duel_id,
            'comment_id': comment_id,
            'duel_name': duel_name,
            'commenter_name': commenter_name
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )
    
    def send_ruck_comment_notification(
        self,
        device_tokens: List[str],
        commenter_name: str,
        ruck_id: str,
        comment_id: str
    ) -> bool:
        """Send ruck comment notification"""
        if not device_tokens:
            logger.info(f"📱 No device tokens for ruck comment notification (ruck_id: {ruck_id}) - user notifications disabled")
            return True  # Graceful handling, not a failure
            
        title = "New Comment"
        body = f"{commenter_name} commented on your ruck!"
        
        data = {
            'type': 'ruck_comment',
            'ruck_id': ruck_id,
            'comment_id': comment_id,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )
    
    def send_ruck_like_notification(
        self,
        device_tokens: List[str],
        liker_name: str,
        ruck_id: str
    ) -> bool:
        """Send ruck like notification"""
        title = "New Like"
        body = f"{liker_name} liked your ruck!"
        
        data = {
            'type': 'ruck_like',
            'ruck_id': ruck_id,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def send_ruck_participant_activity_notification(
        self,
        device_tokens: List[str],
        actor_name: str,
        ruck_id: str,
        activity_type: str
    ) -> bool:
        """Notify prior participants of new activity (like/comment) on a ruck they interacted with."""
        if activity_type not in ("like", "comment"):
            activity_type = "activity"
        title = "New activity on a ruck"
        verb = "liked" if activity_type == "like" else ("commented on" if activity_type == "comment" else "updated")
        body = f"{actor_name} {verb} a ruck you interacted with"

        data = {
            'type': 'ruck_activity',
            'activity': activity_type,
            'ruck_id': ruck_id,
            'actor_name': actor_name,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }

        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )
    
    def send_new_follower_notification(
        self,
        device_tokens: List[str],
        follower_name: str,
        follower_id: str
    ) -> bool:
        """Send new follower notification to the followed user"""
        title = "New Follower"
        body = f"{follower_name} started following you"
        data = {
            'type': 'new_follower',
            'follower_id': follower_id,
            'follower_name': follower_name,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            'route': '/profile',
            'user_id': follower_id  # Navigate to follower's profile
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )
    
    def send_duel_joined_notification(
        self,
        device_tokens: List[str],
        joiner_name: str,
        duel_name: str,
        duel_id: str
    ) -> bool:
        """Send duel joined notification to duel creator"""
        title = "New Duel Participant"
        body = f"{joiner_name} joined your duel '{duel_name}'"
        
        data = {
            'type': 'duel_joined',
            'duel_id': duel_id,
            'duel_name': duel_name,
            'joiner_name': joiner_name
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )
    
    def send_duel_started_notification(
        self,
        device_tokens: List[str],
        duel_name: str,
        duel_id: str
    ) -> bool:
        """Send duel started notification to all participants"""
        title = "Duel Started!"
        body = f"'{duel_name}' has started! Begin your challenge"
        
        data = {
            'type': 'duel_started',
            'duel_id': duel_id,
            'duel_name': duel_name
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )
    
    def send_duel_completed_notification(
        self,
        device_tokens: List[str],
        duel_name: str,
        duel_id: str
    ) -> bool:
        """Send duel completed notification to all participants"""
        title = "Duel Completed!"
        body = f"'{duel_name}' has completed! Check the results"
        
        data = {
            'type': 'duel_completed',
            'duel_id': duel_id,
            'duel_name': duel_name
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )
    
    def send_duel_progress_notification(
        self,
        device_tokens: List[str],
        participant_name: str,
        duel_name: str,
        duel_id: str,
        ruck_id: str
    ) -> bool:
        """Send duel progress notification when participant completes a ruck"""
        title = "Duel Progress Update"
        body = f"{participant_name} completed a ruck for '{duel_name}'"
        
        data = {
            'type': 'duel_progress',
            'duel_id': duel_id,
            'duel_name': duel_name,
            'participant_name': participant_name,
            'ruck_id': ruck_id
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )
    
    def send_duel_deleted_notification(
        self,
        device_tokens: List[str],
        deleter_name: str,
        duel_name: str,
        duel_id: str
    ) -> bool:
        """Send duel deleted notification when creator deletes a duel"""
        title = "Duel Deleted"
        body = f"The duel '{duel_name}' has been deleted by {deleter_name}"
        
        data = {
            'type': 'duel_deleted',
            'duel_id': duel_id,
            'duel_name': duel_name,
            'deleter_name': deleter_name
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )
    
    def send_achievement_notification(
        self,
        device_tokens: List[str],
        achievement_names: List[str],
        session_id: str
    ) -> bool:
        """Send achievement earned notification for one or multiple achievements"""
        if not device_tokens:
            logger.info(f"📱 No device tokens for achievement notification (session_id: {session_id}) - user notifications disabled")
            return True  # Graceful handling, not a failure
        
        if len(achievement_names) == 1:
            title = "🏆 Achievement Unlocked!"
            body = f"You earned: {achievement_names[0]}"
        else:
            title = f"🏆 {len(achievement_names)} Achievements Unlocked!"
            body = f"You earned: {', '.join(achievement_names[:2])}" + (f" and {len(achievement_names)-2} more!" if len(achievement_names) > 2 else "")
        
        data = {
            'type': 'achievement',
            'session_id': session_id,
            'achievement_count': str(len(achievement_names)),
            'achievement_names': ','.join(achievement_names)
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def send_ruck_started_notification(
        self,
        device_tokens: List[str],
        rucker_name: str,
        ruck_id: str
    ) -> bool:
        """Send ruck started notification to followers"""
        if not device_tokens:
            logger.info(f"📱 No device tokens for ruck started notification (ruck_id: {ruck_id}) - followers have notifications disabled")
            return True  # Graceful handling, not a failure
        
        title = "🎒 Ruck Started!"
        body = f"{rucker_name} started rucking"
        
        data = {
            'type': 'ruck_started',
            'ruck_id': ruck_id,
            'rucker_name': rucker_name
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def send_club_join_request_notification(self, device_tokens: List[str], requester_name: str, club_name: str, club_id: str):
        """Send notification when someone requests to join a club"""
        if not device_tokens:
            logger.info(f"📱 No device tokens for club join request notification (club_id: {club_id}) - admin notifications disabled")
            return True  # Graceful handling, not a failure
            
        title = "New Club Join Request"
        body = f"{requester_name} wants to join {club_name}"
        
        data = {
            'type': 'club_join_request',
            'requester_name': requester_name,
            'club_name': club_name,
            'club_id': club_id,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def send_club_membership_approved_notification(self, device_tokens: List[str], club_name: str, club_id: str):
        """Send notification when club membership is approved"""
        if not device_tokens:
            logger.info(f"📱 No device tokens for club membership approved notification (club_id: {club_id}) - user notifications disabled")
            return True  # Graceful handling, not a failure
            
        title = "Welcome to the Club!"
        body = f"Your request to join {club_name} has been approved"
        
        data = {
            'type': 'club_membership_approved',
            'club_name': club_name,
            'club_id': club_id,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def send_club_membership_rejected_notification(self, device_tokens: List[str], club_name: str):
        """Send notification when club membership is rejected"""
        if not device_tokens:
            logger.info(f"📱 No device tokens for club membership rejected notification - user notifications disabled")
            return True  # Graceful handling, not a failure
            
        title = "Club Membership Update"
        body = f"Your request to join {club_name} was not approved"
        
        data = {
            'type': 'club_membership_rejected',
            'club_name': club_name,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def send_club_deleted_notification(self, device_tokens: List[str], club_name: str):
        """Send notification when a club is deleted"""
        if not device_tokens:
            logger.info(f"📱 No device tokens for club deleted notification - member notifications disabled")
            return True  # Graceful handling, not a failure
            
        title = "Club Disbanded"
        body = f"{club_name} has been disbanded by the admin"
        
        data = {
            'type': 'club_deleted',
            'club_name': club_name,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def send_club_event_notification(self, device_tokens: List[str], event_title: str, club_name: str, event_id: str, club_id: str):
        """Send notification when a new club event is created"""
        if not device_tokens:
            logger.info(f"📱 No device tokens for club event notification (event_id: {event_id}) - member notifications disabled")
            return True  # Graceful handling, not a failure
            
        title = f"New {club_name} Event"
        body = f"{event_title} - Check it out!"
        
        data = {
            'type': 'club_event_created',
            'event_title': event_title,
            'club_name': club_name,
            'event_id': event_id,
            'club_id': club_id,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def send_event_reminder_notification(self, device_tokens: List[str], event_title: str, event_id: str, reminder_time: str):
        """Send reminder notification for upcoming events"""
        if not device_tokens:
            logger.info(f"📱 No device tokens for event reminder notification (event_id: {event_id}) - user notifications disabled")
            return True  # Graceful handling, not a failure
            
        title = "Event Reminder"
        body = f"{event_title} starts {reminder_time}!"
        
        data = {
            'type': 'event_reminder',
            'event_id': event_id,
            'event_title': event_title,
            'reminder_time': reminder_time,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def send_event_comment_notification(self, device_tokens: List[str], event_title: str, commenter_name: str, comment_preview: str, event_id: str):
        """Send notification when someone comments on an event"""
        if not device_tokens:
            logger.info(f"📱 No device tokens for event comment notification (event_id: {event_id}) - user notifications disabled")
            return True  # Graceful handling, not a failure
            
        title = f"New comment on {event_title}"
        body = f"{commenter_name}: {comment_preview}"
        
        data = {
            'type': 'event_comment',
            'event_id': event_id,
            'event_title': event_title,
            'commenter_name': commenter_name,
            'comment_preview': comment_preview,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def send_event_cancelled_notification(self, device_tokens: List[str], event_title: str, event_id: str):
        """Send notification when an event is cancelled"""
        if not device_tokens:
            logger.info(f"📱 No device tokens for event cancelled notification (event_id: {event_id}) - user notifications disabled")
            return True  # Graceful handling, not a failure
            
        title = "Event Cancelled"
        body = f"{event_title} has been cancelled"
        
        data = {
            'type': 'event_cancelled',
            'event_id': event_id,
            'event_title': event_title,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def notify_stuck_session(self, user_id, session_id):
        """Send stuck session notification using unified notification manager"""
        from .notification_manager import notification_manager
        
        logger.info(f"🔔 UNIFIED NOTIFICATION: Sending stuck session notification to user {user_id}")
        result = notification_manager.send_stuck_session_notification(
            recipient_id=user_id,
            session_id=session_id
        )
        logger.info(f"🔔 UNIFIED NOTIFICATION: Stuck session notification result: {result}")
        return result

    def send_app_update_notification(self, device_tokens: List[str], version: str, is_critical: bool = False):
        """Send app update notification to users"""
        if is_critical:
            title = "🚨 Critical App Update Available"
            body = f"Update to v{version} now for important GPS tracking fixes. Please go to the App Store to update."
            notification_data = {
                'type': 'critical_app_update',
                'version': version,
                'action': 'open_app_store',
                'priority': 'high'
            }
        else:
            title = "📱 App Update Available"
            body = f"Version {version} is now available with new features and improvements. Tap to update."
            notification_data = {
                'type': 'app_update',
                'version': version,
                'action': 'open_app_store',
                'priority': 'normal'
            }
        
        logger.info(f"🔔 Sending {'CRITICAL' if is_critical else 'NORMAL'} app update notification for v{version} to {len(device_tokens)} devices")
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=notification_data
        )


# Helper function to get user device tokens
def get_user_device_tokens(user_ids: List[str]) -> List[str]:
    """
    Get FCM device tokens for given user IDs
    
    Args:
        user_ids: List of user IDs
        
    Returns:
        List of FCM device tokens
    """
    if not user_ids:
        logger.warning("🔍 get_user_device_tokens called with empty user_ids list")
        return []
    
    logger.info(f"🔍 DEVICE TOKEN LOOKUP START - Searching for {len(user_ids)} users")
    logger.info(f"🔍 User IDs: {user_ids}")
    
    try:
        from RuckTracker.supabase_client import get_supabase_admin_client
        
        admin_client = get_supabase_admin_client()
        logger.info(f"🔍 Supabase admin client initialized successfully")
        
        # Query user_device_tokens table
        logger.info(f"🔍 Querying user_device_tokens table...")
        response = admin_client.table('user_device_tokens') \
            .select('fcm_token, user_id, device_id, is_active, created_at, updated_at') \
            .in_('user_id', user_ids) \
            .eq('is_active', True) \
            .not_.is_('fcm_token', 'null') \
            .execute()
            
        logger.info(f"🔍 Raw query response: {response}")
        logger.info(f"🔍 Query returned {len(response.data) if response.data else 0} records")
        
        if response.data:
            logger.info(f"🔍 Detailed token records:")
            for i, record in enumerate(response.data):
                logger.info(f"   {i+1}. User: {record.get('user_id')}, Device: {record.get('device_id')}, Active: {record.get('is_active')}, Token: {record.get('fcm_token', 'null')[:30]}...")
            
            # Extract unique valid tokens
            tokens = list(set(item.get('fcm_token') for item in response.data if item.get('fcm_token') and item.get('fcm_token').strip()))

            active_tokens = len(tokens)
            total_records = len(response.data)
            
            logger.info(f"📊 DEVICE TOKEN SUMMARY:")
            logger.info(f"   📱 Total records: {total_records}")
            logger.info(f"   ✅ Valid tokens extracted: {active_tokens}")
            logger.info(f"   🎯 Users requested: {len(user_ids)}")
            logger.info(f"   📈 Token success rate: {(active_tokens/len(user_ids))*100:.1f}%")
            
            if active_tokens == 0:
                logger.info(f"📱 No valid FCM tokens found for users {user_ids} - notifications likely disabled")
                logger.debug(f"📋 All records returned: {response.data}")
            
            return tokens
        else:
            logger.info(f"📱 No device token records found for users: {user_ids}")
            
            # Let's check if these users exist at all
            user_check = admin_client.table('user').select('id, username').in_('id', user_ids).execute()
            if user_check.data:
                logger.info(f"✅ Users exist but have no device tokens registered (notifications disabled)")
                logger.debug(f"📋 Users: {[(u['id'], u.get('username')) for u in user_check.data]}")
            else:
                logger.warning(f"⚠️ Users don't exist in user table: {user_ids}")
            
            return []
            
    except Exception as e:
        logger.error(f"❌ CRITICAL: Failed to get device tokens for users {user_ids}: {e}", exc_info=True)
        return []
