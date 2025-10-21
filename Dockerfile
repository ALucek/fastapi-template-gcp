FROM python:3.11-slim

# System deps (if you later need curl, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Leverage Docker layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Cloud Run expects the server to listen on $PORT (defaults to 8080)
ENV PORT=8080
EXPOSE 8080

CMD ["gunicorn", "-c", "docker/gunicorn_conf.py", "app.main:app"]
