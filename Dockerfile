FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_ROOT_USER_ACTION=ignore

WORKDIR /app

# Leverage Docker layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Create and use a non-root user for runtime
RUN useradd --create-home appuser && chown -R appuser:appuser /app
USER appuser

# Cloud Run expects the server to listen on $PORT (defaults to 8080)
ENV PORT=8080
EXPOSE 8080

CMD ["gunicorn", "-c", "docker/gunicorn_conf.py", "app.main:app"]
