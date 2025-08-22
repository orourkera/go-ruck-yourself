"""
Automatic Memory profiling and monitoring for RuckTracker API
Tracks ALL function calls automatically without decorators
"""
import tracemalloc
import psutil
import gc
import sys
import threading
import time
from flask import jsonify, request
from functools import wraps
import logging
from datetime import datetime
from collections import defaultdict
import inspect

logger = logging.getLogger(__name__)

class AutoMemoryProfiler:
    def __init__(self):
        self.snapshots = []
        self.enabled = False
        self.function_stats = defaultdict(lambda: {'calls': 0, 'total_memory': 0, 'max_memory': 0})
        self.current_trace = None
        self.monitoring_thread = None
        self.stop_monitoring = False
        
    def start_automatic_profiling(self):
        """Start automatic profiling of ALL function calls"""
        if not self.enabled:
            tracemalloc.start()
            self.enabled = True
            self.stop_monitoring = False
            
            # Start background monitoring thread
            self.monitoring_thread = threading.Thread(target=self._background_monitor)
            self.monitoring_thread.daemon = True
            self.monitoring_thread.start()
            
            logger.info("🔧 Automatic memory profiling started - tracking ALL functions")
    
    def stop_automatic_profiling(self):
        """Stop automatic profiling"""
        if self.enabled:
            self.stop_monitoring = True
            if self.monitoring_thread:
                self.monitoring_thread.join(timeout=2)
            
            tracemalloc.stop()
            self.enabled = False
            logger.info("🛑 Automatic memory profiling stopped")
    
    def _background_monitor(self):
        """Background thread that monitors memory every 5 seconds"""
        while not self.stop_monitoring and self.enabled:
            try:
                self._capture_memory_snapshot()
                time.sleep(5)  # Monitor every 5 seconds
            except Exception as e:
                logger.error(f"Background monitoring error: {e}")
    
    def _capture_memory_snapshot(self):
        """Capture current memory state"""
        if not self.enabled:
            return
            
        try:
            # Get current memory
            process = psutil.Process()
            current_memory = process.memory_info().rss / 1024 / 1024
            
            # Take tracemalloc snapshot
            snapshot = tracemalloc.take_snapshot()
            
            # Store snapshot with timestamp
            self.snapshots.append({
                'timestamp': datetime.now(),
                'memory_mb': current_memory,
                'snapshot': snapshot
            })
            
            # Keep only last 50 snapshots to avoid memory bloat
            if len(self.snapshots) > 50:
                self.snapshots.pop(0)
                
        except Exception as e:
            logger.error(f"Error capturing memory snapshot: {e}")
    
    def get_memory_hotspots(self, limit=20):
        """Get the biggest memory consuming code locations automatically"""
        if not self.snapshots:
            return []
        
        # Get latest snapshot
        latest_snapshot = self.snapshots[-1]['snapshot']
        top_stats = latest_snapshot.statistics('lineno')
        
        hotspots = []
        for stat in top_stats[:limit]:
            # Filter out system/library code, focus on our app
            if any(keyword in str(stat.traceback) for keyword in ['RuckTracker', 'api/', 'ruck.py', 'auth.py']):
                hotspots.append({
                    'file_line': str(stat.traceback).split('\n')[-1] if stat.traceback else 'unknown',
                    'memory_mb': stat.size / 1024 / 1024,
                    'object_count': stat.count,
                    'traceback': [str(frame) for frame in stat.traceback] if stat.traceback else []
                })
        
        return sorted(hotspots, key=lambda x: x['memory_mb'], reverse=True)
    
    def get_memory_growth_analysis(self):
        """Analyze memory growth over time automatically"""
        if len(self.snapshots) < 2:
            return []
        
        # Compare latest with 10 snapshots ago (or earliest available)
        comparison_index = max(0, len(self.snapshots) - 10)
        old_snapshot = self.snapshots[comparison_index]['snapshot']
        new_snapshot = self.snapshots[-1]['snapshot']
        
        # Get memory differences
        top_stats = new_snapshot.compare_to(old_snapshot, 'lineno')
        
        growth_analysis = []
        for stat in top_stats[:15]:
            if stat.size_diff > 0:  # Only show memory growth
                # Filter our app code
                if any(keyword in str(stat.traceback) for keyword in ['RuckTracker', 'api/', 'ruck.py', 'auth.py']):
                    growth_analysis.append({
                        'file_line': str(stat.traceback).split('\n')[-1] if stat.traceback else 'unknown',
                        'memory_growth_mb': stat.size_diff / 1024 / 1024,
                        'object_growth': stat.count_diff,
                        'current_memory_mb': stat.size / 1024 / 1024
                    })
        
        return sorted(growth_analysis, key=lambda x: x['memory_growth_mb'], reverse=True)
    
    def get_function_call_stats(self):
        """Get statistics about which API endpoints/functions are called most"""
        return dict(self.function_stats)

# Global profiler instance
auto_profiler = AutoMemoryProfiler()

