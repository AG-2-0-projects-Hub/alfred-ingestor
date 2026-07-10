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

# Cloud Run injects $PORT (usually 8080); bind it. Deploy this service with
# --min-instances=1 (or "CPU always allocated") — the Telegram/escalation
# BackgroundTasks reply is CPU-frozen after the HTTP response otherwise.
ENV PORT=8080
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
