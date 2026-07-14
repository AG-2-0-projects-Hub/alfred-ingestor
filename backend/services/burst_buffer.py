"""Guests type the way people talk — one thought split across several messages:

    "Chichis con carne y mayonesa"   "Dos perros"   "Y tres gatos"

Answering each one separately produces three disconnected replies to what was a
single question (observed in prod 2026-07-13). This is the same shape as the
Telegram photo album: several inbound events that must become ONE turn.

So it gets the same cure — collect the messages, then run the Brain once, a
moment after the guest stops typing. The flush is scheduled exactly once per
conversation via a Cloud Task named after it (duplicate names are rejected), so
messages 2..N ride along instead of each triggering their own reply.

The buffer is process memory, like the album buffer: the flush lands on the same
instance in practice, and the scheduled task carries the first message as a seed
so a guest is never left unanswered even if it doesn't.
"""
import os

# Seconds to wait for the rest of a burst. Long enough to catch a follow-up line,
# short enough that a lone question doesn't feel like it stalled — a Gemini turn
# already costs ~10-15s on top of this. (Raised 5→6 after live testing: a guest
# typing a second line needs a beat more than the model does.)
WINDOW_SECONDS = int(os.getenv("GUEST_BURST_WINDOW_SECONDS", "6"))

_buffers: dict[str, list[str]] = {}


def add(key: str, text: str) -> bool:
    """Append a message to `key`'s burst. True if it opened a new burst, i.e. the
    caller must schedule the flush (later messages must not schedule their own)."""
    existing = _buffers.get(key)
    if existing is None:
        _buffers[key] = [text]
        return True
    existing.append(text)
    return False


def pop(key: str, seed: list[str] | None = None) -> list[str]:
    """Take everything buffered for `key`. Falls back to `seed` (carried in the
    task payload) if this instance holds no buffer — degraded, never silent."""
    return _buffers.pop(key, None) or list(seed or [])


def combine(messages: list[str]) -> str:
    """One prompt for the Brain. Newline-joined keeps each line legible to the
    model as a separate utterance while reading as a single turn."""
    return "\n".join(m for m in messages if m)
