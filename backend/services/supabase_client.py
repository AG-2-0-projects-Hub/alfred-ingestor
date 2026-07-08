import os
from datetime import datetime, timedelta, timezone
from supabase import create_client, Client

_client: Client | None = None


def get_client() -> Client:
    global _client
    if _client is None:
        url = os.environ["SUPABASE_URL"]
        key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
        _client = create_client(url, key)
    return _client


BUCKET = "Property_assets"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


# ── Property row ──────────────────────────────────────────────────────────────

def insert_property(
    property_id: str,
    name: str = "",
    airbnb_url: str = "",
    owner_id: str | None = None,
) -> None:
    """Upsert a row in the properties table, preserving existing fields.

    owner_id is set ONLY when the row is being created for the first time.
    On subsequent upserts (re-ingest, status update, etc.) the existing
    owner_id is preserved — never silently overwritten. Prevents accidental
    cross-tenant property transfer when two users ingest the same nickname
    (see BUG-004 / bug-backlog).
    """
    client = get_client()

    # Check if row already exists. If yes, never touch owner_id.
    existing = (
        client.table("properties")
        .select("id, owner_id")
        .eq("id", property_id)
        .maybe_single()
        .execute()
    )
    is_new_row = existing is None or existing.data is None

    row: dict = {"id": property_id, "updated_at": _now()}
    if name:
        row["name"] = name
    if airbnb_url:
        row["airbnb_url"] = airbnb_url
    if owner_id and is_new_row:
        row["owner_id"] = owner_id
    client.table("properties").upsert(row).execute()


def get_canonical_property(airbnb_url: str) -> dict | None:
    """Find an existing property by airbnb_url. Returns the row or None. (REQ-01, REQ-19)"""
    client = get_client()
    result = (
        client.table("properties")
        .select("id, status, name")
        .eq("airbnb_url", airbnb_url)
        .maybe_single()
        .execute()
    )
    return result.data if result else None


def get_canonical_property_by_name(name: str, owner_id: str | None = None) -> dict | None:
    """Find an existing property by nickname, scoped to a specific owner.

    Returns None unless an owner_id is provided — prevents cross-tenant
    name collisions where User B's "Bungalowww" ingest hijacks User A's
    property. (BUG-004 / bug-backlog)

    Anonymous / unauthenticated ingests (owner_id=None) deliberately get
    no canonical match — they will create a fresh property row.
    """
    if not owner_id:
        return None
    client = get_client()
    result = (
        client.table("properties")
        .select("id, status, name, owner_id")
        .eq("name", name)
        .eq("owner_id", owner_id)
        .is_("deleted_at", "null")  # B2: never treat a soft-deleted tombstone as
        .maybe_single()             # canonical — re-adding must create a fresh row,
        .execute()                  # not silently revive (and re-hide) the tombstone.
    )
    return result.data if result else None


def update_status(property_id: str, status: str) -> None:
    """PATCH properties SET status = <status>, updated_at = NOW() WHERE id = property_id."""
    client = get_client()
    client.table("properties").update(
        {"status": status, "updated_at": _now()}
    ).eq("id", property_id).execute()


def save_scraped_markdown(property_id: str, scraped_markdown: str) -> None:
    """Write scraped_markdown to the property row. Called by ingestor after scraper response. (REQ-27 reliability)"""
    client = get_client()
    client.table("properties").update(
        {"scraped_markdown": scraped_markdown, "updated_at": _now()}
    ).eq("id", property_id).execute()


def append_ingested_markdown(property_id: str, new_markdown: str) -> None:
    """Fetch existing ingested_markdown, append new_markdown, and save back."""
    client = get_client()
    result = (
        client.table("properties")
        .select("ingested_markdown")
        .eq("id", property_id)
        .single()
        .execute()
    )
    existing = (result.data or {}).get("ingested_markdown") or ""
    combined = existing + "\n\n---\n\n" + new_markdown if existing else new_markdown
    client.table("properties").update(
        {"ingested_markdown": combined, "updated_at": _now()}
    ).eq("id", property_id).execute()


# ── File fingerprints ─────────────────────────────────────────────────────────

