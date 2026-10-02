import os
import sentry_sdk
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
from routers import (
    ingest, ingest_worker, merge_resolve, messages, guest_auth, properties, telegram, whatsapp,
)

load_dotenv()

# Crash/error visibility. Empty SENTRY_DSN means Sentry is off -- local dev
# doesn't send events by default. ENVIRONMENT distinguishes staging/production
# events since those run as separate Cloud Run services, not a runtime flag.
_sentry_dsn = os.getenv("SENTRY_DSN", "")
if _sentry_dsn:
    sentry_sdk.init(dsn=_sentry_dsn, environment=os.getenv("ENVIRONMENT", "local"))

app = FastAPI(title="The Ingestor")

# Parse FRONTEND_URL as comma-separated so multiple origins can be listed in
# the Render env var (e.g. "https://alfred-ingestor.vercel.app,http://localhost:3000").
# Strip trailing slashes so a misconfigured env var doesn't silently break CORS.
_raw_origins = os.getenv("FRONTEND_URL", "http://localhost:3000")
_origins = [u.strip().rstrip("/") for u in _raw_origins.split(",") if u.strip()]
if not _origins:
    _origins = ["http://localhost:3000"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(ingest.router, prefix="/api")
app.include_router(ingest_worker.router, prefix="/api")
app.include_router(merge_resolve.router, prefix="/api")
app.include_router(messages.router, prefix="/api")
app.include_router(guest_auth.router, prefix="/api")
app.include_router(properties.router, prefix="/api")
app.include_router(telegram.router, prefix="/api")
app.include_router(whatsapp.router, prefix="/api")


@app.api_route("/health", methods=["GET", "HEAD"])
def health():
    return {"status": "ok"}
