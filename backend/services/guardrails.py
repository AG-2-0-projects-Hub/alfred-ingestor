"""AI guardrails for the guest pipeline (ROADMAP Track 1, risks R2/R3).

Lean by design: env-tunable counters and a small keyword backstop, not a
moderation pipeline. The prompt rules in gemini_messenger.SYSTEM_PROMPT are the
primary defense; this module is the server-side backstop that does not trust
the model. All checks run at the single choke point
routers/messages.process_guest_message, so web and Telegram are both covered.
"""
import os
import re

# Per-conversation guest-message ceilings. A counter, not a quota engine:
# breaching skips the Gemini call (the cost) but the guest message is still
# stored, so the host always sees what was sent.
RATE_LIMIT_PER_HOUR = int(os.getenv("GUEST_RATE_LIMIT_PER_HOUR", "20"))
RATE_LIMIT_PER_DAY = int(os.getenv("GUEST_RATE_LIMIT_PER_DAY", "100"))

# Hard cap on what a single guest message can feed into the prompt.
MAX_GUEST_MESSAGE_CHARS = int(os.getenv("GUEST_MAX_MESSAGE_CHARS", "2000"))

# Media-burst escalation: a guest sending several PHOTOS in a short burst usually
# wants a human to look, so the conversation escalates to the host regardless of
# what the model replied. Only photos count — a voice note is ordinary
# conversation and never escalates on volume alone. Both values env-tunable.
MEDIA_ESCALATE_COUNT = int(os.getenv("GUEST_MEDIA_ESCALATE_COUNT", "2"))
MEDIA_BURST_WINDOW_MIN = int(os.getenv("GUEST_MEDIA_BURST_WINDOW_MINUTES", "10"))


def truncate_message(text: str) -> str:
    """Cap guest input length before it reaches storage or the prompt."""
    if len(text) <= MAX_GUEST_MESSAGE_CHARS:
        return text
    return text[:MAX_GUEST_MESSAGE_CHARS] + " …"


def _is_spanish(language: str | None) -> bool:
    return bool(language) and language.strip().lower().startswith(("es", "spa"))


def rate_limit_reply(language: str | None) -> str:
    if _is_spanish(language):
        return (
            "Has enviado bastantes mensajes en poco tiempo, así que haré una breve "
            "pausa. Tus mensajes quedaron guardados y tu anfitrión puede verlos — "
            "inténtalo de nuevo un poco más tarde."
        )
    return (
        "You've sent quite a few messages in a short time, so I'm taking a short "
        "pause. Your messages are saved and your host can see them — please try "
        "again a little later."
    )


def holding_reply(language: str | None) -> str:
    """Safe reply when the high-stakes backstop forces an escalation."""
    if _is_spanish(language):
        return (
            "Es un dato importante, así que prefiero confirmarlo con tu anfitrión "
            "antes de responderte — en breve tendrás la información correcta."
        )
    return (
        "That's an important detail, so let me confirm it with your host before "
        "answering — you'll have the correct information shortly."
    )


# ── High-stakes backstop (risk R2) ────────────────────────────────────────────
# Intent = the guest is asking for a field where a wrong answer is harmful
# (address, access codes, wifi password, check-in/out times). If the intent
# matches and the Master JSON has no matching data (or the field is conflicted),
# we force an escalation server-side instead of trusting the model's reply.
# Deliberately conservative: a miss here just falls back to the prompt rules.

