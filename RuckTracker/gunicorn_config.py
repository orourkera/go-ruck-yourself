import multiprocessing
import os

# Server socket
bind = f"0.0.0.0:{os.environ.get('PORT', '5000')}"
backlog = 128

# Worker processes
workers = int(os.environ.get('GUNICORN_WORKERS', 2))  # Default to 2 for Heroku
worker_class = os.environ.get('GUNICORN_WORKER_CLASS', 'gevent')  # Try gevent
worker_connections = 100  # Lower for gevent
timeout = int(os.environ.get('GUNICORN_TIMEOUT', 30))  # Align with Heroku router
keepalive = 2

# Memory management
max_requests = 1000
max_requests_jitter = 100
preload_app = True

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