def get_file_fingerprints(property_id: str) -> dict:
    """Fetch file_fingerprints JSONB for a property. Returns {} if row not found. (REQ-22)"""
    client = get_client()
    result = (
        client.table("properties")
        .select("file_fingerprints")
        .eq("id", property_id)
        .maybe_single()
        .execute()
    )
    return (result.data or {}).get("file_fingerprints") or {}


def update_file_fingerprints(property_id: str, fingerprints: dict) -> None:
    """Write updated file_fingerprints JSONB back to the property row. (REQ-22)"""
    client = get_client()
    client.table("properties").update(
        {"file_fingerprints": fingerprints, "updated_at": _now()}
    ).eq("id", property_id).execute()


# ── Storage ───────────────────────────────────────────────────────────────────

def list_upload_files(property_id: str) -> list[dict]:
    """List files at Property_assets/{property_id}/user_uploads/."""
    client = get_client()
    resp = client.storage.from_(BUCKET).list(
        f"{property_id}/user_uploads",
        {"limit": 100, "offset": 0, "sortBy": {"column": "name", "order": "asc"}},
    )
    return resp or []


def download_file(property_id: str, filename: str) -> bytes:
    """Download a file from Supabase Storage. Returns raw bytes."""
    client = get_client()
    path = f"{property_id}/user_uploads/{filename}"
    return client.storage.from_(BUCKET).download(path)


def move_files_in_storage(src_id: str, dest_id: str) -> None:
    """Move all user_uploads from src_id folder to dest_id folder. (REQ-01, REQ-19)"""
    client = get_client()
    files = list_upload_files(src_id)
    for f in files:
        src_path = f"{src_id}/user_uploads/{f['name']}"
        dest_path = f"{dest_id}/user_uploads/{f['name']}"
        try:
            client.storage.from_(BUCKET).move(src_path, dest_path)
        except Exception as exc:
            print(f"move_files_in_storage: failed to move {src_path} → {dest_path}: {exc}")


# ── Merge / Resolve ───────────────────────────────────────────────────────────

def get_property_for_merge(property_id: str) -> dict | None:
    """Fetch fields needed by the merge endpoint."""
    client = get_client()
    result = (
        client.table("properties")
        .select("status, scraped_markdown, ingested_markdown, master_json")
        .eq("id", property_id)
        .maybe_single()
        .execute()
    )
    return result.data if result else None


def save_merge_result(
    property_id: str,
    master_json_dict: dict,
    status: str,
    conflict_status: str,
) -> None:
    """Write master_json, status, and Conflict_status after a successful merge."""
    client = get_client()
    client.table("properties").update({
        "master_json": master_json_dict,
        "status": status,
        "Conflict_status": conflict_status,
        "updated_at": _now(),
    }).eq("id", property_id).execute()


def get_property_for_resolve(property_id: str) -> dict | None:
    """Fetch fields needed by the resolve endpoint."""
    client = get_client()
    result = (
        client.table("properties")
        .select("status, master_json, resolution_history")
        .eq("id", property_id)
        .maybe_single()
        .execute()
    )
    return result.data if result else None


def save_resolve_result(
    property_id: str,
    master_json_dict: dict,
    history_text_entry: str,
    history_json_entry: dict | None,
    status: str,
    conflict_status: str,
) -> None:
    """Append history_text_entry to resolution_history (append-only),
    replace resolution_history_json, and write the updated master_json."""
    client = get_client()
    existing_result = (
        client.table("properties")
        .select("resolution_history")
        .eq("id", property_id)
        .single()
        .execute()
    )
    existing = (existing_result.data or {}).get("resolution_history") or ""
    if history_text_entry:
        combined = existing + "\n\n---\n\n" + history_text_entry if existing else history_text_entry
    else:
        combined = existing
    client.table("properties").update({
        "master_json": master_json_dict,
        "resolution_history": combined,
        "resolution_history_json": history_json_entry,
        "status": status,
        "Conflict_status": conflict_status,
        "updated_at": _now(),
    }).eq("id", property_id).execute()


# ── Messenger ─────────────────────────────────────────────────────────────────

