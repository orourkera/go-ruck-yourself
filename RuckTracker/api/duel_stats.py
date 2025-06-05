from flask import request, g
from flask_restful import Resource
from datetime import datetime, timedelta
from extensions import db
from utils.auth import auth_required

# ============================================================================
# RESOURCES
# ============================================================================

class UserDuelStatsResource(Resource):
    @auth_required
    def get(self, user_id=None):
        """Get user's duel statistics"""
        try:
            # If no user_id provided, use current user
            target_user_id = user_id or g.current_user['id']
            
            cursor = db.connection.cursor()
            
            # Get or create user duel stats
            cursor.execute('''
                SELECT * FROM user_duel_stats 
                WHERE user_id = %s
            ''', [target_user_id])
            
            stats = cursor.fetchone()
            
            if not stats:
                # Create initial stats record
                now = datetime.utcnow()
                cursor.execute('''
                    INSERT INTO user_duel_stats (user_id, created_at, updated_at)
                    VALUES (%s, %s, %s)
                    RETURNING *
                ''', [target_user_id, now, now])
                stats = cursor.fetchone()
                db.connection.commit()
            
            # Get additional computed stats
            cursor.execute('''
                SELECT 
                    COUNT(CASE WHEN d.status = 'active' THEN 1 END) as active_duels,
                    COUNT(CASE WHEN d.status = 'pending' THEN 1 END) as pending_duels,
                    AVG(CASE WHEN d.status = 'completed' AND d.winner_id = %s 
                        THEN dp.current_value END) as avg_winning_score,
                    MAX(CASE WHEN d.challenge_type = 'distance' 
                        THEN dp.current_value END) as best_distance,
                    MAX(CASE WHEN d.challenge_type = 'time' 
                        THEN dp.current_value END) as best_time,
                    MAX(CASE WHEN d.challenge_type = 'elevation' 
                        THEN dp.current_value END) as best_elevation,
                    MAX(CASE WHEN d.challenge_type = 'power_points' 
                        THEN dp.current_value END) as best_power_points
                FROM duel_participants dp
                JOIN duels d ON dp.duel_id = d.id
                WHERE dp.user_id = %s AND dp.status = 'accepted'
            ''', [target_user_id, target_user_id])
            
            computed_stats = cursor.fetchone()
            
            # Get recent duel history
            cursor.execute('''
                SELECT d.id, d.title, d.challenge_type, d.target_value, d.status,
                       d.created_at, d.ends_at, d.winner_id,
                       dp.current_value, dp.status as participant_status,
                       CASE WHEN d.winner_id = %s THEN true ELSE false END as won
                FROM duel_participants dp
                JOIN duels d ON dp.duel_id = d.id
                WHERE dp.user_id = %s AND dp.status = 'accepted'
                ORDER BY d.created_at DESC
                LIMIT 10
            ''', [target_user_id, target_user_id])
            
            recent_duels = cursor.fetchall()
            
            cursor.close()
            
            # Combine all stats
            result = dict(stats)
            result.update(dict(computed_stats))
            result['recent_duels'] = [dict(d) for d in recent_duels]
            
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
            
            cursor = db.connection.cursor()
            
            # Build query based on stat type
            if stat_type == 'wins':
                order_by = 'uds.duels_won DESC, uds.duels_completed DESC'
            elif stat_type == 'completion_rate':
                order_by = '''
                    CASE 
                        WHEN (uds.duels_created + uds.duels_joined) > 0 
                        THEN CAST(uds.duels_completed AS FLOAT) / (uds.duels_created + uds.duels_joined)
                        ELSE 0 
                    END DESC
                '''
            elif stat_type == 'total_duels':
                order_by = '(uds.duels_created + uds.duels_joined) DESC'
            else:
                order_by = 'uds.duels_won DESC'
            
            query = f'''
                SELECT uds.*, u.username, u.email,
                       (uds.duels_created + uds.duels_joined) as total_duels,
                       CASE 
                           WHEN uds.duels_completed > 0 
                           THEN CAST(uds.duels_won AS FLOAT) / uds.duels_completed
                           ELSE 0 
                       END as win_rate,
                       CASE 
                           WHEN (uds.duels_created + uds.duels_joined) > 0 
                           THEN CAST(uds.duels_completed AS FLOAT) / (uds.duels_created + uds.duels_joined)
                           ELSE 0 
                       END as completion_rate,
                       ROW_NUMBER() OVER (ORDER BY {order_by}) as rank
                FROM user_duel_stats uds
                JOIN users u ON uds.user_id = u.id
                WHERE (uds.duels_created + uds.duels_joined) > 0
                ORDER BY {order_by}
                LIMIT %s
            '''
            
            cursor.execute(query, [limit])
            leaderboard = cursor.fetchall()
            
            # Get current user's rank if not in top results
            user_id = g.current_user['id']
            user_in_results = any(row['user_id'] == user_id for row in leaderboard)
            user_rank = None
            
            if not user_in_results:
                user_rank_query = f'''
                    SELECT rank FROM (
                        SELECT user_id, 
                               ROW_NUMBER() OVER (ORDER BY {order_by}) as rank
                        FROM user_duel_stats uds
                        JOIN users u ON uds.user_id = u.id
                        WHERE (uds.duels_created + uds.duels_joined) > 0
                    ) ranked
                    WHERE user_id = %s
                '''
                cursor.execute(user_rank_query, [user_id])
                rank_result = cursor.fetchone()
                user_rank = rank_result['rank'] if rank_result else None
            
            cursor.close()
            
            return {
                'leaderboard': [dict(row) for row in leaderboard],
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
            user_id = g.current_user['id']
            days = int(request.args.get('days', 30))
            start_date = datetime.utcnow() - timedelta(days=days)
            
            cursor = db.connection.cursor()
            
            # Activity over time
            cursor.execute('''
                SELECT DATE(d.created_at) as date,
                       COUNT(*) as duels_created,
                       COUNT(CASE WHEN d.status = 'completed' THEN 1 END) as duels_completed
                FROM duels d
                WHERE d.creator_id = %s AND d.created_at >= %s
                GROUP BY DATE(d.created_at)
                ORDER BY date DESC
            ''', [user_id, start_date])
            
            activity_timeline = cursor.fetchall()
            
            # Performance by challenge type
            cursor.execute('''
                SELECT d.challenge_type,
                       COUNT(*) as total_duels,
                       COUNT(CASE WHEN d.winner_id = %s THEN 1 END) as wins,
                       AVG(dp.current_value) as avg_performance,
                       MAX(dp.current_value) as best_performance
                FROM duel_participants dp
                JOIN duels d ON dp.duel_id = d.id
                WHERE dp.user_id = %s AND dp.status = 'accepted' 
                      AND d.created_at >= %s
                GROUP BY d.challenge_type
            ''', [user_id, user_id, start_date])
            
            performance_by_type = cursor.fetchall()
            
            # Opponent analysis
            cursor.execute('''
                SELECT u.username, u.id as opponent_id,
                       COUNT(*) as duels_against,
                       COUNT(CASE WHEN d.winner_id = %s THEN 1 END) as wins_against,
                       COUNT(CASE WHEN d.winner_id = u.id THEN 1 END) as losses_against
                FROM duel_participants dp1
                JOIN duel_participants dp2 ON dp1.duel_id = dp2.duel_id AND dp1.user_id != dp2.user_id
                JOIN users u ON dp2.user_id = u.id
                JOIN duels d ON dp1.duel_id = d.id
                WHERE dp1.user_id = %s AND dp1.status = 'accepted' 
                      AND dp2.status = 'accepted' AND d.status = 'completed'
                      AND d.created_at >= %s
                GROUP BY u.id, u.username
                HAVING COUNT(*) > 1
                ORDER BY COUNT(*) DESC
                LIMIT 10
            ''', [user_id, user_id, start_date])
            
            frequent_opponents = cursor.fetchall()
            
            cursor.close()
            
            return {
                'period_days': days,
                'activity_timeline': [dict(row) for row in activity_timeline],
                'performance_by_type': [dict(row) for row in performance_by_type],
                'frequent_opponents': [dict(row) for row in frequent_opponents]
            }
            
        except Exception as e:
            return {'error': str(e)}, 500
