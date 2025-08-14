import multiprocessing
import os

# Server socket
bind = f"0.0.0.0:{os.environ.get('PORT', '5000')}"
backlog = 128

# Worker processes
workers = int(os.environ.get('WEB_CONCURRENCY', os.environ.get('GUNICORN_WORKERS', 1)))  # Default to 1 to stay within 512MB dynos
worker_class = os.environ.get('GUNICORN_WORKER_CLASS', 'gevent')  # Default gevent; can set to 'gthread'
threads = int(os.environ.get('GUNICORN_THREADS', 2))  # Used when worker_class='gthread'
worker_connections = 100  # For gevent
timeout = int(os.environ.get('GUNICORN_TIMEOUT', 30))  # Align with Heroku router
keepalive = 2

# Memory management
max_requests = int(os.environ.get('GUNICORN_MAX_REQUESTS', 300))
max_requests_jitter = int(os.environ.get('GUNICORN_MAX_REQUESTS_JITTER', 50))
# Default to False to avoid duplicating memory; enable by setting GUNICORN_PRELOAD=true if needed
preload_app = os.environ.get('GUNICORN_PRELOAD', 'false').lower() == 'true'

# Logging - Reduced verbosity to prevent log overflow
accesslog = "-"
errorlog = "-"
loglevel = "warning"  # Reduced from 'info' to 'warning'
# Simplified access log format (remove user agent and referer to reduce log size)
access_log_format = '%h %t "%r" %s %b %D'

# Security
limit_request_line = 4094
limit_request_fields = 100
limit_request_field_size = 4096  # Tighten if possible

# Performance
# Removed worker_tmp_dir unless verified on Heroku

# Logging hooks - Reduced verbosity
def when_ready(server):
    server.log.info("Server is ready. Spawning workers")

def worker_int(worker):
    worker.log.warning("worker received INT or QUIT signal")

def pre_fork(server, worker):
    # Only log at debug level to reduce verbosity
    pass

def post_fork(server, worker):
    # Only log at debug level to reduce verbosity
    pass

def worker_abort(worker):
    worker.log.error("worker received SIGABRT signal")