def get_guest_by_booking_id(booking_id: str) -> dict | None:
    client = get_client()
    result = (
        client.table("guests")
        .select("id, name, booking_id, property_id, preferred_language, telegram_chat_id")
        .eq("booking_id", booking_id)
        .maybe_single()
        .execute()
    )
    return result.data if result else None


def get_guest_by_telegram_chat_id(chat_id: str) -> dict | None:
    """Find the guest linked to a Telegram chat (via /start <booking_id>)."""
    client = get_client()
    result = (
        client.table("guests")
        .select("id, name, booking_id, property_id, preferred_language, telegram_chat_id")
        .eq("telegram_chat_id", str(chat_id))
        .maybe_single()
        .execute()
    )
    return result.data if result else None


def link_guest_telegram(booking_id: str, chat_id: str) -> None:
    """Attach a Telegram chat to a guest booking.

    A Telegram account maps to exactly one booking (unique index on
    telegram_chat_id). So first RELEASE this chat from any other booking it was
    linked to, then attach it here. This makes /start on a new booking MOVE the
    link instead of hitting a unique violation — needed for a returning guest
    (new stay, same Telegram) and for testing several bookings from one account.
    """
    client = get_client()
    cid = str(chat_id)
    client.table("guests").update({"telegram_chat_id": None}) \
        .eq("telegram_chat_id", cid).neq("booking_id", booking_id).execute()
    client.table("guests").update({"telegram_chat_id": cid}) \
        .eq("booking_id", booking_id).execute()


def update_guest_language(booking_id: str, language: str) -> None:
    """Persist the established conversation language so future turns have a stable
    anchor (avoids re-detecting from scratch each message). Only meaningful,
    non-empty values are written."""
    if not language or not language.strip():
        return
    client = get_client()
    client.table("guests").update(
        {"preferred_language": language.strip().lower()}
    ).eq("booking_id", booking_id).execute()


def get_guest_by_conversation_id(conversation_id: str) -> dict | None:
    """Resolve the guest behind a conversation — used to deliver a host reply to
    the guest's Telegram chat when they're Telegram-linked."""
    client = get_client()
    conv = (
        client.table("conversations")
        .select("booking_id")
        .eq("id", conversation_id)
        .maybe_single()
        .execute()
    )
    if not (conv and conv.data):
        return None
    return get_guest_by_booking_id(conv.data["booking_id"])


def get_property_for_chat(property_id: str) -> dict | None:
    client = get_client()
    result = (
        client.table("properties")
        .select("id, master_json, name, learned_knowledge, deleted_at, welcome_also_english")
        .eq("id", property_id)
        .maybe_single()
        .execute()
    )
    return result.data if result else None


def find_or_create_conversation(booking_id: str, property_id: str) -> dict:
    client = get_client()
    result = (
        client.table("conversations")
        .select("*")
        .eq("booking_id", booking_id)
        .maybe_single()
        .execute()
    )
    if result and result.data:
        return result.data
    insert_result = client.table("conversations").insert({
        "booking_id": booking_id,
        "property_id": property_id,
        "requires_attention": False,
        "mode": "autopilot",
        "ai_status": "active",
        "last_message_at": _now(),
    }).execute()
    return insert_result.data[0]


def ensure_conversation_with_welcome(
    booking_id: str, property_id: str, welcome_text: str
) -> tuple[dict, bool]:
    """Get-or-create the conversation and, if it has no messages yet, post the
    welcome as Alfred's first message. Returns (conversation, welcome_inserted).

    Idempotent: safe to call on every /start and every guest-token load — the
    welcome is inserted at most once (only when the thread is empty).
    """
    client = get_client()
    conversation = find_or_create_conversation(booking_id, property_id)
    existing = (
        client.table("messages")
        .select("id")
        .eq("conversation_id", conversation["id"])
        .limit(1)
        .execute()
    )
    if existing.data:
        return conversation, False
    insert_message(conversation["id"], "ai", welcome_text)
    return conversation, True


