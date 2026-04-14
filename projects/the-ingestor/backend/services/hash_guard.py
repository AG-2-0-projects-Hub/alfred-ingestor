import hashlib
import os

# Simple in-memory store per process. For a production restart-safe guard,
# persist hashes to a Supabase table or Redis.
_processed: set[str] = set()

_GUARD_FILE = os.path.join(os.path.dirname(__file__), ".processed_hashes")


def _load() -> None:
    if os.path.exists(_GUARD_FILE):
        with open(_GUARD_FILE) as f:
            for line in f:
                h = line.strip()
                if h:
                    _processed.add(h)


def _persist(sha: str) -> None:
    with open(_GUARD_FILE, "a") as f:
        f.write(sha + "\n")


_load()


def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def already_processed(sha: str) -> bool:
    return sha in _processed


def mark_processed(sha: str) -> None:
    _processed.add(sha)
    _persist(sha)
