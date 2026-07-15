# Cloud Run image for the Airbnb scraper (Firecrawl → Gemini structuring).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# The /scrape work (Firecrawl → Gemini → Supabase upsert → return) is fully
# synchronous — nothing runs after the response — so this service can scale to
# zero (--min-instances=0) and keep request-based (CPU-throttled) billing.
ENV PORT=8080
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
