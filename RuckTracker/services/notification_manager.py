"""
Unified Notification Manager
Handles both database logging and push notifications atomically
"""
import logging
from typing import List, Dict, Any, Optional
from datetime import datetime
from .push_notification_service import PushNotificationService, get_user_device_tokens

logger = logging.getLogger(__name__)

class NotificationManager:
    """Unified service for handling notifications with database logging and push notifications"""
    
    def __init__(self):
        self.push_service = PushNotificationService()
    
    def send_notification(
        self,
        recipients: List[str],
        notification_type: str,
        title: str,
        body: str,
        data: Dict[str, Any] = None,
        save_to_db: bool = True,
        sender_id: Optional[str] = None
    ) -> bool:
        """
        Send unified notification with database logging and push notification
        
        Args:
            recipients: List of user IDs to notify
            notification_type: Type of notification (ruck_like, duel_comment, etc.)
            title: Push notification title
            body: Push notification body and database message
            data: Additional data for notification
            save_to_db: Whether to save to database (default True)
            sender_id: ID of user who triggered notification (optional)
            
        Returns:
            bool: True if successful, False otherwise
        """
        if not recipients:
            logger.info(f"📱 No recipients for {notification_type} notification")
            return True
        
        logger.info(f"🔔 UNIFIED NOTIFICATION: {notification_type} to {len(recipients)} users")
        logger.info(f"📋 Title: '{title}', Body: '{body}'")
        
        success = True
        
        try:
            # 1. Save to database FIRST (atomic operation)
            if save_to_db:
                success &= self._save_to_database(
                    recipients=recipients,
                    notification_type=notification_type,
                    message=body,
                    data=data or {},
                    sender_id=sender_id
                )
            
            # 2. Send push notifications 
            success &= self._send_push_notifications(
                recipients=recipients,
                title=title,
                body=body,
                notification_type=notification_type,
                data=data or {}
            )
            
        except Exception as e:
            logger.error(f"❌ Unified notification failed for {notification_type}: {e}", exc_info=True)
            return False
        
        logger.info(f"✅ Unified notification {notification_type} completed, success: {success}")
        return success
    
    def _save_to_database(
        self, 
        recipients: List[str], 
        notification_type: str, 
        message: str, 
        data: Dict[str, Any],
        sender_id: Optional[str]
    ) -> bool:
        """Save notifications to database"""
        try:
            from RuckTracker.supabase_client import get_supabase_admin_client
            
            admin_client = get_supabase_admin_client()
            
            # Prepare database records
            db_notifications = []
            for recipient_id in recipients:
                notification_record = {
                    'recipient_id': recipient_id,
                    'type': notification_type,
                    'message': message,
                    'data': data,
                    'is_read': False,
                    'created_at': datetime.utcnow().isoformat()
                }
                
                # Add sender_id if provided
                if sender_id:
                    notification_record['sender_id'] = sender_id
                
                # Add contextual IDs from data for better querying
                if 'ruck_id' in data:
                    notification_record['data'] = {**data, 'ruck_id': data['ruck_id']}
                if 'duel_id' in data:
                    notification_record['duel_id'] = data['duel_id']
                if 'event_id' in data:
                    notification_record['event_id'] = data['event_id']
                if 'club_id' in data:
                    notification_record['club_id'] = data['club_id']
                
                db_notifications.append(notification_record)
            
            # Insert to database
            logger.info(f"💾 Saving {len(db_notifications)} notifications to database")
            response = admin_client.table('notifications').insert(db_notifications).execute()
            
            if hasattr(response, 'error') and response.error:
                logger.error(f"❌ Database insert failed: {response.error}")
                return False
            
            logger.info(f"✅ Successfully saved {len(db_notifications)} notifications to database")
            return True
            
        except Exception as e:
            logger.error(f"❌ Database save failed: {e}", exc_info=True)
            return False
    
    def _send_push_notifications(
        self,
        recipients: List[str],
        title: str,
        body: str,
        notification_type: str,
        data: Dict[str, Any]
    ) -> bool:
        """Send push notifications"""
        try:
            # Get device tokens
            device_tokens = get_user_device_tokens(recipients)
            
            if not device_tokens:
                logger.info(f"📱 No device tokens for {notification_type} - users have notifications disabled")
                return True  # Not a failure
            
            # Add notification type to data
            push_data = {**data, 'type': notification_type}
            
            # Send push notification
            logger.info(f"📱 Sending push notifications to {len(device_tokens)} devices")
            result = self.push_service.send_notification(
                device_tokens=device_tokens,
                title=title,
                body=body,
                notification_data=push_data
            )
            
            logger.info(f"📱 Push notification result: {result}")
            return result
            
        except Exception as e:
            logger.error(f"❌ Push notification failed: {e}", exc_info=True)
            return False

    # Convenience methods for specific notification types
    def send_ruck_like_notification(self, recipient_id: str, liker_name: str, ruck_id: str, liker_id: str) -> bool:
        """Send ruck like notification with unified logging"""
        return self.send_notification(
            recipients=[recipient_id],
            notification_type='ruck_like',
            title='New Like',
            body=f'{liker_name} liked your ruck!',
            data={
                'ruck_id': ruck_id,
                'liker_id': liker_id,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            },
            sender_id=liker_id
        )
    
    def send_ruck_comment_notification(self, recipient_id: str, commenter_name: str, ruck_id: str, comment_id: str, commenter_id: str) -> bool:
        """Send ruck comment notification with unified logging"""
        return self.send_notification(
            recipients=[recipient_id],
            notification_type='ruck_comment',
            title='New Comment',
            body=f'{commenter_name} commented on your ruck!',
            data={
                'ruck_id': ruck_id,
                'comment_id': comment_id,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            },
            sender_id=commenter_id
        )
    
    def send_new_follower_notification(self, recipient_id: str, follower_name: str, follower_id: str) -> bool:
        """Send new follower notification with unified logging"""
        return self.send_notification(
            recipients=[recipient_id],
            notification_type='new_follower',
            title='New Follower',
            body=f'{follower_name} started following you',
            data={
                'follower_id': follower_id,
                'follower_name': follower_name,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                'route': '/profile',
                'user_id': follower_id
            },
            sender_id=follower_id
        )
    
    def send_achievement_notification(self, recipient_id: str, achievement_names: List[str], session_id: str) -> bool:
        """Send achievement notification with unified logging"""
        if len(achievement_names) == 1:
            title = '🏆 Achievement Unlocked!'
            body = f'You earned: {achievement_names[0]}'
        else:
            title = f'🏆 {len(achievement_names)} Achievements Unlocked!'
            body = f'You earned: {", ".join(achievement_names[:2])}' + (f' and {len(achievement_names)-2} more!' if len(achievement_names) > 2 else '')
        
        return self.send_notification(
            recipients=[recipient_id],
            notification_type='achievement',
            title=title,
            body=body,
            data={
                'session_id': session_id,
                'achievement_count': str(len(achievement_names)),
                'achievement_names': ','.join(achievement_names)
            }
        )
    
    def send_ruck_started_notification(self, recipients: List[str], rucker_name: str, ruck_id: str, rucker_id: str) -> bool:
        """Send ruck started notification with unified logging"""
        return self.send_notification(
            recipients=recipients,
            notification_type='ruck_started',
            title='🎒 Ruck Started!',
            body=f'{rucker_name} started rucking',
            data={
                'ruck_id': ruck_id,
                'rucker_name': rucker_name
            },
            sender_id=rucker_id
        )
    
    def send_club_join_request_notification(self, recipients: List[str], requester_name: str, club_name: str, club_id: str, requester_id: str) -> bool:
        """Send club join request notification with unified logging"""
        return self.send_notification(
            recipients=recipients,
            notification_type='club_join_request',
            title='New Club Join Request',
            body=f'{requester_name} wants to join {club_name}',
            data={
                'requester_name': requester_name,
                'club_name': club_name,
                'club_id': club_id,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            },
            sender_id=requester_id
        )
    
    def send_club_membership_approved_notification(self, recipient_id: str, club_name: str, club_id: str, approver_id: str = None) -> bool:
        """Send club membership approved notification with unified logging"""
        return self.send_notification(
            recipients=[recipient_id],
            notification_type='club_membership_approved',
            title='Welcome to the Club!',
            body=f'Your request to join {club_name} has been approved',
            data={
                'club_name': club_name,
                'club_id': club_id,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            },
            sender_id=approver_id
        )
    
    def send_club_membership_rejected_notification(self, recipient_id: str, club_name: str, rejector_id: str = None) -> bool:
        """Send club membership rejected notification with unified logging"""
        return self.send_notification(
            recipients=[recipient_id],
            notification_type='club_membership_rejected',
            title='Club Membership Update',
            body=f'Your request to join {club_name} was not approved',
            data={
                'club_name': club_name,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            },
            sender_id=rejector_id
        )
    
    def send_stuck_session_notification(self, recipient_id: str, session_id: str) -> bool:
        """Send stuck session notification with unified logging"""
        return self.send_notification(
            recipients=[recipient_id],
            notification_type='stuck_session',
            title='Active Ruck Session',
            body='Your ruck session is still running! Open the app to continue or complete it.',
            data={
                'session_id': session_id,
                'type': 'stuck_session'
            }
        )
    
    def send_ruck_participant_activity_notification(self, recipients: List[str], actor_name: str, ruck_id: str, activity_type: str, actor_id: str) -> bool:
        """Send ruck participant activity notification with unified logging"""
        if activity_type not in ("like", "comment"):
            activity_type = "activity"
        
        verb = "liked" if activity_type == "like" else ("commented on" if activity_type == "comment" else "updated")
        
        return self.send_notification(
            recipients=recipients,
            notification_type='ruck_activity',
            title='New activity on a ruck',
            body=f'{actor_name} {verb} a ruck you interacted with',
            data={
                'activity': activity_type,
                'ruck_id': ruck_id,
                'actor_name': actor_name,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            },
            sender_id=actor_id
        )


# Create singleton instance
notification_manager = NotificationManager()