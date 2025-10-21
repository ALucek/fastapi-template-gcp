# docker/gunicorn_conf.py
import multiprocessing
import os

# Bind to the port Cloud Run provides (defaults to 8080, but don't assume)
bind = f"0.0.0.0:{os.getenv('PORT', '8080')}"

# Scale up later if needed.
workers = 1

# Required for FastAPI under gunicorn
worker_class = "uvicorn.workers.UvicornWorker"

# Cold start + dependency import headroom
timeout = 120
graceful_timeout = 120

keepalive = 5
accesslog = "-"
errorlog = "-"
loglevel = "info"