def count_recent_guest_messages(conversation_id: str, since_iso: str) -> int:
    """Guest messages in this conversation since `since_iso` (rate limiting).

    NOTE: `messages` currently has no index beyond its PK, so this filters via
    a scan — fine at current volume. Index TODO (pending approval):
    CREATE INDEX idx_messages_conversation_created ON messages (conversation_id, created_at);
    """
    client = get_client()
    result = (
        client.table("messages")
        .select("id", count="exact")
        .eq("conversation_id", conversation_id)
        .eq("sender_type", "guest")
        .gte("created_at", since_iso)
        .execute()
    )
    return result.count or 0


def get_conversation_messages(conversation_id: str) -> list[dict]:
    client = get_client()
    result = (
        client.table("messages")
        .select("sender_type, content, created_at")
        .eq("conversation_id", conversation_id)
        .order("created_at")
        .execute()
    )
    return result.data or []


def insert_message(
    conversation_id: str,
    sender_type: str,
    content: str,
    sentiment: str | None = None,
    is_escalated_interaction: bool = False,
    used_learned_knowledge: bool = False,
    message_type: str = "text",
    media_url: str | None = None,
) -> dict:
    client = get_client()
    row: dict = {
        "conversation_id": conversation_id,
        "sender_type": sender_type,
        "content": content,
        "sentiment": sentiment,
        "status": "delivered",
        "is_escalated_interaction": is_escalated_interaction,
        "used_learned_knowledge": used_learned_knowledge,
        "message_type": message_type,
    }
    if media_url:
        row["media_url"] = media_url
    result = client.table("messages").insert(row).execute()

    # First guest message flips the conversation out of the "Awaiting reply"
    # (pending) state on the dashboard. Guarded so it writes at most once.
    if sender_type == "guest":
        client.table("conversations").update({"has_guest_message": True}) \
            .eq("id", conversation_id).eq("has_guest_message", False).execute()

        # Reactivate an archived conversation: a new guest message pulls it back
        # into the active list (covers both auto-archive on check_out and manual
        # host archive). Done unconditionally — clearing an already-null
        # archived_at is a harmless no-op, and bumping last_message_at on each
        # guest message is correct anyway (it also stops the hourly cron from
        # immediately re-archiving a conversation revived after check_out).
        client.table("conversations").update(
            {"archived_at": None, "last_message_at": _now()}
        ).eq("id", conversation_id).execute()

    # A BEFORE INSERT trigger (suppress_dup_system_marker) can skip a duplicate
    # consecutive system marker, in which case no row is returned. Callers of
    # marker inserts ignore the return; guard so we don't IndexError on skip.
    return result.data[0] if result.data else {}


def get_conversation_thread_for_resolve(
    booking_id: str,
) -> tuple[str | None, list[dict], str | None]:
    """Returns (conversation_id, messages, escalation_reason) where messages are
    all rows since the earliest unresolved escalated message, including host
    replies and guest follow-ups. `escalation_reason` is read here (before
    resolve_conversation nulls it) so the learning triage can gate on it.
    Returns (None, [], None) if no conversation found."""
    client = get_client()
    conv_result = (
        client.table("conversations")
        .select("id, escalation_reason")
        .eq("booking_id", booking_id)
        .maybe_single()
        .execute()
    )
    if not (conv_result and conv_result.data):
        return None, [], None
    conv_id = conv_result.data["id"]
    escalation_reason = conv_result.data.get("escalation_reason")
    first_esc = (
        client.table("messages")
        .select("created_at")
        .eq("conversation_id", conv_id)
        .eq("is_escalated_interaction", True)
        .is_("resolution_status", "null")
        .order("created_at")
        .limit(1)
        .execute()
    )
    if not first_esc.data:
        return conv_id, []
    threshold = first_esc.data[0]["created_at"]
    thread = (
        client.table("messages")
        .select("id, sender_type, content, created_at, is_escalated_interaction")
        .eq("conversation_id", conv_id)
        .gte("created_at", threshold)
        .order("created_at")
        .execute()
    )
    return conv_id, (thread.data or [])


