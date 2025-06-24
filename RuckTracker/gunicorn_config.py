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

# Logging
accesslog = "-"
errorlog = "-"
loglevel = "info"
access_log_format = '%h %l %u %t "%r" %s %b "%{Referer}i" "%{User-Agent}i" %D'

# Security
limit_request_line = 4094
limit_request_fields = 100
limit_request_field_size = 4096  # Tighten if possible

# Performance
# Removed worker_tmp_dir unless verified on Heroku

# Logging hooks
def when_ready(server):
    server.log.info("Server is ready. Spawning workers")

def worker_int(worker):
    worker.log.info("worker received INT or QUIT signal")

def pre_fork(server, worker):
    server.log.info("Worker spawned (pid: %s)", worker.pid)

def post_fork(server, worker):
    server.log.info("Worker spawned (pid: %s)", worker.pid)

def worker_abort(worker):
    worker.log.info("worker received SIGABRT signal")