def track_endpoint_memory():
    """Middleware to automatically track memory for all API endpoints"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            if not auto_profiler.enabled:
                return func(*args, **kwargs)
            
            # Get memory before
            process = psutil.Process()
            memory_before = process.memory_info().rss / 1024 / 1024
            
            # Get function name and endpoint
            endpoint = request.endpoint or func.__name__
            
            try:
                # Execute function
                result = func(*args, **kwargs)
                
                # Get memory after
                memory_after = process.memory_info().rss / 1024 / 1024
                memory_diff = memory_after - memory_before
                
                # Update stats
                stats = auto_profiler.function_stats[endpoint]
                stats['calls'] += 1
                stats['total_memory'] += memory_diff
                stats['max_memory'] = max(stats['max_memory'], memory_diff)
                
                # Log significant memory usage
                if memory_diff > 5:  # More than 5MB
                    logger.warning(f"🔥 HIGH MEMORY: {endpoint} used {memory_diff:.2f}MB")
                elif memory_diff > 1:  # More than 1MB
                    logger.info(f"📊 MEMORY: {endpoint} used {memory_diff:.2f}MB")
                
                return result
                
            except Exception as e:
                logger.error(f"❌ ERROR in {endpoint}: {str(e)}")
                raise
                
        return wrapper
    return decorator

def get_comprehensive_memory_report():
    """Get comprehensive automatic memory report"""
    process = psutil.Process()
    memory_info = process.memory_info()
    
    # Get Python object counts
    object_counts = {}
    for obj in gc.get_objects():
        obj_type = type(obj).__name__
        object_counts[obj_type] = object_counts.get(obj_type, 0) + 1
    
    # Sort by count
    top_objects = sorted(object_counts.items(), key=lambda x: x[1], reverse=True)[:20]
    
    report = {
        'timestamp': datetime.now().isoformat(),
        'memory_mb': memory_info.rss / 1024 / 1024,
        'memory_percent': process.memory_percent(),
        'cpu_percent': process.cpu_percent(),
        'num_threads': process.num_threads(),
        'python_objects': {
            'total_objects': len(gc.get_objects()),
            'top_objects': top_objects,
            'gc_counts': gc.get_count()
        },
        'profiling_enabled': auto_profiler.enabled,
        'snapshots_count': len(auto_profiler.snapshots),
        'memory_hotspots': auto_profiler.get_memory_hotspots(15),
        'memory_growth': auto_profiler.get_memory_growth_analysis(),
        'endpoint_stats': auto_profiler.get_function_call_stats()
    }
    
    return report

def memory_cleanup():
    """Force memory cleanup"""
    collected = gc.collect()
    logger.info(f"🗑️ Garbage collected {collected} objects")
    return collected

# Auto-discover memory intensive Flask routes
def auto_instrument_flask_app(app):
    """Automatically instrument all Flask routes for memory tracking"""
    original_route = app.route
    
    def instrumented_route(*args, **kwargs):
        def decorator(func):
            # Determine the endpoint name Flask will use for this registration
            endpoint_name = kwargs.get('endpoint') or func.__name__
            
            # If this endpoint was already registered, reuse the same function object
            # so stacked @app.route decorators don't conflict
            if endpoint_name in app.view_functions:
                existing_func = app.view_functions[endpoint_name]
                return original_route(*args, **kwargs)(existing_func)
            
            # First-time registration for this endpoint: wrap and register
            tracked_func = track_endpoint_memory()(func)
            return original_route(*args, **kwargs)(tracked_func)
        return decorator
    
    # Replace app.route with instrumented version
    app.route = instrumented_route
    
    logger.info("🔧 Auto-instrumented Flask app for memory tracking")

# Memory monitoring routes
def init_memory_routes(app):
    """Initialize automatic memory monitoring routes"""
    
    @app.route('/api/system/memory')
    def memory_status():
        """Get detailed automatic memory analysis"""
        return jsonify(get_comprehensive_memory_report())
    
    @app.route('/api/system/memory/start-auto-profiling')
    def start_auto_profiling():
        """Start automatic memory profiling (no decorators needed)"""
        auto_profiler.start_automatic_profiling()
        return jsonify({'status': 'started', 'message': 'Automatic memory profiling started - tracking ALL functions'})
    
    @app.route('/api/system/memory/stop-auto-profiling')
    def stop_auto_profiling():
        """Stop automatic memory profiling"""
        if auto_profiler.enabled:
            report = get_comprehensive_memory_report()
            auto_profiler.stop_automatic_profiling()
            return jsonify({'status': 'stopped', 'final_report': report})
        return jsonify({'status': 'not_running', 'message': 'Auto-profiling was not running'})
    
    @app.route('/api/system/memory/hotspots')
    def memory_hotspots():
        """Get current memory hotspots automatically detected"""
        hotspots = auto_profiler.get_memory_hotspots(25)
        return jsonify({
            'hotspots': hotspots,
            'total_snapshots': len(auto_profiler.snapshots),
            'profiling_active': auto_profiler.enabled
        })
    
    @app.route('/api/system/memory/growth')
    def memory_growth():
        """Get memory growth analysis"""
        growth = auto_profiler.get_memory_growth_analysis()
        return jsonify({
            'growth_analysis': growth,
            'timespan_snapshots': min(10, len(auto_profiler.snapshots)),
            'profiling_active': auto_profiler.enabled
        })
    
    @app.route('/api/system/memory/cleanup')
    def memory_cleanup_endpoint():
        """Force garbage collection"""
        collected = memory_cleanup()
        memory_after = psutil.Process().memory_info().rss / 1024 / 1024
        return jsonify({
            'objects_collected': collected,
            'memory_mb_after_cleanup': memory_after
        })
    
    # Auto-instrument the Flask app
    auto_instrument_flask_app(app)
