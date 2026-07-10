# Cloud Run image for the Airbnb scraper (Firecrawl → Gemini structuring).
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# The /scrape work (Firecrawl → Gemini → Supabase upsert → return) is synchronous,
# so this service can scale to zero (--min-instances=0). The only BackgroundTasks
# call is the non-critical, deprecated Make.com webhook — safe to lose on a
# scaled-to-zero cold path.
ENV PORT=8080
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
