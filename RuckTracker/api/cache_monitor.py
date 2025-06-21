"""
Cache monitoring endpoints for Redis performance tracking
"""
import psutil
import os
from flask import Blueprint, jsonify, g
from flask_restful import Api, Resource
from RuckTracker.api.auth import auth_required, get_user_id
from RuckTracker.services.redis_cache_service import get_cache_service

cache_monitor_bp = Blueprint('cache_monitor', __name__)
api = Api(cache_monitor_bp)

class CacheStatusResource(Resource):
    @auth_required
    def get(self):
        """Get cache and memory status (admin only for now)"""
        try:
            cache_service = get_cache_service()
            
            # Get Redis status
            redis_connected = cache_service.is_connected()
            redis_memory = cache_service.get_memory_usage() if redis_connected else {}
            
            # Get Python process memory usage
            process = psutil.Process(os.getpid())
            process_memory = process.memory_info()
            
            # Calculate memory usage in MB
            rss_mb = process_memory.rss / 1024 / 1024
            vms_mb = process_memory.vms / 1024 / 1024
            
            return {
                'status': 'success',
                'redis': {
                    'connected': redis_connected,
                    'memory_stats': redis_memory
                },
                'python_process': {
                    'memory_mb': {
                        'rss': round(rss_mb, 2),  # Resident Set Size (physical memory)
                        'vms': round(vms_mb, 2),  # Virtual Memory Size
                    },
                    'memory_percent': round(process.memory_percent(), 2),
                    'pid': process.pid
                },
                'heroku_limits': {
                    'memory_limit_mb': 512,  # Heroku hobby tier limit
                    'memory_usage_percent': round((rss_mb / 512) * 100, 2),
                    'memory_available_mb': round(512 - rss_mb, 2)
                }
            }, 200
            
        except Exception as e:
            return {
                'status': 'error',
                'message': f'Error getting cache status: {str(e)}'
            }, 500

class CacheClearResource(Resource):
    @auth_required 
    def post(self):
        """Clear cache (admin only for now)"""
        try:
            cache_service = get_cache_service()
            
            if not cache_service.is_connected():
                return {
                    'status': 'error',
                    'message': 'Redis not connected'
                }, 500
            
            # Clear all cache data
            success = cache_service.clear_all()
            
            if success:
                return {
                    'status': 'success',
                    'message': 'Cache cleared successfully'
                }, 200
            else:
                return {
                    'status': 'error', 
                    'message': 'Failed to clear cache'
                }, 500
                
        except Exception as e:
            return {
                'status': 'error',
                'message': f'Error clearing cache: {str(e)}'
            }, 500

class CacheTestResource(Resource):
    @auth_required
    def post(self):
        """Test cache functionality"""
        try:
            cache_service = get_cache_service()
            
            if not cache_service.is_connected():
                return {
                    'status': 'error',
                    'message': 'Redis not connected'
                }, 500
            
            # Test cache operations
            test_key = f"test:{g.user.id}:cache_test"
            test_value = {"test": "data", "timestamp": str(cache_service.redis_client.time()[0])}
            
            # Set test value
            set_success = cache_service.set(test_key, test_value, 60)  # 1 minute TTL
            
            # Get test value
            retrieved_value = cache_service.get(test_key)
            
            # Check if value matches
            values_match = retrieved_value == test_value
            
            # Clean up
            cache_service.delete(test_key)
            
            return {
                'status': 'success',
                'test_results': {
                    'set_operation': set_success,
                    'get_operation': retrieved_value is not None,
                    'values_match': values_match,
                    'redis_connected': True
                }
            }, 200
            
        except Exception as e:
            return {
                'status': 'error',
                'message': f'Cache test failed: {str(e)}'
            }, 500

# Register endpoints
api.add_resource(CacheStatusResource, '/api/cache/status')
api.add_resource(CacheClearResource, '/api/cache/clear')
api.add_resource(CacheTestResource, '/api/cache/test')