def resolve_conversation(
    conversation_id: str,
    property_id: str,
    learned_entry: dict | None,
) -> None:
    """Atomically de-escalate a conversation and (optionally) append the learned
    Q&A entry to properties.learned_knowledge."""
    client = get_client()

    client.table("messages").update({
        "is_learned": True,
        "resolution_status": "resolved",
    }).eq("conversation_id", conversation_id) \
      .eq("is_escalated_interaction", True) \
      .is_("resolution_status", "null") \
      .execute()

    client.table("conversations").update({
        "mode": "autopilot",
        "requires_attention": False,
        "escalation_reason": None,
        "ai_status": "active",
        "last_message_at": _now(),
    }).eq("id", conversation_id).execute()

    if learned_entry:
        existing = (
            client.table("properties")
            .select("learned_knowledge")
            .eq("id", property_id)
            .single()
            .execute()
        )
        current_arr = (existing.data or {}).get("learned_knowledge") or []
        if not isinstance(current_arr, list):
            current_arr = []
        current_arr.append(learned_entry)
        client.table("properties").update({
            "learned_knowledge": current_arr,
            "updated_at": _now(),
        }).eq("id", property_id).execute()


def record_learning_event(
    property_id: str | None,
    booking_id: str | None,
    escalation_reason: str | None,
    disposition: str,
    skip_reason: str | None = None,
    problem_summary: str | None = None,
    solution_summary: str | None = None,
    category: str | None = None,
    language: str | None = None,
) -> None:
    """Append one row to the pseudonymized learning_events ledger (permanent
    internal record of every triage decision — learned or dropped). No guest
    name/PII: the summarizer is instructed to omit it, and only property_id +
    booking_id (opaque) are stored. Best-effort — never fail the resolve."""
    client = get_client()
    client.table("learning_events").insert({
        "property_id": property_id,
        "booking_id": booking_id,
        "escalation_reason": escalation_reason,
        "problem_summary": problem_summary,
        "solution_summary": solution_summary,
        "category": category,
        "language": language,
        "disposition": disposition,
        "skip_reason": skip_reason,
    }).execute()


def update_conversation(conversation_id: str, **fields) -> None:
    client = get_client()
    fields["last_message_at"] = _now()
    client.table("conversations").update(fields).eq("id", conversation_id).execute()


def archive_conversation(conversation_id: str) -> None:
    """Manually archive a conversation (host "delete conversation" action).

    Non-destructive: messages/training are kept and the conversation returns to
    the active list if the guest sends a new message (see insert_message)."""
    client = get_client()
    client.table("conversations").update(
        {"archived_at": _now()}
    ).eq("id", conversation_id).execute()


# ── Storage ───────────────────────────────────────────────────────────────────

# ── Knowledge injection ───────────────────────────────────────────────────────

def update_master_json(property_id: str, master_json_dict: dict) -> None:
    """Overwrite master_json only — does not touch status or Conflict_status."""
    client = get_client()
    client.table("properties").update(
        {"master_json": master_json_dict, "updated_at": _now()}
    ).eq("id", property_id).execute()


# ── Guest / booking ───────────────────────────────────────────────────────────

def create_guest(
    booking_id: str,
    property_id: str,
    name: str,
    guest_chat_url: str,
    host_chat_url: str,
) -> dict:
    """Insert a new guest booking row and return it."""
    client = get_client()
    now = datetime.now(timezone.utc)
    result = client.table("guests").insert({
        "booking_id": booking_id,
        "property_id": property_id,
        "name": name,
        # Start neutral — the working language is established from the actual
        # conversation, not seeded to English (which caused false "switches").
        "preferred_language": "not_set",
        "guest_chat_url": guest_chat_url,
        "host_chat_url": host_chat_url,
        # Testing defaults until Channex.io feeds real reservation dates: the
        # stay starts now and runs 96h. check_out drives auto-archiving of the
        # conversation once it passes (pg_cron job auto-archive-conversations).
        "check_in": now.isoformat(),
        "check_out": (now + timedelta(hours=96)).isoformat(),
    }).execute()
    return result.data[0]


def get_guests_for_property(property_id: str) -> list[dict]:
    """Return all guests for a property joined with their conversation row."""
    client = get_client()
    result = (
        client.table("guests")
        .select("id, booking_id, name, guest_chat_url, host_chat_url, conversations(mode, last_message_at, requires_attention, ai_status)")
        .eq("property_id", property_id)
        .order("booking_id")
        .execute()
    )
    return result.data or []


