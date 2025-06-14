"""
Push notification service using Firebase Cloud Messaging (FCM)
"""
import json
import logging
import os
import requests
from typing import List, Dict, Any
import time
from google.auth.transport.requests import Request
from google.oauth2 import service_account

logger = logging.getLogger(__name__)

class PushNotificationService:
    """Service for sending push notifications via Firebase Cloud Messaging"""
    
    def __init__(self):
        """
        Initialize FCM service using service account authentication
        """
        self.project_id = os.getenv('FIREBASE_PROJECT_ID')
        self.service_account_path = os.getenv('FIREBASE_SERVICE_ACCOUNT_PATH')
        self.service_account_json = os.getenv('FIREBASE_SERVICE_ACCOUNT_JSON')
        self.fcm_url = f"https://fcm.googleapis.com/v1/projects/{self.project_id}/messages:send"
        self._access_token = None
        self._token_expiry = 0
        
        if not self.project_id:
            logger.error("FIREBASE_PROJECT_ID environment variable not set")
        if not self.service_account_path and not self.service_account_json:
            logger.error("Either FIREBASE_SERVICE_ACCOUNT_PATH or FIREBASE_SERVICE_ACCOUNT_JSON environment variable must be set")
    
    def _get_access_token(self) -> str:
        """Get OAuth2 access token for Firebase V1 API"""
        # Check if we have a valid cached token
        if self._access_token and time.time() < self._token_expiry:
            return self._access_token
            
        try:
            # Load service account credentials
            if self.service_account_path:
                credentials = service_account.Credentials.from_service_account_file(
                    self.service_account_path,
                    scopes=['https://www.googleapis.com/auth/firebase.messaging']
                )
            elif self.service_account_json:
                credentials = service_account.Credentials.from_service_account_info(
                    json.loads(self.service_account_json),
                    scopes=['https://www.googleapis.com/auth/firebase.messaging']
                )
            else:
                logger.error("No Firebase service account credentials configured")
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
            notification_data: Additional data payload
            
        Returns:
            bool: True if all successful, False otherwise
        """
        if not device_tokens:
            logger.warning("No device tokens provided")
            return False
            
        if not self.project_id:
            logger.error("FIREBASE_PROJECT_ID environment variable not set")
            return False
            
        access_token = self._get_access_token()
        if not access_token:
            logger.error("Failed to get Firebase access token")
            return False
            
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json'
        }
        
        # Default data if none provided
        if notification_data is None:
            notification_data = {}
        
        success_count = 0
        failure_count = 0
        
        # V1 API requires individual requests for each token
        for token in device_tokens:
            payload = {
                'message': {
                    'token': token,
                    'notification': {
                        'title': title,
                        'body': body
                    },
                    'data': {k: str(v) for k, v in notification_data.items()},
                    'apns': {
                        'headers': {
                            'apns-priority': '10'
                        },
                        'payload': {
                            'aps': {
                                'sound': 'default',
                                'badge': 1
                            }
                        }
                    },
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'sound': 'default',
                            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                        }
                    }
                }
            }
            
            try:
                response = requests.post(
                    self.fcm_url,
                    headers=headers,
                    json=payload,
                    timeout=10
                )
                
                if response.status_code == 200:
                    success_count += 1
                    logger.debug(f"Successfully sent notification to token: {token[:10]}...")
                else:
                    failure_count += 1
                    logger.error(f"FCM API error for token {token[:10]}...: {response.status_code} - {response.text}")
                    
            except Exception as e:
                failure_count += 1
                logger.error(f"Failed to send FCM notification to token {token[:10]}...: {e}")
        
        logger.info(f"FCM notification batch complete: {success_count} successful, {failure_count} failed")
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
        if not achievement_names:
            return False
        
        count = len(achievement_names)
        
        if count == 1:
            title = "Achievement Unlocked! 🏆"
            body = f"Congratulations! You've earned '{achievement_names[0]}'"
        else:
            title = f"{count} Achievements Unlocked! 🏆"
            if count == 2:
                body = f"Congratulations! You've earned '{achievement_names[0]}' and '{achievement_names[1]}'"
            else:
                body = f"Congratulations! You've earned {count} new achievements including '{achievement_names[0]}'"
        
        data = {
            'type': 'achievement_earned',
            'achievement_names': achievement_names,
            'achievement_count': count,
            'session_id': session_id,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
        }
        
        return self.send_notification(
            device_tokens=device_tokens,
            title=title,
            body=body,
            notification_data=data
        )

    def send_club_join_request_notification(self, device_tokens: List[str], requester_name: str, club_name: str, club_id: str):
        """Send notification when someone requests to join a club"""
        try:
            if not device_tokens:
                return
                
            payload = {
                'message': {
                    'token': device_tokens[0],
                    'notification': {
                        'title': "New Club Join Request",
                        'body': f"{requester_name} wants to join {club_name}"
                    },
                    'data': {
                        'type': 'club_join_request',
                        'club_id': club_id,
                        'requester_name': requester_name,
                        'club_name': club_name
                    },
                    'apns': {
                        'headers': {
                            'apns-priority': '10'
                        },
                        'payload': {
                            'aps': {
                                'sound': 'default',
                                'badge': 1
                            }
                        }
                    },
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'sound': 'default',
                            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                        }
                    }
                }
            }
            
            access_token = self._get_access_token()
            if not access_token:
                logger.error("Failed to get Firebase access token")
                return False
            
            headers = {
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json'
            }
            
            response = requests.post(
                self.fcm_url,
                headers=headers,
                json=payload,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info(f"Club join request notification sent to {len(device_tokens)} devices. Success: 1, Failures: 0")
            else:
                logger.error(f"FCM API error for token {device_tokens[0][:10]}...: {response.status_code} - {response.text}")
                
        except Exception as e:
            logger.error(f"Error sending club join request notification: {e}")

    def send_club_membership_approved_notification(self, device_tokens: List[str], club_name: str, club_id: str):
        """Send notification when club membership is approved"""
        try:
            if not device_tokens:
                return
                
            payload = {
                'message': {
                    'token': device_tokens[0],
                    'notification': {
                        'title': "Welcome to the Club!",
                        'body': f"Your request to join {club_name} has been approved"
                    },
                    'data': {
                        'type': 'club_membership_approved',
                        'club_id': club_id,
                        'club_name': club_name
                    },
                    'apns': {
                        'headers': {
                            'apns-priority': '10'
                        },
                        'payload': {
                            'aps': {
                                'sound': 'default',
                                'badge': 1
                            }
                        }
                    },
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'sound': 'default',
                            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                        }
                    }
                }
            }
            
            access_token = self._get_access_token()
            if not access_token:
                logger.error("Failed to get Firebase access token")
                return False
            
            headers = {
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json'
            }
            
            response = requests.post(
                self.fcm_url,
                headers=headers,
                json=payload,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info(f"Club membership approved notification sent to {len(device_tokens)} devices. Success: 1, Failures: 0")
            else:
                logger.error(f"FCM API error for token {device_tokens[0][:10]}...: {response.status_code} - {response.text}")
                
        except Exception as e:
            logger.error(f"Error sending club membership approved notification: {e}")

    def send_club_membership_rejected_notification(self, device_tokens: List[str], club_name: str):
        """Send notification when club membership is rejected"""
        try:
            if not device_tokens:
                return
                
            payload = {
                'message': {
                    'token': device_tokens[0],
                    'notification': {
                        'title': "Club Membership Update",
                        'body': f"Your request to join {club_name} was not approved"
                    },
                    'data': {
                        'type': 'club_membership_rejected',
                        'club_name': club_name
                    },
                    'apns': {
                        'headers': {
                            'apns-priority': '10'
                        },
                        'payload': {
                            'aps': {
                                'sound': 'default',
                                'badge': 1
                            }
                        }
                    },
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'sound': 'default',
                            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                        }
                    }
                }
            }
            
            access_token = self._get_access_token()
            if not access_token:
                logger.error("Failed to get Firebase access token")
                return False
            
            headers = {
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json'
            }
            
            response = requests.post(
                self.fcm_url,
                headers=headers,
                json=payload,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info(f"Club membership rejected notification sent to {len(device_tokens)} devices. Success: 1, Failures: 0")
            else:
                logger.error(f"FCM API error for token {device_tokens[0][:10]}...: {response.status_code} - {response.text}")
                
        except Exception as e:
            logger.error(f"Error sending club membership rejected notification: {e}")

    def send_club_deleted_notification(self, device_tokens: List[str], club_name: str):
        """Send notification when a club is deleted"""
        try:
            if not device_tokens:
                return
                
            payload = {
                'message': {
                    'token': device_tokens[0],
                    'notification': {
                        'title': "Club Disbanded",
                        'body': f"{club_name} has been disbanded by the admin"
                    },
                    'data': {
                        'type': 'club_deleted',
                        'club_name': club_name
                    },
                    'apns': {
                        'headers': {
                            'apns-priority': '10'
                        },
                        'payload': {
                            'aps': {
                                'sound': 'default',
                                'badge': 1
                            }
                        }
                    },
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'sound': 'default',
                            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                        }
                    }
                }
            }
            
            access_token = self._get_access_token()
            if not access_token:
                logger.error("Failed to get Firebase access token")
                return False
            
            headers = {
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json'
            }
            
            response = requests.post(
                self.fcm_url,
                headers=headers,
                json=payload,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info(f"Club deleted notification sent to {len(device_tokens)} devices. Success: 1, Failures: 0")
            else:
                logger.error(f"FCM API error for token {device_tokens[0][:10]}...: {response.status_code} - {response.text}")
                
        except Exception as e:
            logger.error(f"Error sending club deleted notification: {e}")

    def send_club_event_notification(self, device_tokens: List[str], event_title: str, club_name: str, event_id: str, club_id: str):
        """Send notification when a new club event is created"""
        try:
            if not device_tokens:
                return
                
            payload = {
                'message': {
                    'token': device_tokens[0],
                    'notification': {
                        'title': f"New {club_name} Event",
                        'body': f"{event_title} - Check it out!"
                    },
                    'data': {
                        'type': 'club_event_created',
                        'event_id': event_id,
                        'club_id': club_id,
                        'event_title': event_title,
                        'club_name': club_name
                    },
                    'apns': {
                        'headers': {
                            'apns-priority': '10'
                        },
                        'payload': {
                            'aps': {
                                'sound': 'default',
                                'badge': 1
                            }
                        }
                    },
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'sound': 'default',
                            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                        }
                    }
                }
            }
            
            access_token = self._get_access_token()
            if not access_token:
                logger.error("Failed to get Firebase access token")
                return False
            
            headers = {
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json'
            }
            
            response = requests.post(
                self.fcm_url,
                headers=headers,
                json=payload,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info(f"Club event notification sent to {len(device_tokens)} devices. Success: 1, Failures: 0")
            else:
                logger.error(f"FCM API error for token {device_tokens[0][:10]}...: {response.status_code} - {response.text}")
                
        except Exception as e:
            logger.error(f"Error sending club event notification: {e}")

    def send_event_reminder_notification(self, device_tokens: List[str], event_title: str, event_id: str, reminder_time: str):
        """Send reminder notification for upcoming events"""
        try:
            if not device_tokens:
                return
                
            payload = {
                'message': {
                    'token': device_tokens[0],
                    'notification': {
                        'title': f"Event Reminder",
                        'body': f"{event_title} starts {reminder_time}!"
                    },
                    'data': {
                        'type': 'event_reminder',
                        'event_id': event_id,
                        'event_title': event_title,
                        'reminder_time': reminder_time
                    },
                    'apns': {
                        'headers': {
                            'apns-priority': '10'
                        },
                        'payload': {
                            'aps': {
                                'sound': 'default',
                                'badge': 1
                            }
                        }
                    },
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'sound': 'default',
                            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                        }
                    }
                }
            }
            
            access_token = self._get_access_token()
            if not access_token:
                logger.error("Failed to get Firebase access token")
                return False
            
            headers = {
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json'
            }
            
            response = requests.post(
                self.fcm_url,
                headers=headers,
                json=payload,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info(f"Event reminder notification sent to {len(device_tokens)} devices")
            else:
                logger.error(f"FCM API error for reminder notification: {response.status_code} - {response.text}")
                
        except Exception as e:
            logger.error(f"Error sending event reminder notification: {e}")

    def send_event_comment_notification(self, device_tokens: List[str], event_title: str, commenter_name: str, comment_preview: str, event_id: str):
        """Send notification when someone comments on an event"""
        try:
            if not device_tokens:
                return
                
            payload = {
                'message': {
                    'token': device_tokens[0],
                    'notification': {
                        'title': f"New comment on {event_title}",
                        'body': f"{commenter_name}: {comment_preview}"
                    },
                    'data': {
                        'type': 'event_comment',
                        'event_id': event_id,
                        'event_title': event_title,
                        'commenter_name': commenter_name,
                        'comment_preview': comment_preview
                    },
                    'apns': {
                        'headers': {
                            'apns-priority': '10'
                        },
                        'payload': {
                            'aps': {
                                'sound': 'default',
                                'badge': 1
                            }
                        }
                    },
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'sound': 'default',
                            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                        }
                    }
                }
            }
            
            access_token = self._get_access_token()
            if not access_token:
                logger.error("Failed to get Firebase access token")
                return False
            
            headers = {
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json'
            }
            
            response = requests.post(
                self.fcm_url,
                headers=headers,
                json=payload,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info(f"Event comment notification sent to {len(device_tokens)} devices")
            else:
                logger.error(f"FCM API error for comment notification: {response.status_code} - {response.text}")
                
        except Exception as e:
            logger.error(f"Error sending event comment notification: {e}")

    def send_event_cancelled_notification(self, device_tokens: List[str], event_title: str, event_id: str):
        """Send notification when an event is cancelled"""
        try:
            if not device_tokens:
                return
                
            payload = {
                'message': {
                    'token': device_tokens[0],
                    'notification': {
                        'title': f"Event Cancelled",
                        'body': f"{event_title} has been cancelled"
                    },
                    'data': {
                        'type': 'event_cancelled',
                        'event_id': event_id,
                        'event_title': event_title
                    },
                    'apns': {
                        'headers': {
                            'apns-priority': '10'
                        },
                        'payload': {
                            'aps': {
                                'sound': 'default',
                                'badge': 1
                            }
                        }
                    },
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'sound': 'default',
                            'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                        }
                    }
                }
            }
            
            access_token = self._get_access_token()
            if not access_token:
                logger.error("Failed to get Firebase access token")
                return False
            
            headers = {
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json'
            }
            
            response = requests.post(
                self.fcm_url,
                headers=headers,
                json=payload,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info(f"Event cancelled notification sent to {len(device_tokens)} devices")
            else:
                logger.error(f"FCM API error for cancellation notification: {response.status_code} - {response.text}")
                
        except Exception as e:
            logger.error(f"Error sending event cancelled notification: {e}")


# Helper function to get user device tokens
def get_user_device_tokens(user_ids: List[str]) -> List[str]:
    """
    Get FCM device tokens for given user IDs
    
    Args:
        user_ids: List of user IDs
        
    Returns:
        List of FCM device tokens
    """
    try:
        from RuckTracker.supabase_client import get_supabase_admin_client
        
        admin_client = get_supabase_admin_client()
        
        # Query user_device_tokens table
        response = admin_client.table('user_device_tokens') \
            .select('fcm_token') \
            .in_('user_id', user_ids) \
            .not_.is_('fcm_token', 'null') \
            .execute()
            
        if response.data:
            tokens = [item['fcm_token'] for item in response.data if item['fcm_token']]
            logger.info(f"Found {len(tokens)} device tokens for {len(user_ids)} users")
            return tokens
        else:
            logger.warning(f"No device tokens found for users: {user_ids}")
            return []
            
    except Exception as e:
        logger.error(f"Failed to get device tokens: {e}")
        return []
