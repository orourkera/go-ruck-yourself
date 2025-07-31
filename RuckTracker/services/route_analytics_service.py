"""
Route Analytics Service for tracking route usage, popularity, and user interactions.
Provides centralized analytics recording and reporting for the AllTrails integration.
"""

import logging
from typing import Dict, Any, List, Optional
from decimal import Decimal
from datetime import datetime, timedelta

from ..supabase_client import get_supabase_client
from ..models import RouteAnalytics, RoutePopularityStats

logger = logging.getLogger(__name__)

class RouteAnalyticsService:
    """Service for recording and retrieving route analytics."""
    
    def __init__(self, user_jwt=None):
        # Use authenticated client if JWT provided, otherwise fallback to regular client
        self.supabase = get_supabase_client(user_jwt=user_jwt)
        self.user_jwt = user_jwt
    
    def record_route_viewed(self, route_id: str, user_id: str) -> bool:
        """Record when a user views a route."""
        try:
            analytics_event = RouteAnalytics.create_view_event(route_id, user_id)
            
            result = self.supabase.table('route_analytics').insert(analytics_event.to_dict()).execute()
            
            return bool(result.data)
            
        except Exception as e:
            logger.error(f"Failed to record route view: {e}")
            return False
    
    def record_route_planned(self, route_id: str, user_id: str) -> bool:
        """Record when a user plans a ruck with this route."""
        try:
            analytics_event = RouteAnalytics.create_planned_event(route_id, user_id)
            
            result = self.supabase.table('route_analytics').insert(analytics_event.to_dict()).execute()
            
            return bool(result.data)
            
        except Exception as e:
            logger.error(f"Failed to record route planned: {e}")
            return False
    
    def record_route_started(self, route_id: str, user_id: str, ruck_weight_kg: Optional[Decimal] = None) -> bool:
        """Record when a user starts a ruck session with this route."""
        try:
            analytics_event = RouteAnalytics.create_started_event(route_id, user_id, ruck_weight_kg)
            
            result = self.supabase.table('route_analytics').insert(analytics_event.to_dict()).execute()
            
            return bool(result.data)
            
        except Exception as e:
            logger.error(f"Failed to record route started: {e}")
            return False
    
    def record_route_completed(
        self, 
        route_id: str, 
        user_id: str, 
        duration_hours: Decimal,
        ruck_weight_kg: Optional[Decimal] = None,
        rating: Optional[int] = None,
        feedback: Optional[str] = None
    ) -> bool:
        """Record when a user completes a ruck session with this route."""
        try:
            analytics_event = RouteAnalytics.create_completed_event(
                route_id, user_id, duration_hours, ruck_weight_kg, rating, feedback
            )
            
            result = self.supabase.table('route_analytics').insert(analytics_event.to_dict()).execute()
            
            return bool(result.data)
            
        except Exception as e:
            logger.error(f"Failed to record route completed: {e}")
            return False
    
    def record_route_cancelled(self, route_id: str, user_id: str, reason: Optional[str] = None) -> bool:
        """Record when a user cancels a planned ruck with this route."""
        try:
            analytics_event = RouteAnalytics.create_cancelled_event(route_id, user_id, reason)
            
            result = self.supabase.table('route_analytics').insert(analytics_event.to_dict()).execute()
            
            return bool(result.data)
            
        except Exception as e:
            logger.error(f"Failed to record route cancelled: {e}")
            return False
    
    def record_route_created(self, route_id: str, user_id: str) -> bool:
        """Record when a user creates a new route."""
        try:
            # Use 'viewed' event type since 'created' is not in valid event types
            analytics_event = RouteAnalytics(
                id=None,
                route_id=route_id,
                user_id=user_id,
                event_type='viewed',  # Use 'viewed' as closest valid event type
                created_at=datetime.now()
            )
            
            result = self.supabase.table('route_analytics').insert(analytics_event.to_dict()).execute()
            
            return bool(result.data)
            
        except Exception as e:
            # Check if it's an RLS policy violation (non-critical error)
            error_str = str(e)
            if 'row-level security policy' in error_str or '42501' in error_str:
                logger.warning(f"Route analytics RLS policy violation - route: {route_id}, user: {user_id}. This is non-critical.")
            else:
                logger.error(f"Failed to record route creation analytics - route: {route_id}, user: {user_id}: {e}")
            return False
    
    def get_route_popularity_stats(self, route_id: str) -> Optional[RoutePopularityStats]:
        """Get aggregated popularity statistics for a route."""
        try:
            # Get all analytics events for this route
            result = self.supabase.table('route_analytics').select('*').eq('route_id', route_id).execute()
            
            if not result.data:
                return RoutePopularityStats(route_id=route_id)
            
            stats = RoutePopularityStats(route_id=route_id)
            
            # Count events by type
            durations = []
            ratings = []
            rating_counts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
            
            for event_data in result.data:
                event_type = event_data['event_type']
                
                if event_type == 'viewed':
                    stats.total_views += 1
                elif event_type == 'planned':
                    stats.total_planned += 1
                elif event_type == 'started':
                    stats.total_started += 1
                elif event_type == 'completed':
                    stats.total_completed += 1
                    
                    # Collect duration data
                    if event_data.get('actual_duration_hours'):
                        durations.append(Decimal(str(event_data['actual_duration_hours'])))
                    
                    # Collect rating data
                    if event_data.get('user_rating'):
                        rating = event_data['user_rating']
                        ratings.append(rating)
                        rating_counts[rating] += 1
                        
                elif event_type == 'cancelled':
                    stats.total_cancelled += 1
            
            # Calculate rating statistics
            if ratings:
                stats.average_rating = Decimal(sum(ratings)) / Decimal(len(ratings))
                stats.total_ratings = len(ratings)
                stats.rating_distribution = {k: v for k, v in rating_counts.items() if v > 0}
            
            # Calculate duration statistics
            if durations:
                stats.average_duration_hours = sum(durations) / len(durations)
                stats.fastest_duration_hours = min(durations)
                stats.slowest_duration_hours = max(durations)
            
            # Calculate completion rate
            stats.calculate_completion_rate()
            
            return stats
            
        except Exception as e:
            logger.error(f"Failed to get route popularity stats: {e}")
            return None
    
    def get_trending_routes(self, limit: int = 10, days: int = 30) -> List[Dict[str, Any]]:
        """Get trending routes based on recent activity."""
        try:
            # Get routes with activity in the last N days
            cutoff_date = (datetime.now() - timedelta(days=days)).isoformat()
            
            # Get recent analytics events
            result = self.supabase.table('route_analytics').select(
                'route_id, event_type, user_rating, created_at'
            ).gte('created_at', cutoff_date).execute()
            
            if not result.data:
                return []
            
            # Group by route and calculate trending scores
            route_activity = {}
            
            for event in result.data:
                route_id = event['route_id']
                event_type = event['event_type']
                
                if route_id not in route_activity:
                    route_activity[route_id] = {
                        'views': 0,
                        'planned': 0,
                        'started': 0,
                        'completed': 0,
                        'ratings': [],
                        'score': 0
                    }
                
                activity = route_activity[route_id]
                
                if event_type == 'viewed':
                    activity['views'] += 1
                elif event_type == 'planned':
                    activity['planned'] += 1
                elif event_type == 'started':
                    activity['started'] += 1
                elif event_type == 'completed':
                    activity['completed'] += 1
                    if event.get('user_rating'):
                        activity['ratings'].append(event['user_rating'])
            
            # Calculate trending scores
            for route_id, activity in route_activity.items():
                score = (
                    activity['views'] * 1 +
                    activity['planned'] * 3 +
                    activity['started'] * 5 +
                    activity['completed'] * 10
                )
                
                # Bonus for high ratings
                if activity['ratings']:
                    avg_rating = sum(activity['ratings']) / len(activity['ratings'])
                    if avg_rating >= 4.0:
                        score += 20
                
                # Bonus for high completion rate
                if activity['started'] > 0:
                    completion_rate = activity['completed'] / activity['started']
                    if completion_rate >= 0.8:
                        score += 15
                
                activity['score'] = score
            
            # Sort by score and get top routes
            top_route_ids = sorted(
                route_activity.keys(), 
                key=lambda r: route_activity[r]['score'], 
                reverse=True
            )[:limit]
            
            if not top_route_ids:
                return []
            
            # Get route details
            routes_result = self.supabase.table('routes').select(
                'id, name, description, distance_km, elevation_gain_m, '
                'trail_difficulty, total_completed_count, average_rating'
            ).in_('id', top_route_ids).execute()
            
            # Combine route data with trending scores
            trending_routes = []
            for route_data in routes_result.data:
                route_id = route_data['id']
                if route_id in route_activity:
                    route_data['trending_score'] = route_activity[route_id]['score']
                    route_data['recent_activity'] = route_activity[route_id]
                    trending_routes.append(route_data)
            
            # Sort by trending score
            trending_routes.sort(key=lambda r: r['trending_score'], reverse=True)
            
            return trending_routes
            
        except Exception as e:
            logger.error(f"Failed to get trending routes: {e}")
            return []
    
    def get_user_route_history(self, user_id: str, limit: int = 50) -> List[Dict[str, Any]]:
        """Get a user's route interaction history."""
        try:
            result = self.supabase.table('route_analytics').select(
                'route_id, event_type, actual_duration_hours, user_rating, '
                'user_feedback, created_at'
            ).eq('user_id', user_id).order('created_at', desc=True).limit(limit).execute()
            
            return result.data or []
            
        except Exception as e:
            logger.error(f"Failed to get user route history: {e}")
            return []
    
    def get_route_completion_insights(self, route_id: str) -> Dict[str, Any]:
        """Get detailed completion insights for a route."""
        try:
            # Get completion events only
            result = self.supabase.table('route_analytics').select(
                'actual_duration_hours, actual_ruck_weight_kg, user_rating, '
                'user_feedback, created_at'
            ).eq('route_id', route_id).eq('event_type', 'completed').execute()
            
            if not result.data:
                return {'route_id': route_id, 'completions': 0, 'insights': []}
            
            completions = result.data
            durations = [Decimal(str(c['actual_duration_hours'])) for c in completions if c.get('actual_duration_hours')]
            weights = [Decimal(str(c['actual_ruck_weight_kg'])) for c in completions if c.get('actual_ruck_weight_kg')]
            ratings = [c['user_rating'] for c in completions if c.get('user_rating')]
            feedback = [c['user_feedback'] for c in completions if c.get('user_feedback')]
            
            insights = []
            
            # Duration insights
            if durations:
                avg_duration = sum(durations) / len(durations)
                min_duration = min(durations)
                max_duration = max(durations)
                
                insights.append({
                    'type': 'duration',
                    'average_hours': float(avg_duration),
                    'fastest_hours': float(min_duration),
                    'slowest_hours': float(max_duration),
                    'sample_size': len(durations)
                })
            
            # Weight insights
            if weights:
                avg_weight = sum(weights) / len(weights)
                insights.append({
                    'type': 'weight',
                    'average_kg': float(avg_weight),
                    'sample_size': len(weights)
                })
            
            # Rating insights
            if ratings:
                avg_rating = sum(ratings) / len(ratings)
                rating_distribution = {}
                for rating in ratings:
                    rating_distribution[rating] = rating_distribution.get(rating, 0) + 1
                
                insights.append({
                    'type': 'rating',
                    'average_rating': avg_rating,
                    'total_ratings': len(ratings),
                    'distribution': rating_distribution
                })
            
            # Feedback insights (recent feedback)
            recent_feedback = [f for f in feedback if f.strip()][-5:]  # Last 5 feedback entries
            
            return {
                'route_id': route_id,
                'completions': len(completions),
                'insights': insights,
                'recent_feedback': recent_feedback
            }
            
        except Exception as e:
            logger.error(f"Failed to get route completion insights: {e}")
            return {'route_id': route_id, 'completions': 0, 'insights': [], 'error': str(e)}
    
    def get_user_analytics_summary(self, user_id: str) -> Dict[str, Any]:
        """Get analytics summary for a user's route activities."""
        try:
            result = self.supabase.table('route_analytics').select(
                'event_type, actual_duration_hours, user_rating, created_at'
            ).eq('user_id', user_id).execute()
            
            if not result.data:
                return {'user_id': user_id, 'total_events': 0}
            
            events = result.data
            
            # Count events by type
            event_counts = {}
            total_duration = Decimal('0')
            ratings = []
            
            for event in events:
                event_type = event['event_type']
                event_counts[event_type] = event_counts.get(event_type, 0) + 1
                
                if event.get('actual_duration_hours'):
                    total_duration += Decimal(str(event['actual_duration_hours']))
                
                if event.get('user_rating'):
                    ratings.append(event['user_rating'])
            
            summary = {
                'user_id': user_id,
                'total_events': len(events),
                'event_counts': event_counts,
                'total_ruck_hours': float(total_duration),
                'routes_completed': event_counts.get('completed', 0),
                'routes_started': event_counts.get('started', 0),
                'completion_rate': 0.0
            }
            
            # Calculate completion rate
            if event_counts.get('started', 0) > 0:
                summary['completion_rate'] = event_counts.get('completed', 0) / event_counts['started']
            
            # Add rating summary
            if ratings:
                summary['average_rating_given'] = sum(ratings) / len(ratings)
                summary['total_ratings_given'] = len(ratings)
            
            return summary
            
        except Exception as e:
            logger.error(f"Failed to get user analytics summary: {e}")
            return {'user_id': user_id, 'total_events': 0, 'error': str(e)}
