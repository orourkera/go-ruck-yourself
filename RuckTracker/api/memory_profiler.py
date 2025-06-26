"""
Memory profiling and monitoring for RuckTracker API
"""
import tracemalloc
import psutil
import gc
import sys
from flask import jsonify
from functools import wraps
import logging
from datetime import datetime
import os

logger = logging.getLogger(__name__)

class MemoryProfiler:
    def __init__(self):
        self.snapshots = []
        self.enabled = False
        
    def start_tracing(self):
        """Start memory tracing"""
        if not self.enabled:
            tracemalloc.start()
            self.enabled = True
            logger.info("🔧 Memory tracing started")
    
    def stop_tracing(self):
        """Stop memory tracing"""
        if self.enabled:
            tracemalloc.stop()
            self.enabled = False
            logger.info("🛑 Memory tracing stopped")
    
    def take_snapshot(self, name=""):
        """Take a memory snapshot"""
        if self.enabled:
            snapshot = tracemalloc.take_snapshot()
            self.snapshots.append({
                'name': name,
                'snapshot': snapshot,
                'timestamp': datetime.now()
            })
            logger.info(f"📸 Memory snapshot taken: {name}")
            return snapshot
        return None
    
    def get_top_stats(self, limit=10):
        """Get top memory consuming lines"""
        if not self.snapshots:
            return []
        
        current = self.snapshots[-1]['snapshot']
        top_stats = current.statistics('lineno')
        
        result = []
        for stat in top_stats[:limit]:
            result.append({
                'file': stat.traceback.format()[-1] if stat.traceback.format() else 'unknown',
                'size_mb': stat.size / 1024 / 1024,
                'count': stat.count
            })
        
        return result
    
    def compare_snapshots(self, index1=-2, index2=-1):
        """Compare two memory snapshots"""
        if len(self.snapshots) < 2:
            return []
        
        snapshot1 = self.snapshots[index1]['snapshot']
        snapshot2 = self.snapshots[index2]['snapshot']
        
        top_stats = snapshot2.compare_to(snapshot1, 'lineno')
        
        result = []
        for stat in top_stats[:10]:
            result.append({
                'file': stat.traceback.format()[-1] if stat.traceback.format() else 'unknown',
                'size_diff_mb': stat.size_diff / 1024 / 1024,
                'count_diff': stat.count_diff
            })
        
        return result

# Global profiler instance
memory_profiler = MemoryProfiler()

def profile_memory(snapshot_name=None):
    """Decorator to profile memory usage of a function"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            # Get memory before
            process = psutil.Process()
            memory_before = process.memory_info().rss / 1024 / 1024
            
            # Take snapshot before
            if memory_profiler.enabled:
                snapshot_name_full = f"{snapshot_name or func.__name__}_before"
                memory_profiler.take_snapshot(snapshot_name_full)
            
            try:
                # Execute function
                result = func(*args, **kwargs)
                
                # Get memory after
                memory_after = process.memory_info().rss / 1024 / 1024
                memory_diff = memory_after - memory_before
                
                # Take snapshot after
                if memory_profiler.enabled:
                    snapshot_name_full = f"{snapshot_name or func.__name__}_after"
                    memory_profiler.take_snapshot(snapshot_name_full)
                
                # Log memory usage
                if memory_diff > 1:  # Only log if significant memory increase
                    logger.warning(f"🔥 HIGH MEMORY: {func.__name__} used {memory_diff:.2f}MB (before: {memory_before:.2f}MB, after: {memory_after:.2f}MB)")
                else:
                    logger.info(f"📊 MEMORY: {func.__name__} used {memory_diff:.2f}MB")
                
                return result
                
            except Exception as e:
                logger.error(f"❌ ERROR in {func.__name__}: {str(e)}")
                raise
                
        return wrapper
    return decorator

def get_memory_report():
    """Get comprehensive memory report"""
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
        'num_fds': process.num_fds() if hasattr(process, 'num_fds') else None,
        'python_objects': {
            'total_objects': len(gc.get_objects()),
            'top_objects': top_objects,
            'gc_counts': gc.get_count()
        },
        'tracemalloc_enabled': memory_profiler.enabled,
        'snapshots_count': len(memory_profiler.snapshots)
    }
    
    if memory_profiler.enabled:
        report['top_memory_lines'] = memory_profiler.get_top_stats(10)
        if len(memory_profiler.snapshots) >= 2:
            report['memory_diff'] = memory_profiler.compare_snapshots()
    
    return report

def memory_cleanup():
    """Force memory cleanup"""
    collected = gc.collect()
    logger.info(f"🗑️ Garbage collected {collected} objects")
    return collected

# Memory monitoring routes
def init_memory_routes(app):
    """Initialize memory monitoring routes"""
    
    @app.route('/api/system/memory')
    def memory_status():
        """Get detailed memory status"""
        return jsonify(get_memory_report())
    
    @app.route('/api/system/memory/start-profiling')
    def start_memory_profiling():
        """Start memory profiling"""
        memory_profiler.start_tracing()
        memory_profiler.take_snapshot("start")
        return jsonify({'status': 'started', 'message': 'Memory profiling started'})
    
    @app.route('/api/system/memory/stop-profiling')
    def stop_memory_profiling():
        """Stop memory profiling"""
        if memory_profiler.enabled:
            memory_profiler.take_snapshot("stop")
            report = get_memory_report()
            memory_profiler.stop_tracing()
            return jsonify({'status': 'stopped', 'final_report': report})
        return jsonify({'status': 'not_running', 'message': 'Profiling was not running'})
    
    @app.route('/api/system/memory/cleanup')
    def memory_cleanup_endpoint():
        """Force garbage collection"""
        collected = memory_cleanup()
        memory_after = psutil.Process().memory_info().rss / 1024 / 1024
        return jsonify({
            'objects_collected': collected,
            'memory_mb_after_cleanup': memory_after
        })
    
    @app.route('/api/system/memory/snapshot')
    def take_memory_snapshot():
        """Take a memory snapshot"""
        snapshot = memory_profiler.take_snapshot("manual")
        if snapshot:
            return jsonify({'status': 'taken', 'snapshots_count': len(memory_profiler.snapshots)})
        return jsonify({'status': 'failed', 'message': 'Profiling not enabled'})
