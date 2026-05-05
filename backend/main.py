import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
from routers import ingest

load_dotenv()

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


@app.get("/health")
def health():
    return {"status": "ok"}
