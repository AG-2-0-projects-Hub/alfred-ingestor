# Cloud Run image for the FastAPI backend ("The Ingestor").
# Python pinned to 3.12 — 3.14 has no pydantic-core wheel and fails the Rust
# build (the same constraint we hit on Render, PYTHON_VERSION=3.12.10).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install deps first so the layer caches across code-only changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Cloud Run injects $PORT (usually 8080); bind it.
#
# Nothing here runs after a response is sent, so this service is safe on default
# request-based (CPU-throttled) billing and can scale to zero. That is deliberate:
# the Telegram reply used to run in a BackgroundTask, which Cloud Run froze the
# instant the webhook answered — the cure ("CPU always allocated") bills an idle
# container 24/7. The work now goes through Cloud Tasks, which calls us back as a
# fresh request. Deploy with CLOUD_TASKS_QUEUE / CLOUD_TASKS_LOCATION /
# SERVICE_BASE_URL set; leave them unset on a host that does not throttle
# (Render staging, local) and it falls back to BackgroundTasks.
ENV PORT=8080
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
