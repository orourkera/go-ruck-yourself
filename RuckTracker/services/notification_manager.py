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

    # AI-Personalized Retention Notifications
    def send_session_1_celebration_notification(self, recipient_id: str, session_data: Dict[str, Any]) -> bool:
        """Send AI-personalized Session 1 celebration notification"""
        user_profile = self._get_user_coaching_profile(recipient_id)
        coaching_tone = user_profile.get('coaching_tone', 'supportive_friend')
        
        content = self._get_retention_notification_content('session_1_celebration', coaching_tone, session_data)
        
        return self.send_notification(
            recipients=[recipient_id],
            notification_type='retention_session_1_celebration',
            title=content['title'],
            body=content['body'],
            data={
                'retention_type': 'session_1_celebration',
                'session_data': session_data,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            }
        )
    
    def send_session_1_to_2_reminder_notification(self, recipient_id: str, days_since_first: int) -> bool:
        """Send AI-personalized Session 1→2 conversion reminder"""
        user_profile = self._get_user_coaching_profile(recipient_id)
        coaching_tone = user_profile.get('coaching_tone')
        
        notification_type = f'session_1_to_2_day{days_since_first}'
        
        # If user has no coaching tone set, generate AI-personalized content
        if not coaching_tone:
            content = self._generate_ai_retention_notification(recipient_id, notification_type, {'days_since_first': days_since_first})
        else:
            # Use predefined templates for users with coaching tone preference
            content = self._get_retention_notification_content(notification_type, coaching_tone, {'days_since_first': days_since_first})
        
        return self.send_notification(
            recipients=[recipient_id],
            notification_type=f'retention_{notification_type}',
            title=content['title'],
            body=content['body'],
            data={
                'retention_type': notification_type,
                'days_since_first': days_since_first,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            }
        )

    def send_new_user_activation_notification(self, recipient_id: str, hours_since_signup: int, context: Dict[str, Any]) -> bool:
        """Send push to new users who haven't completed their first ruck."""
        tone = self._get_user_coaching_profile(recipient_id).get('coaching_tone')
        notification_type = f'new_user_day{1 if hours_since_signup < 48 else 3}'

        payload_context = {
            'hours_since_signup': hours_since_signup,
            'timezone': context.get('timezone'),
            'prefer_metric': context.get('prefer_metric', True),
            'target': 'first_ruck'
        }

        if tone:
            content = self._get_retention_notification_content(notification_type, tone, payload_context)
        else:
            payload_context.update(context)
            content = self._generate_ai_retention_notification(recipient_id, notification_type, payload_context)

        return self.send_notification(
            recipients=[recipient_id],
            notification_type=f'retention_{notification_type}',
            title=content['title'],
            body=content['body'],
            data={
                'retention_type': notification_type,
                'hours_since_signup': hours_since_signup,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            }
        )

    def send_single_ruck_reactivation_notification(
        self,
        recipient_id: str,
        days_since_last: int,
        context: Dict[str, Any]
    ) -> bool:
        """Send push to users who completed exactly one ruck and lapsed."""
        tone = self._get_user_coaching_profile(recipient_id).get('coaching_tone')
        notification_type = 'single_ruck_day7'

        payload_context = {
            'days_since_last': days_since_last,
            'last_ruck': context.get('last_ruck'),
            'current_weather': context.get('current_weather'),
            'target': 'second_ruck'
        }

        if tone:
            content = self._get_retention_notification_content(notification_type, tone, payload_context)
        else:
            content = self._generate_ai_retention_notification(recipient_id, notification_type, payload_context)

        return self.send_notification(
            recipients=[recipient_id],
            notification_type=f'retention_{notification_type}',
            title=content['title'],
            body=content['body'],
            data={
                'retention_type': notification_type,
                'days_since_last': days_since_last,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            }
        )

    def send_session_2_celebration_notification(self, recipient_id: str, session_data: Dict[str, Any]) -> bool:
        """Send AI-personalized Session 2 celebration notification"""
        user_profile = self._get_user_coaching_profile(recipient_id)
        coaching_tone = user_profile.get('coaching_tone', 'supportive_friend')
        
        content = self._get_retention_notification_content('session_2_celebration', coaching_tone, session_data)
        
        return self.send_notification(
            recipients=[recipient_id],
            notification_type='retention_session_2_celebration',
            title=content['title'],
            body=content['body'],
            data={
                'retention_type': 'session_2_celebration',
                'session_data': session_data,
                'next_goal': 'first_week_sprint',
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            }
        )
    
    def send_first_week_sprint_notification(self, recipient_id: str, session_count: int, notification_subtype: str) -> bool:
        """Send AI-personalized first week sprint notifications"""
        user_profile = self._get_user_coaching_profile(recipient_id)
        coaching_tone = user_profile.get('coaching_tone', 'supportive_friend')
        
        content = self._get_retention_notification_content(notification_subtype, coaching_tone, {'session_count': session_count})
        
        return self.send_notification(
            recipients=[recipient_id],
            notification_type=f'retention_{notification_subtype}',
            title=content['title'],
            body=content['body'],
            data={
                'retention_type': notification_subtype,
                'session_count': session_count,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            }
        )
    
    def send_road_to_7_complete_notification(self, recipient_id: str) -> bool:
        """Send AI-personalized Road to 7 completion notification"""
        user_profile = self._get_user_coaching_profile(recipient_id)
        coaching_tone = user_profile.get('coaching_tone', 'supportive_friend')
        
        content = self._get_retention_notification_content('road_to_7_complete', coaching_tone, {})
        
        return self.send_notification(
            recipients=[recipient_id],
            notification_type='retention_road_to_7_complete',
            title=content['title'],
            body=content['body'],
            data={
                'retention_type': 'road_to_7_complete',
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            }
        )
    
    def _generate_ai_retention_notification(self, user_id: str, notification_type: str, context: Dict[str, Any]) -> Dict[str, str]:
        """Generate AI-personalized retention notification using user insights and current context"""
        try:
            from ..supabase_client import get_supabase_admin_client
            import requests
            import json
            import os
            
            # Get user insights (last ruck data)
            supabase = get_supabase_admin_client()
            
            # Fetch user's last ruck session for context
            last_ruck_resp = supabase.table('ruck_session').select(
                'completed_at, distance_km, duration_seconds, calories_burned, weather_conditions, location_name'
            ).eq('user_id', user_id).eq('status', 'completed').order('completed_at', desc=True).limit(1).execute()
            
            last_ruck = last_ruck_resp.data[0] if last_ruck_resp.data else None
            
            # Get current weather for user's location (if available)
            current_weather = self._get_current_weather_for_user(user_id)
            
            # Build context for AI
            ai_context = {
                'notification_type': notification_type,
                'days_since_first': context.get('days_since_first', 1),
                'last_ruck': last_ruck,
                'current_weather': current_weather,
                'user_id': user_id
            }
            
            # Generate AI content using OpenAI
            content = self._call_openai_for_retention_notification(ai_context)
            
            if content:
                return content
            else:
                # Fallback to default supportive_friend tone if AI fails
                return self._get_retention_notification_content(notification_type, 'supportive_friend', context)
                
        except Exception as e:
            logger.error(f"Error generating AI retention notification: {e}")
            # Fallback to default supportive_friend tone
            return self._get_retention_notification_content(notification_type, 'supportive_friend', context)
    
    def _get_current_weather_for_user(self, user_id: str) -> Dict[str, Any]:
        """Get current weather for user's location"""
        try:
            # Get user's last known location or preferred location
            from ..supabase_client import get_supabase_admin_client
            supabase = get_supabase_admin_client()
            
            # Try to get location from last session
            location_resp = supabase.table('ruck_session').select(
                'location_name, weather_conditions'
            ).eq('user_id', user_id).eq('status', 'completed').order('completed_at', desc=True).limit(1).execute()
            
            if location_resp.data and location_resp.data[0].get('location_name'):
                location = location_resp.data[0]['location_name']
                
                # Simple weather API call (you can replace with your preferred weather service)
                import os
                weather_api_key = os.getenv('OPENWEATHER_API_KEY')
                if weather_api_key:
                    import requests
                    weather_url = f"http://api.openweathermap.org/data/2.5/weather?q={location}&appid={weather_api_key}&units=metric"
                    weather_resp = requests.get(weather_url, timeout=5)
                    
                    if weather_resp.status_code == 200:
                        weather_data = weather_resp.json()
                        return {
                            'temperature': weather_data['main']['temp'],
                            'description': weather_data['weather'][0]['description'],
                            'location': location
                        }
            
            return {}
            
        except Exception as e:
            logger.warning(f"Could not fetch weather for user {user_id}: {e}")
            return {}
    
    def _call_openai_for_retention_notification(self, context: Dict[str, Any]) -> Dict[str, str]:
        """Call OpenAI to generate personalized retention notification"""
        try:
            import openai
            import os
            import json
            
            openai_api_key = os.getenv('OPENAI_API_KEY')
            if not openai_api_key:
                logger.warning("OpenAI API key not configured")
                return None
            
            client = openai.OpenAI(api_key=openai_api_key)
            
            # Build prompt based on notification type
            if context['notification_type'] == 'session_1_to_2_day1':
                system_prompt = """You are a motivational rucking coach generating a push notification to encourage someone to complete their second ruck session. They completed their first ruck 24 hours ago and need encouragement to continue their journey.

Generate a push notification with:
- A compelling title (max 50 characters)
- An encouraging body message (max 120 characters)
- Reference their last ruck performance if available
- Include weather context if provided
- Be motivational but not pushy
- Focus on momentum and the fact that session 2 is often easier than session 1

Return JSON format: {"title": "...", "body": "..."}"""
            
            elif context['notification_type'] == 'session_1_to_2_day2':
                system_prompt = """You are a motivational rucking coach generating a push notification to encourage someone to complete their second ruck session. They completed their first ruck 48 hours ago and are at risk of losing momentum.

Generate a push notification with:
- An urgent but supportive title (max 50 characters)
- A motivating body message (max 120 characters)
- Reference their last ruck performance if available
- Include weather context if provided
- Emphasize the importance of not losing momentum
- Make it feel achievable and worthwhile

Return JSON format: {"title": "...", "body": "..."}"""
            
            elif context['notification_type'] == 'session_1_to_2_day2':
                system_prompt = """You are a motivational rucking coach generating a push notification to encourage someone to complete their second ruck session. They completed their first ruck 48 hours ago and are at risk of losing momentum.

Generate a push notification with:
- An urgent but supportive title (max 50 characters)
- A motivating body message (max 120 characters)
- Reference their last ruck performance if available
- Include weather context if provided
- Emphasize the importance of not losing momentum
- Make it feel achievable and worthwhile

Return JSON format: {"title": "...", "body": "..."}"""

            elif context['notification_type'] == 'new_user_day1':
                system_prompt = """You are a world-class onboarding coach for a rucking app. A user created an account about 24 hours ago but hasn't logged a first ruck yet.

Generate a push notification with:
- Inspiring title < 50 characters that sparks action.
- Supportive, specific body (<120 characters) that removes friction and points to an easy win (e.g., 15-minute first ruck, using gear they already have).
- Incorporate local weather or time-of-day cues when provided.
- Sound fun, confident, and personalized; avoid generic app marketing.
- Include a call-to-action rooted in feelings (e.g., momentum, stress relief, curiosity).

Return JSON format: {"title": "...", "body": "..."}"""

            elif context['notification_type'] == 'new_user_day3':
                system_prompt = """You are a motivational rucking coach. A user signed up ~72 hours ago but still hasn’t completed their first ruck.

Generate a push notification with:
- Empathetic title (<50 characters) acknowledging real-life busyness.
- Body (<120 characters) that offers a specific, low-barrier invitation (e.g., 10-minute walk with backpack) and highlights how they’ll feel afterward.
- If weather/time info exists, weave it in naturally.
- Convey that it’s totally normal to be starting now, and that momentum begins with one short session.
- Deliver a friendly nudge without pressure.

Return JSON format: {"title": "...", "body": "..."}"""

            elif context['notification_type'] == 'single_ruck_day7':
                system_prompt = """You are a motivational rucking coach. A user completed exactly one ruck about 7 days ago and hasn’t logged another.

Generate a push notification with:
- Title (<50 characters) celebrating their first win and hinting at what’s next.
- Body (<120 characters) that references their last ruck stats (distance/time) when available, encourages a quick return, and points to an achievable session.
- If you have weather or location details, incorporate them so the message feels timely.
- Emphasize that session #2 is where real momentum builds.
- Keep tone positive, personal, and action-oriented.

Return JSON format: {"title": "...", "body": "..."}"""

            else:
                return None

            # Build user prompt with context
            user_prompt_parts = [f"Generate a retention notification for: {context['notification_type']}"]
            
            if context.get('last_ruck'):
                last_ruck = context['last_ruck']
                distance = last_ruck.get('distance_km', 0)
                duration_mins = (last_ruck.get('duration_seconds', 0) // 60)
                user_prompt_parts.append(f"Their last ruck: {distance:.1f}km in {duration_mins} minutes")
                
                if last_ruck.get('location_name'):
                    user_prompt_parts.append(f"Location: {last_ruck['location_name']}")
            
            if context.get('current_weather'):
                weather = context['current_weather']
                user_prompt_parts.append(f"Current weather: {weather.get('temperature', 'N/A')}°C, {weather.get('description', 'N/A')}")

            if context.get('hours_since_signup'):
                user_prompt_parts.append(f"Hours since signup: {context['hours_since_signup']}")

            user_prompt = "\n".join(user_prompt_parts)

            response = client.chat.completions.create(
                model=os.getenv('OPENAI_RETENTION_MODEL', os.getenv('OPENAI_DEFAULT_MODEL', 'gpt-5')),
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                max_tokens=150,
                temperature=0.7
            )
            
            content = response.choices[0].message.content.strip()
            
            # Parse JSON response
            try:
                parsed_content = json.loads(content)
                if 'title' in parsed_content and 'body' in parsed_content:
                    return parsed_content
            except json.JSONDecodeError:
                logger.error(f"Failed to parse OpenAI JSON response: {content}")
            
            return None
            
        except Exception as e:
            logger.error(f"OpenAI API call failed: {e}")
            return None

    def generate_ai_plan_notification(self, user_id: str, notification_type: str, tone: str, context: Dict[str, Any]) -> Optional[Dict[str, str]]:
        """Generate plan notification content via OpenAI, respecting coaching tone"""
        try:
            import openai
            import os
            import json

            openai_api_key = os.getenv('OPENAI_API_KEY')
            if not openai_api_key:
                logger.warning("OpenAI API key not configured; falling back to templates")
                return None

            client = openai.OpenAI(api_key=openai_api_key)

            tone_descriptors = {
                'drill_sergeant': 'authoritative, disciplined, direct, high-accountability',
                'supportive_friend': 'warm, encouraging, conversational, empathetic',
                'data_nerd': 'analytical, precise, metrics-driven yet motivating',
                'minimalist': 'succinct, calm, no fluff, still supportive'
            }

            notification_prompts = {
                'plan_evening_brief': {
                    'goal': 'Send an evening-before reminder encouraging preparation, rest, and anticipation of the next ruck session.',
                    'constraints': 'Mention start time or window, nod to weather if provided, keep under 120 characters for body and 50 for title.'
                },
                'plan_morning_hype': {
                    'goal': 'Deliver a short, energetic push notification about one hour before the planned ruck.',
                    'constraints': 'Highlight session focus or intent, remind about load or pacing if supplied, keep tone uplifting and concise.'
                },
                'plan_missed_followup': {
                    'goal': 'Encourage the athlete after a missed session with an actionable recovery plan.',
                    'constraints': 'Acknowledge miss without shame, provide a concrete next step or makeup option, keep message positive.'
                },
                'plan_completion_celebration': {
                    'goal': 'Celebrate a completed session with positive reinforcement tied to their plan metrics.',
                    'constraints': 'Reference distance, load, or adherence if available, point to next action or recovery tip, remain under push notification length limits.'
                },
                'plan_weekly_digest': {
                    'goal': 'Summarize weekly progress, reinforce adherence, and preview next focus area.',
                    'constraints': 'Include sessions completed vs planned, adherence percentage, upcoming focus or milestone, motivating close.'
                }
            }

            prompt_config = notification_prompts.get(notification_type)
            if not prompt_config:
                logger.debug(f"No AI prompt template for {notification_type}")
                return None

            tone_style = tone_descriptors.get(tone, tone_descriptors['supportive_friend'])

            system_prompt = (
                "You are an elite rucking coach crafting world-class push notifications. "
                f"Voice style: {tone_style}. "
                f"Objective: {prompt_config['goal']} "
                f"Constraints: {prompt_config['constraints']} "
                "Output must be valid JSON with 'title' (<=50 chars) and 'body' (<=120 chars)."
            )

            lines = [
                f"Notification type: {notification_type}",
                f"User ID: {user_id}",
                f"Plan: {context.get('plan_name', 'Coaching plan')}"
            ]

            if context.get('session_focus'):
                lines.append(f"Session focus: {context['session_focus']}")
            if context.get('scheduled_date_label'):
                lines.append(f"Scheduled day: {context['scheduled_date_label']}")
            if context.get('start_time_label'):
                lines.append(f"Start time: {context['start_time_label']} {context.get('timezone', 'UTC')}")
            if context.get('prime_window_label'):
                lines.append(f"Prime window: {context['prime_window_label']}")
            if context.get('weather_summary'):
                lines.append(f"Weather: {context['weather_summary']}")
            if context.get('distance_label'):
                lines.append(f"Distance: {context['distance_label']}")
            if context.get('load_label'):
                lines.append(f"Load: {context['load_label']}")
            if context.get('adherence_percent') is not None:
                lines.append(f"Adherence: {context['adherence_percent']}%")
            if context.get('completed_sessions') is not None and context.get('planned_sessions') is not None:
                lines.append(
                    f"Weekly sessions: {context['completed_sessions']}/{context['planned_sessions']}"
                )
            if context.get('upcoming_focus'):
                lines.append(f"Upcoming focus: {context['upcoming_focus']}")
            if context.get('makeup_tip'):
                lines.append(f"Makeup guidance: {context['makeup_tip']}")
            if context.get('next_tip'):
                lines.append(f"Next tip: {context['next_tip']}")
            if context.get('behavior_confidence') is not None:
                lines.append(f"Cadence confidence: {context['behavior_confidence']}")

            user_prompt = "\n".join(lines)

            response = client.chat.completions.create(
                model=os.getenv('OPENAI_PLAN_NOTIFICATIONS_MODEL', 'gpt-5'),
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                max_tokens=150,
                temperature=0.7
            )

            content = response.choices[0].message.content.strip()
            parsed_content = json.loads(content)
            if 'title' in parsed_content and 'body' in parsed_content:
                return parsed_content
            logger.error(f"AI plan notification response missing title/body: {content}")
            return None

        except Exception as exc:
            logger.error(f"Failed to generate AI plan notification: {exc}")
            return None

    def _get_user_coaching_profile(self, user_id: str) -> Dict[str, Any]:
        """Get user's coaching profile preferences"""
        try:
            from ..supabase_client import get_supabase_admin_client
            admin_client = get_supabase_admin_client()
            
            response = None
            try:
                response = admin_client.table('user_profiles').select(
                    'coaching_tone, coaching_style'
                ).eq('user_id', user_id).execute()
            except Exception as missing_profiles_err:
                logger.debug(f"user_profiles table not available: {missing_profiles_err}")

            if response and response.data:
                return response.data[0]

            # Fallback to core users table if profile record not available
            try:
                users_resp = admin_client.table('user').select(
                    'coaching_tone, coaching_style'
                ).eq('id', user_id).execute()
                if users_resp.data:
                    return users_resp.data[0]
            except Exception as users_err:
                logger.debug(f"Fallback to users table failed: {users_err}")
            
            return {'coaching_tone': None, 'coaching_style': 'balanced'}
            
        except Exception as e:
            logger.error(f"❌ Error getting user coaching profile: {e}")
            return {'coaching_tone': None, 'coaching_style': 'balanced'}
    
    def _get_retention_notification_content(self, notification_type: str, coaching_tone: str, context: Dict[str, Any]) -> Dict[str, str]:
        """Get AI-personalized retention notification content"""
        templates = {
            'session_1_celebration': {
                'drill_sergeant': {
                    'title': '🎯 Mission Accomplished!',
                    'body': 'Outstanding work on your first ruck! You\'ve taken the first step toward becoming unstoppable. Your body is already adapting - don\'t let this momentum die!'
                },
                'supportive_friend': {
                    'title': '🎉 Amazing First Ruck!',
                    'body': 'You did it! Your first ruck is complete and I\'m so proud of you. You\'ve started something incredible - your future self will thank you for this moment!'
                },
                'data_nerd': {
                    'title': '📊 Session 1: Complete',
                    'body': 'First ruck logged successfully. Initial baseline established. Your body has begun physiological adaptations. Optimal window for session 2: next 24-48 hours.'
                },
                'minimalist': {
                    'title': '✅ Session 1',
                    'body': 'First ruck done. Next: Session 2.'
                }
            },
            'session_1_to_2_day1': {
                'drill_sergeant': {
                    'title': '⚡ Time for Session 2!',
                    'body': 'Your body recovered overnight and is READY for action! The hardest part is behind you - session 2 will feel easier. Strike while the iron is hot!'
                },
                'supportive_friend': {
                    'title': '💪 Ready for Round 2?',
                    'body': 'Hey champion! Your body has had time to recover and adapt. Session 2 is often easier than the first - you\'ve got the experience now. Let\'s keep this amazing momentum going!'
                },
                'data_nerd': {
                    'title': '🔬 Recovery Complete',
                    'body': 'Analysis: 24-hour recovery period optimal. Muscle adaptation initiated. Session 2 projected difficulty: 15% easier than baseline. Recommendation: Execute within next 24 hours.'
                },
                'minimalist': {
                    'title': '⏰ Session 2',
                    'body': 'Body ready. Time for session 2.'
                }
            },
            'session_1_to_2_day2': {
                'drill_sergeant': {
                    'title': '🚨 Don\'t Lose Momentum!',
                    'body': 'Two days since your first ruck - that fire is still burning but it needs fuel! Every hour you wait makes it harder to restart. Get out there NOW!'
                },
                'supportive_friend': {
                    'title': '🤗 Missing You Out There',
                    'body': 'It\'s been a couple days since your awesome first ruck! I know life gets busy, but you felt so good after that first session. Just 20 minutes today - that\'s all it takes!'
                },
                'data_nerd': {
                    'title': '⚠️ Momentum Decay Detected',
                    'body': 'Alert: 48+ hour gap detected. Statistical analysis shows 67% drop in session 2 completion after this point. Immediate action recommended to maintain trajectory.'
                },
                'minimalist': {
                    'title': '📉 Momentum fading',
                    'body': 'Session 2. Today.'
                }
            },
            'session_2_celebration': {
                'drill_sergeant': {
                    'title': '🔥 You\'re Unstoppable!',
                    'body': 'TWO SESSIONS DOWN! You\'ve proven you\'re not a quitter. You\'re building something powerful here - next stop: 4 sessions in your first week!'
                },
                'supportive_friend': {
                    'title': '🌟 You\'re on Fire!',
                    'body': 'Session 2 complete - you\'re absolutely crushing this! You\'ve already beaten 48% of people who never make it past session 1. You\'re special, and it shows!'
                },
                'data_nerd': {
                    'title': '📈 Trajectory Confirmed',
                    'body': 'Session 2 complete. You\'re now in the top 52% of users. Pattern recognition: High probability of reaching 4-session first week milestone. Continue current trajectory.'
                },
                'minimalist': {
                    'title': '✅ Session 2',
                    'body': 'Two down. Momentum building.'
                }
            },
            'new_user_day1': {
                'drill_sergeant': {
                    'title': 'Day 1: Move!',
                    'body': '24 hours since signup. Throw on a pack, march 15 minutes, prove to yourself you’re serious.'
                },
                'supportive_friend': {
                    'title': 'Let’s take that first step',
                    'body': 'Grab a backpack, load a couple books, and stroll 10 minutes today. You’ll feel amazing after that first ruck.'
                },
                'data_nerd': {
                    'title': 'Prime moment to start',
                    'body': 'Habits stick best within 24h of intent. A 0.8 km shakeout ruck tonight keeps your streak probability high.'
                },
                'minimalist': {
                    'title': 'Backpack. Door. Go.',
                    'body': '10 minutes. Light pack. First ruck done.'
                }
            },
            'new_user_day3': {
                'drill_sergeant': {
                    'title': 'Momentum slipping',
                    'body': '72 hours since signup. Lace up, move 12 minutes tonight, and reclaim the fire you felt on day one!'
                },
                'supportive_friend': {
                    'title': 'Life’s busy—I get it',
                    'body': 'Sneak in a short ruck tonight. Even 0.5 km with a backpack resets your momentum and boosts your mood.'
                },
                'data_nerd': {
                    'title': 'Habit clock is ticking',
                    'body': 'Day 3 is the drop-off point for most. Beat the stat: 12-minute ruck now raises success odds by 68%.'
                },
                'minimalist': {
                    'title': 'Day 3 check-in',
                    'body': 'Backpack + 12 minutes. Do it tonight.'
                }
            },
            'single_ruck_day7': {
                'drill_sergeant': {
                    'title': 'Session 2 awaits',
                    'body': 'Seven days since your first ruck. Lace up and lock in session #2 before rust sets in!'
                },
                'supportive_friend': {
                    'title': 'Ride that first-ruck high',
                    'body': 'You loved that first ruck! A quick follow-up this week keeps the good vibes rolling. I’ve got your back.'
                },
                'data_nerd': {
                    'title': 'Momentum decay spotted',
                    'body': 'Your inaugural ruck was 7 days ago. Logging #2 within 10 days ups long-term consistency by 3x.'
                },
                'minimalist': {
                    'title': 'Second ruck time',
                    'body': 'Session #2 today. Let’s go.'
                }
            },
            'first_week_sprint_push': {
                'drill_sergeant': {
                    'title': '🏃‍♂️ First Week Sprint!',
                    'body': 'You\'ve got 2 sessions down - now let\'s make it 4 this week! Only 30% of people achieve this, but you\'re not like everyone else. CHARGE!'
                },
                'supportive_friend': {
                    'title': '🎯 Going for 4 This Week?',
                    'body': 'You\'re doing amazing with 2 sessions! Want to try something special? If you can get 4 sessions this week, you\'ll join an elite group. I believe you can do it!'
                },
                'data_nerd': {
                    'title': '🎲 First Week Sprint Available',
                    'body': 'Current: 2 sessions. Target: 4 sessions in week 1. Success rate: 30% of users. Your profile indicates 73% probability of success. Recommend attempt.'
                },
                'minimalist': {
                    'title': '🎯 Week 1: 4 sessions?',
                    'body': '2 of 4 done this week.'
                }
            },
            'session_3_celebration': {
                'drill_sergeant': {
                    'title': '💥 Three Sessions Strong!',
                    'body': 'THREE SESSIONS! You\'re 75% of the way to an elite first week. One more session and you\'ll be in the top 30%. FINISH STRONG!'
                },
                'supportive_friend': {
                    'title': '🚀 You\'re So Close!',
                    'body': 'Session 3 complete - you\'re incredible! Just ONE more session this week and you\'ll achieve something only 30% of people do. You\'re almost there!'
                },
                'data_nerd': {
                    'title': '📊 75% Progress to Elite Status',
                    'body': 'Session 3 logged. First week sprint: 75% complete. One session remaining for top 30% achievement. Probability of completion: 89% based on current pattern.'
                },
                'minimalist': {
                    'title': '✅ Session 3',
                    'body': '3 of 4. Almost there.'
                }
            },
            'first_week_sprint_complete': {
                'drill_sergeant': {
                    'title': '🏆 ELITE ACHIEVEMENT UNLOCKED!',
                    'body': 'FOUR SESSIONS IN WEEK ONE! You\'re now in the TOP 30% of all users! You\'ve proven you have what it takes. Next mission: Road to 7!'
                },
                'supportive_friend': {
                    'title': '🌟 You\'re Absolutely Amazing!',
                    'body': 'WOW! 4 sessions in your first week - you\'re in the top 30%! This is incredible and shows you\'re building a real habit. I\'m so proud of you!'
                },
                'data_nerd': {
                    'title': '🎖️ Top 30% Achievement',
                    'body': 'First Week Sprint: COMPLETE. Status: Elite (top 30% of users). Next milestone: Session 7 (habit formation threshold). Projected success rate: 71%.'
                },
                'minimalist': {
                    'title': '🏆 Elite Status',
                    'body': 'Top 30%. Week 1 complete.'
                }
            },
            'road_to_7_complete': {
                'drill_sergeant': {
                    'title': '🎖️ HABIT FORMATION COMPLETE!',
                    'body': 'SEVEN SESSIONS! You\'ve reached the habit formation threshold! 92.3% of people who reach this point stick with rucking. You\'re officially unstoppable!'
                },
                'supportive_friend': {
                    'title': '🎉 You\'ve Built a Habit!',
                    'body': 'Session 7 complete - you\'ve officially formed a rucking habit! Science shows 92% of people who reach this point continue long-term. You\'ve done something amazing!'
                },
                'data_nerd': {
                    'title': '🧠 Habit Formation: Confirmed',
                    'body': 'Session 7 achieved. Neurological habit pathways established. Long-term retention probability: 92.3%. Status: Habit formation complete. Mission accomplished.'
                },
                'minimalist': {
                    'title': '🧠 Habit formed',
                    'body': 'Session 7. Habit established.'
                }
            }
        }
        
        template = templates.get(notification_type, {})
        content = template.get(coaching_tone, template.get('supportive_friend', {}))
        
        if not content:
            # Fallback content
            return {
                'title': 'Ruck Update',
                'body': 'Keep up the great work with your rucking journey!'
            }
        
        return content


# Create singleton instance
notification_manager = NotificationManager()