# ── Soft delete ─────────────────────────────────────────────────────────────

def get_user_id_from_token(access_token: str) -> str | None:
    """Validate a host access token against Supabase Auth and return the user
    id (sub). Uses GoTrue's /user endpoint (algorithm-agnostic) rather than
    local HS256 verification, because the project migrated to asymmetric JWT
    signing keys — host session tokens are no longer signed with the legacy
    HS256 secret, so local jwt.decode(..., HS256) would reject them."""
    client = get_client()
    try:
        resp = client.auth.get_user(access_token)
    except Exception:
        return None
    if resp and getattr(resp, "user", None):
        return resp.user.id
    return None


def soft_delete_property(property_id: str, owner_id: str) -> str:
    """Soft-delete a property: blank its ingested/scraped/master data, drop its
    storage files, anonymize its guests' names, and stamp deleted_at — while
    deliberately KEEPING the property row (as a tombstone) plus all
    conversations and messages, which we retain for internal AI training.

    Ownership is enforced here: returns "not_found" if the row is missing and
    "forbidden" if owner_id doesn't match. Returns "ok" on success.
    """
    client = get_client()
    existing = (
        client.table("properties")
        .select("id, owner_id")
        .eq("id", property_id)
        .maybe_single()
        .execute()
    )
    if existing is None or existing.data is None:
        return "not_found"
    if existing.data.get("owner_id") != owner_id:
        return "forbidden"

    # Blank the property data columns + stamp the tombstone FIRST, so the
    # delete the host sees is durable even if a later best-effort step fails.
    # NOTE: learned_knowledge is NOT NULL — clear it to [] (an empty array),
    # never None, or the whole update is rejected and nothing gets deleted.
    client.table("properties").update({
        "master_json": None,
        "ingested_markdown": None,
        "scraped_markdown": None,
        "file_fingerprints": None,
        "learned_knowledge": [],
        "resolution_history": None,
        "resolution_history_json": None,
        "status": "deleted",
        "deleted_at": _now(),
        "updated_at": _now(),
    }).eq("id", property_id).execute()

    # Anonymize guests — keep the rows (FK + chat linkage) but strip the
    # personal name down to a non-identifying label derived from the booking.
    guests = (
        client.table("guests")
        .select("id, booking_id")
        .eq("property_id", property_id)
        .execute()
    ).data or []
    for g in guests:
        bid = (g.get("booking_id") or g["id"]) or ""
        suffix = bid[-5:] if len(bid) >= 5 else bid
        client.table("guests").update({"name": f"Guest {suffix}"}).eq("id", g["id"]).execute()

    # Remove all stored files for the property (best-effort).
    _delete_property_storage(property_id)
    return "ok"


def _delete_property_storage(property_id: str) -> None:
    """Best-effort removal of all objects under the property's storage prefix."""
    client = get_client()
    paths: list[str] = []
    for sub in ("user_uploads", "hero_image"):
        try:
            files = client.storage.from_(BUCKET).list(
                f"{property_id}/{sub}", {"limit": 1000, "offset": 0}
            )
            for f in files or []:
                paths.append(f"{property_id}/{sub}/{f['name']}")
        except Exception as exc:
            print(f"_delete_property_storage: list {sub} failed: {exc}")
    if paths:
        try:
            client.storage.from_(BUCKET).remove(paths)
        except Exception as exc:
            print(f"_delete_property_storage: remove failed: {exc}")


# ── Storage ───────────────────────────────────────────────────────────────────

def upload_hero_image(property_id: str, image_url: str) -> None:
    """Download thumbnail from Airbnb URL and store under {property_id}/hero_image/main.jpg. (REQ-18)"""
    import httpx

    client = get_client()
    resp = httpx.get(image_url, timeout=30, follow_redirects=True)
    resp.raise_for_status()
    content_type = resp.headers.get("content-type", "image/jpeg").split(";")[0].strip()
    path = f"{property_id}/hero_image/main.jpg"
    client.storage.from_(BUCKET).upload(
        path,
        resp.content,
        file_options={"content-type": content_type, "upsert": "true"},
    )
