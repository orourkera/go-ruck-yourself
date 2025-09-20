"""
Background job system for delayed retention notifications
Handles Session 1→2 conversion reminders and other time-delayed retention notifications
"""
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from .notification_manager import notification_manager
from ..supabase_client import get_supabase_admin_client

logger = logging.getLogger(__name__)

class RetentionBackgroundJobs:
    """Background job processor for retention notifications"""
    
    def __init__(self):
        self.admin_client = get_supabase_admin_client()
    
    def schedule_session_1_to_2_reminders(self, user_id: str, session_1_completed_at: datetime) -> bool:
        """
        Schedule Session 1→2 conversion reminders for 24h and 48h after first session
        """
        try:
            logger.info(f"🎯 RETENTION: Scheduling Session 1→2 reminders for user {user_id}")
            
            # Schedule Day 1 reminder (24 hours after first session)
            day_1_time = session_1_completed_at + timedelta(hours=24)
            self._schedule_delayed_notification(
                user_id=user_id,
                notification_type='session_1_to_2_day1',
                scheduled_time=day_1_time,
                context={'days_since_first': 1}
            )
            
            # Schedule Day 2 reminder (48 hours after first session)
            day_2_time = session_1_completed_at + timedelta(hours=48)
            self._schedule_delayed_notification(
                user_id=user_id,
                notification_type='session_1_to_2_day2',
                scheduled_time=day_2_time,
                context={'days_since_first': 2}
            )
            
            logger.info(f"✅ Scheduled Session 1→2 reminders for user {user_id}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error scheduling Session 1→2 reminders: {e}", exc_info=True)
            return False
    
    def _schedule_delayed_notification(self, user_id: str, notification_type: str, 
                                     scheduled_time: datetime, context: Dict[str, Any]) -> bool:
        """
        Schedule a delayed notification by storing it in the database
        """
        try:
            notification_record = {
                'user_id': user_id,
                'notification_type': notification_type,
                'scheduled_time': scheduled_time.isoformat(),
                'context': context,
                'status': 'scheduled',
                'created_at': datetime.utcnow().isoformat()
            }
            
            # Store in notifications table with special retention data
            db_record = {
                'recipient_id': user_id,
                'type': f'retention_scheduled_{notification_type}',
                'message': f'Scheduled {notification_type} notification',
                'data': {
                    'is_scheduled_retention': True,
                    'notification_type': notification_type,
                    'scheduled_time': scheduled_time.isoformat(),
                    'context': context,
                    'status': 'scheduled'
                },
                'is_read': False,
                'created_at': datetime.utcnow().isoformat()
            }
            
            response = self.admin_client.table('notifications').insert(db_record).execute()
            
            if hasattr(response, 'error') and response.error:
                logger.error(f"Failed to schedule delayed notification: {response.error}")
                return False
            
            logger.info(f"📅 Scheduled {notification_type} for user {user_id} at {scheduled_time}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error scheduling delayed notification: {e}", exc_info=True)
            return False
    
    def process_scheduled_notifications(self) -> int:
        """
        Process scheduled retention notifications that are due to be sent
        Should be called by a cron job or background task every 15 minutes

        Returns:
            int: Number of notifications processed (including skipped ones)
        """
        try:
            logger.info("🔄 Processing scheduled retention notifications")
            
            current_time = datetime.utcnow()
            
            # Get scheduled notifications that are due
            response = self.admin_client.table('notifications').select(
                'id, recipient_id, type, data'
            ).eq('is_read', False).contains('data', {'is_scheduled_retention': True}).execute()
            
            if not response.data:
                logger.info("📭 No scheduled retention notifications found")
                return 0
            
            processed_count = 0
            sent_count = 0
            
            for notification in response.data:
                try:
                    data = notification.get('data', {})
                    scheduled_time_str = data.get('scheduled_time')
                    status = data.get('status', 'unknown')
                    
                    if status != 'scheduled':
                        continue
                    
                    if not scheduled_time_str:
                        continue
                    
                    scheduled_time = datetime.fromisoformat(scheduled_time_str.replace('Z', '+00:00'))
                    
                    # Check if notification is due
                    if scheduled_time <= current_time:
                        user_id = notification['recipient_id']
                        notification_type = data.get('notification_type')
                        context = data.get('context', {})
                        
                        # Check if user has completed session 2 already (skip reminder if they have)
                        if notification_type in ['session_1_to_2_day1', 'session_1_to_2_day2']:
                            session_count_resp = self.admin_client.table('ruck_session').select(
                                'id', count='exact'
                            ).eq('user_id', user_id).eq('status', 'completed').execute()
                            
                            session_count = getattr(session_count_resp, 'count', 0) or len(session_count_resp.data or [])
                            
                            if session_count >= 2:
                                logger.info(f"📊 User {user_id} already has {session_count} sessions, skipping {notification_type}")
                                # Mark as processed but not sent
                                self._mark_notification_processed(notification['id'], 'skipped_user_progressed')
                                processed_count += 1
                                continue
                        
                        # Send the notification
                        success = self._send_scheduled_retention_notification(
                            user_id, notification_type, context
                        )
                        
                        if success:
                            self._mark_notification_processed(notification['id'], 'sent')
                            sent_count += 1
                        else:
                            self._mark_notification_processed(notification['id'], 'failed')
                        
                        processed_count += 1
                        
                except Exception as notification_err:
                    logger.error(f"❌ Error processing notification {notification.get('id')}: {notification_err}")
                    continue
            
            logger.info(f"✅ Processed {processed_count} scheduled notifications, sent {sent_count}")
            return processed_count
            
        except Exception as e:
            logger.error(f"❌ Error processing scheduled notifications: {e}", exc_info=True)
            return 0
    
    def _send_scheduled_retention_notification(self, user_id: str, notification_type: str, context: Dict[str, Any]) -> bool:
        """
        Send a scheduled retention notification using the notification manager
        """
        try:
            if notification_type == 'session_1_to_2_day1':
                return notification_manager.send_session_1_to_2_reminder_notification(user_id, 1)
            elif notification_type == 'session_1_to_2_day2':
                return notification_manager.send_session_1_to_2_reminder_notification(user_id, 2)
            else:
                logger.error(f"Unknown scheduled notification type: {notification_type}")
                return False
                
        except Exception as e:
            logger.error(f"❌ Error sending scheduled retention notification: {e}", exc_info=True)
            return False
    
    def _mark_notification_processed(self, notification_id: str, status: str) -> bool:
        """
        Mark a scheduled notification as processed
        """
        try:
            # Update the notification data to mark as processed
            update_data = {
                'is_read': True,
                'read_at': datetime.utcnow().isoformat()
            }
            
            response = self.admin_client.table('notifications').update(update_data).eq('id', notification_id).execute()
            
            if hasattr(response, 'error') and response.error:
                logger.error(f"Failed to mark notification as processed: {response.error}")
                return False
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Error marking notification as processed: {e}", exc_info=True)
            return False
    
    def cancel_scheduled_notifications(self, user_id: str, notification_types: List[str]) -> bool:
        """
        Cancel scheduled notifications for a user (e.g., when they complete session 2)
        """
        try:
            logger.info(f"📅 Cancelling scheduled notifications for user {user_id}: {notification_types}")
            
            # Mark scheduled notifications as read/cancelled
            for notification_type in notification_types:
                response = self.admin_client.table('notifications').update({
                    'is_read': True,
                    'read_at': datetime.utcnow().isoformat()
                }).eq('recipient_id', user_id).eq('type', f'retention_scheduled_{notification_type}').eq('is_read', False).execute()
                
                if hasattr(response, 'error') and response.error:
                    logger.error(f"Failed to cancel {notification_type} notifications: {response.error}")
                else:
                    cancelled_count = len(response.data) if response.data else 0
                    logger.info(f"📅 Cancelled {cancelled_count} {notification_type} notifications for user {user_id}")
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Error cancelling scheduled notifications: {e}", exc_info=True)
            return False


# Create singleton instance
retention_background_jobs = RetentionBackgroundJobs()
