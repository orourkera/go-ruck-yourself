"""
Redis Cache Service for the Rucking App
Provides caching functionality to reduce memory usage and improve performance
"""
import os
import json
import redis
import logging
from typing import Any, Optional, Union
from datetime import timedelta

logger = logging.getLogger(__name__)

class RedisCacheService:
    """Redis-based cache service for storing frequently accessed data"""
    
    def __init__(self):
        """Initialize Redis connection"""
        self.redis_client = None
        self._initialize_redis()
    
    def _initialize_redis(self):
        """Initialize Redis connection with proper SSL configuration for Heroku"""
        try:
            # Prefer REDIS_URL, fallback to REDIS_TLS_URL (Heroku names this when SSL required)
            redis_url = os.environ.get('REDIS_URL') or os.environ.get('REDIS_TLS_URL')
            if not redis_url:
                logger.warning('REDIS_URL/REDIS_TLS_URL environment variables not found; Redis cache will be disabled.')
                self.redis_client = None
                return
            
            # For Heroku Redis, handle SSL configuration
            if redis_url.startswith('rediss://'):  # Heroku Redis uses rediss:// for SSL
                # Parse the URL to add SSL parameters
                self.redis_client = redis.from_url(
                    redis_url,
                    ssl_cert_reqs=None,  # Skip certificate verification for Heroku
                    decode_responses=True  # Automatically decode responses to strings
                )
            else:
                self.redis_client = redis.from_url(
                    redis_url,
                    decode_responses=True
                )
            
            # Test connection
            self.redis_client.ping()
            logger.info(f"Redis cache service initialized successfully with URL: {redis_url[:20]}...")
            
        except Exception as e:
            logger.error(f"Failed to initialize Redis cache service: {e}")
            self.redis_client = None
    
    def is_connected(self) -> bool:
        """Check if Redis is connected and available"""
        if not self.redis_client:
            return False
        try:
            self.redis_client.ping()
            return True
        except:
            return False
    
    def set(self, key: str, value: Any, expire_seconds: int = 3600) -> bool:
        """
        Set a value in Redis cache
        
        Args:
            key: Cache key
            value: Value to cache (will be JSON serialized)
            expire_seconds: Expiration time in seconds (default 1 hour)
        
        Returns:
            True if successful, False otherwise
        """
        if not self.is_connected():
            logger.warning("Redis not connected, cannot set cache value")
            return False
        
        try:
            # Serialize complex objects to JSON
            if isinstance(value, (dict, list)):
                serialized_value = json.dumps(value)
            else:
                serialized_value = str(value)
            
            result = self.redis_client.setex(key, expire_seconds, serialized_value)
            logger.debug(f"Set cache key '{key}' with expiration {expire_seconds}s")
            return result
            
        except Exception as e:
            logger.error(f"Error setting cache key '{key}': {e}")
            return False
    
    def get(self, key: str) -> Optional[Any]:
        """
        Get a value from Redis cache
        
        Args:
            key: Cache key
        
        Returns:
            Cached value or None if not found/error
        """
        if not self.is_connected():
            logger.warning("Redis not connected, cannot get cache value")
            return None
        
        try:
            value = self.redis_client.get(key)
            if value is None:
                return None
            
            # Try to deserialize JSON, fallback to string
            try:
                return json.loads(value)
            except json.JSONDecodeError:
                return value
                
        except Exception as e:
            logger.error(f"Error getting cache key '{key}': {e}")
            return None
    
    def delete(self, key: str) -> bool:
        """
        Delete a key from Redis cache
        
        Args:
            key: Cache key to delete
        
        Returns:
            True if successful, False otherwise
        """
        if not self.is_connected():
            logger.warning("Redis not connected, cannot delete cache key")
            return False
        
        try:
            result = self.redis_client.delete(key)
            logger.debug(f"Deleted cache key '{key}'")
            return result > 0
            
        except Exception as e:
            logger.error(f"Error deleting cache key '{key}': {e}")
            return False
    
    def delete_pattern(self, pattern: str) -> int:
        """
        Delete all keys matching a pattern
        
        Args:
            pattern: Pattern to match (e.g., 'user:*', 'session:123:*')
        
        Returns:
            Number of keys deleted
        """
        if not self.is_connected():
            logger.warning("Redis not connected, cannot delete cache pattern")
            return 0
        
        try:
            keys = self.redis_client.keys(pattern)
            if keys:
                result = self.redis_client.delete(*keys)
                logger.info(f"Deleted {result} keys matching pattern '{pattern}'")
                return result
            return 0
            
        except Exception as e:
            logger.error(f"Error deleting cache pattern '{pattern}': {e}")
            return 0
    
    def exists(self, key: str) -> bool:
        """
        Check if a key exists in Redis cache
        
        Args:
            key: Cache key to check
        
        Returns:
            True if key exists, False otherwise
        """
        if not self.is_connected():
            return False
        
        try:
            return self.redis_client.exists(key) > 0
        except Exception as e:
            logger.error(f"Error checking cache key existence '{key}': {e}")
            return False
    
    def increment(self, key: str, amount: int = 1, expire_seconds: int = 3600) -> Optional[int]:
        """
        Increment a numeric value in Redis
        
        Args:
            key: Cache key
            amount: Amount to increment by (default 1)
            expire_seconds: Expiration time for new keys
        
        Returns:
            New value after increment, or None on error
        """
        if not self.is_connected():
            return None
        
        try:
            # Use pipeline for atomic operations
            pipe = self.redis_client.pipeline()
            pipe.incr(key, amount)
            pipe.expire(key, expire_seconds)
            results = pipe.execute()
            return results[0]
            
        except Exception as e:
            logger.error(f"Error incrementing cache key '{key}': {e}")
            return None
    
    def get_memory_usage(self) -> dict:
        """
        Get Redis memory usage statistics
        
        Returns:
            Dictionary with memory statistics
        """
        if not self.is_connected():
            return {}
        
        try:
            info = self.redis_client.info('memory')
            return {
                'used_memory': info.get('used_memory', 0),
                'used_memory_human': info.get('used_memory_human', '0B'),
                'used_memory_peak': info.get('used_memory_peak', 0),
                'used_memory_peak_human': info.get('used_memory_peak_human', '0B'),
                'mem_fragmentation_ratio': info.get('mem_fragmentation_ratio', 0),
            }
        except Exception as e:
            logger.error(f"Error getting Redis memory usage: {e}")
            return {}
    
    def clear_all(self) -> bool:
        """
        Clear all cache data (use with caution!)
        
        Returns:
            True if successful, False otherwise
        """
        if not self.is_connected():
            return False
        
        try:
            self.redis_client.flushdb()
            logger.warning("Cleared all Redis cache data")
            return True
        except Exception as e:
            logger.error(f"Error clearing Redis cache: {e}")
            return False

# Global cache service instance
_cache_instance = None

def get_cache_service() -> RedisCacheService:
    """Get the global Redis cache service instance"""
    global _cache_instance
    if _cache_instance is None:
        _cache_instance = RedisCacheService()
    return _cache_instance

# Convenience functions for easy access
def cache_set(key: str, value: Any, expire_seconds: int = 3600) -> bool:
    """Set a value in cache"""
    return get_cache_service().set(key, value, expire_seconds)

def cache_get(key: str) -> Optional[Any]:
    """Get a value from cache"""
    return get_cache_service().get(key)

def cache_delete(key: str) -> bool:
    """Delete a key from cache"""
    return get_cache_service().delete(key)

def cache_delete_pattern(pattern: str) -> int:
    """Delete keys matching pattern"""
    return get_cache_service().delete_pattern(pattern)

def cache_exists(key: str) -> bool:
    """Check if key exists in cache"""
    return get_cache_service().exists(key)
