# docker/gunicorn_conf.py
import os
# Bind to Cloud Run's provided port (default 8080).
bind = f"0.0.0.0:{os.getenv('PORT', '8080')}"

# Workers
workers = 1

# ASGI via Uvicorn worker
worker_class = "uvicorn.workers.UvicornWorker"

# Trust Cloud Run's X-Forwarded-* headers
forwarded_allow_ips = "*"

# Stability / lifecycle
timeout = 120
graceful_timeout = 60
keepalive = 5

# Periodic worker restarts to avoid memory creep
max_requests = 1000
max_requests_jitter = 100

# Logging to stdout/stderr for Cloud Run
accesslog = "-"
errorlog = "-"
loglevel = "info"
access_log_format = '%(h)s %(l)s %(u)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(L)ss'