_INTENT_MESSAGE_PATTERNS: list[tuple[str, re.Pattern]] = [
    (
        "access_code",
        re.compile(
            r"(door|lock\s?box|keypad|entry|gate|access|puerta|port[óo]n|cerradura|candado)"
            r"[^.!?\n]{0,40}(code|pin|combination|c[óo]digo|clave|contrase[ñn]a)"
            r"|(code|c[óo]digo|clave)[^.!?\n]{0,40}"
            r"(door|lock\s?box|entry|gate|access|puerta|entrada|acceso)"
            r"|how do (i|we) get in(to|side)?\b"
            r"|c[óo]mo (entro|entramos|abro la puerta)",
            re.IGNORECASE,
        ),
    ),
    (
        "wifi_password",
        re.compile(
            r"(wi[\s-]?fi|internet|network|red)[^.!?\n]{0,40}"
            r"(password|pass\b|key\b|clave|contrase[ñn]a)"
            r"|(password|clave|contrase[ñn]a)[^.!?\n]{0,40}(wi[\s-]?fi|internet|red)",
            re.IGNORECASE,
        ),
    ),
    (
        "address",
        re.compile(
            r"\b(exact\s+)?address\b|\bdirecci[óo]n\b"
            r"|where (exactly )?is the (house|property|place|apartment)"
            r"|how do (i|we) get (there|to the (house|property|place))"
            r"|c[óo]mo (llego|llegamos)|ubicaci[óo]n exacta",
            re.IGNORECASE,
        ),
    ),
    (
        "check_time",
        re.compile(
            r"(what time|when)[^.!?\n]{0,30}check[\s-]?(in|out)"
            r"|check[\s-]?(in|out)[^.!?\n]{0,20}(time|hour)"
            r"|(a qu[ée] hora|hora de)[^.!?\n]{0,20}"
            r"(check[\s-]?(in|out)|entrada|salida|llegada)",
            re.IGNORECASE,
        ),
    ),
]

# Which Master-JSON key-path fragments count as "the data exists" per intent.
_INTENT_DATA_KEYS: dict[str, tuple[str, ...]] = {
    "access_code": ("code", "lockbox", "keypad", "access", "entry"),
    "wifi_password": ("password", "contrasena"),
    "address": ("address", "direccion", "google_maps"),
    "check_time": ("check_in", "checkin", "check_out", "checkout",
                   "arrival", "departure", "entrada", "salida"),
}

_TIME_VALUE = re.compile(r"\b\d{1,2}:\d{2}\b|\b\d{1,2}\s*(am|pm|a\.m\.|p\.m\.|hrs?)\b",
                         re.IGNORECASE)

# The schema is dynamic and codes often live in prose fields (e.g.
# check_in.special_instructions: "lockbox code 4321 by the door"), so a code
# counts as present when a code-word sits near digits in any value too.
_CODE_IN_VALUE = re.compile(r"(code|c[óo]digo|clave|lock\s?box|keypad|pin)\D{0,20}\d",
                            re.IGNORECASE)


def _normalize(text: str) -> str:
    return (text.lower()
            .replace("ñ", "n").replace("á", "a").replace("é", "e")
            .replace("í", "i").replace("ó", "o").replace("ú", "u"))


def _scalar_paths(node, prefix: str = ""):
    """Yield (normalized_dotted_path, value) for every non-empty scalar leaf."""
    if isinstance(node, dict):
        for key, value in node.items():
            yield from _scalar_paths(value, f"{prefix}.{_normalize(str(key))}")
    elif isinstance(node, list):
        for item in node:
            yield from _scalar_paths(item, prefix)
    elif node not in (None, "", [], {}):
        yield prefix, node


def _data_present(intent: str, master_json: dict) -> bool:
    keys = _INTENT_DATA_KEYS[intent]
    for path, value in _scalar_paths(master_json or {}):
        if intent == "access_code" and _CODE_IN_VALUE.search(str(value)):
            return True
        if not any(k in path for k in keys):
            continue
        if intent == "access_code":
            # A real code has digits; a bare "access" prose field doesn't count
            # unless it carries one.
            if any(ch.isdigit() for ch in str(value)):
                return True
        elif intent == "check_time":
            # The section existing isn't enough — require an actual time value
            # (or an explicit *time* key) so the model can't guess "usually 11".
            if "time" in path or "hora" in path or _TIME_VALUE.search(str(value)):
                return True
        else:
            return True
    return False


def _data_conflicted(intent: str, master_json: dict) -> bool:
    conflicts = (master_json or {}).get("_conflict_locations") or []
    keys = _INTENT_DATA_KEYS[intent]
    return any(any(k in _normalize(str(loc)) for k in keys) for loc in conflicts)


def high_stakes_backstop(guest_message: str, master_json: dict) -> dict | None:
    """Return {"intent", "reason"} when the guest asks for a high-stakes field
    the Master JSON can't safely answer (missing or conflicted); else None."""
    for intent, pattern in _INTENT_MESSAGE_PATTERNS:
        if not pattern.search(guest_message):
            continue
        if _data_conflicted(intent, master_json):
            return {"intent": intent, "reason": "conflicting_information_in_database"}
        if not _data_present(intent, master_json):
            return {"intent": intent, "reason": "information_not_in_database"}
    return None
