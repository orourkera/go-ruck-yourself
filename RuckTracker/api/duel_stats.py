from flask import request, g
from flask_restful import Resource
from datetime import datetime, timedelta
from RuckTracker.supabase_client import get_supabase_client
from .auth import auth_required

# ============================================================================
# RESOURCES
# ============================================================================

class UserDuelStatsResource(Resource):
    @auth_required
    def get(self, user_id=None):
        """Get user's duel statistics"""
        try:
            # If no user_id provided, use current user
            target_user_id = user_id or g.user.id
            
            supabase = get_supabase_client()
            
            # Get or create user duel stats
            stats_response = supabase.table('user_duel_stats').select('*').eq('user_id', target_user_id).execute()
            
            stats = stats_response.data[0] if stats_response.data else None
            
            if not stats:
                # Create initial stats record
                now = datetime.utcnow()
                stats = {
                    'user_id': target_user_id,
                    'duels_created': 0,
                    'duels_joined': 0,
                    'duels_won': 0,
                    'duels_completed': 0,
                    'total_contribution': 0.0,
                    'average_contribution': 0.0,
                    'current_streak': 0,
                    'longest_streak': 0,
                    'created_at': now.isoformat(),
                    'updated_at': now.isoformat()
                }
                
                supabase.table('user_duel_stats').insert([stats]).execute()
            
            # Get additional computed stats
            cursor = supabase.table('duel_participants').select('duel_id(title, challenge_type, status, winner_id)').eq('user_id', target_user_id).order('joined_at', desc=True).execute()
            
            computed_stats = cursor.data
            
            # Get recent duel history
            cursor = supabase.table('duel_participants').select('duel_id(id, title, challenge_type, status, winner_id), current_value, status as participant_status').eq('user_id', target_user_id).order('joined_at', desc=True).limit(10).execute()
            
            recent_duels = cursor.data
            
            # Combine all stats
            result = dict(stats)
            result.update({
                'active_duels': len([d for d in computed_stats if d['duel_id']['status'] == 'active']),
                'pending_duels': len([d for d in computed_stats if d['duel_id']['status'] == 'pending']),
                'avg_winning_score': sum([d['duel_id']['winner_id'] == target_user_id and d['current_value'] or 0 for d in computed_stats]) / len([d for d in computed_stats if d['duel_id']['status'] == 'completed' and d['duel_id']['winner_id'] == target_user_id]) if [d for d in computed_stats if d['duel_id']['status'] == 'completed' and d['duel_id']['winner_id'] == target_user_id] else 0,
                'best_distance': max([d['duel_id']['challenge_type'] == 'distance' and d['current_value'] or 0 for d in computed_stats]),
                'best_time': max([d['duel_id']['challenge_type'] == 'time' and d['current_value'] or 0 for d in computed_stats]),
                'best_elevation': max([d['duel_id']['challenge_type'] == 'elevation' and d['current_value'] or 0 for d in computed_stats]),
                'best_power_points': max([d['duel_id']['challenge_type'] == 'power_points' and d['current_value'] or 0 for d in computed_stats]),
                'recent_duels': recent_duels
            })
            
            # Calculate derived metrics
            total_duels = result['duels_created'] + result['duels_joined']
            result['total_duels'] = total_duels
            result['win_rate'] = (result['duels_won'] / result['duels_completed']) if result['duels_completed'] > 0 else 0
            result['completion_rate'] = (result['duels_completed'] / total_duels) if total_duels > 0 else 0
            
            return result
            
        except Exception as e:
            return {'error': str(e)}, 500


class DuelStatsLeaderboardResource(Resource):
    @auth_required
    def get(self):
        """Get global duel leaderboards"""
        try:
            stat_type = request.args.get('type', 'wins')  # wins, completion_rate, total_duels
            limit = min(int(request.args.get('limit', 50)), 100)
            
            supabase = get_supabase_client()
            
            # Build query based on stat type
            if stat_type == 'wins':
                order_by = 'duels_won DESC, duels_completed DESC'
            elif stat_type == 'completion_rate':
                order_by = '''
                    CASE 
                        WHEN (duels_created + duels_joined) > 0 
                        THEN CAST(duels_completed AS FLOAT) / (duels_created + duels_joined)
                        ELSE 0 
                    END DESC
                '''
            elif stat_type == 'total_duels':
                order_by = '(duels_created + duels_joined) DESC'
            else:
                order_by = 'duels_won DESC'
            
            query = f'''
                SELECT *, 
                       (duels_created + duels_joined) as total_duels,
                       CASE 
                           WHEN duels_completed > 0 
                           THEN CAST(duels_won AS FLOAT) / duels_completed
                           ELSE 0 
                       END as win_rate,
                       CASE 
                           WHEN (duels_created + duels_joined) > 0 
                           THEN CAST(duels_completed AS FLOAT) / (duels_created + duels_joined)
                           ELSE 0 
                       END as completion_rate,
                       ROW_NUMBER() OVER (ORDER BY {order_by}) as rank
                FROM user_duel_stats
                WHERE (duels_created + duels_joined) > 0
                ORDER BY {order_by}
                LIMIT %s
            '''
            
            leaderboard_response = supabase.rpc(query, [limit])
            
            leaderboard = leaderboard_response.data
            
            # Get current user's rank if not in top results
            user_id = g.user.id
            user_in_results = any(row['user_id'] == user_id for row in leaderboard)
            user_rank = None
            
            if not user_in_results:
                user_rank_query = f'''
                    SELECT rank FROM (
                        SELECT user_id, 
                               ROW_NUMBER() OVER (ORDER BY {order_by}) as rank
                        FROM user_duel_stats
                        WHERE (duels_created + duels_joined) > 0
                    ) ranked
                    WHERE user_id = %s
                '''
                user_rank_response = supabase.rpc(user_rank_query, [user_id])
                rank_result = user_rank_response.data[0] if user_rank_response.data else None
                user_rank = rank_result['rank'] if rank_result else None
            
            return {
                'leaderboard': leaderboard,
                'stat_type': stat_type,
                'user_rank': user_rank
            }
            
        except Exception as e:
            return {'error': str(e)}, 500


class DuelAnalyticsResource(Resource):
    @auth_required
    def get(self):
        """Get duel analytics and insights"""
        try:
            user_id = g.user.id
            days = int(request.args.get('days', 30))
            start_date = datetime.utcnow() - timedelta(days=days)
            
            supabase = get_supabase_client()
            
            # Activity over time
            cursor = supabase.table('duels').select('created_at').gte('created_at', start_date.isoformat()).execute()
            
            activity_timeline = cursor.data
            
            # Performance by challenge type
            cursor = supabase.table('duel_participants').select('duel_id(challenge_type)').eq('user_id', user_id).execute()
            
            performance_by_type = cursor.data
            
            # Opponent analysis
            cursor = supabase.table('duel_participants').select('duel_id(id, winner_id)').eq('user_id', user_id).execute()
            
            frequent_opponents = cursor.data
            
            return {
                'period_days': days,
                'activity_timeline': activity_timeline,
                'performance_by_type': performance_by_type,
                'frequent_opponents': frequent_opponents
            }
            
        except Exception as e:
            return {'error': str(e)}, 500
