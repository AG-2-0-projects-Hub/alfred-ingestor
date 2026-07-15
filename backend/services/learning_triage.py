"""Automated-learning triage (ROADMAP Track 6 — self-learning loop quality gate).

Two layers decide whether a resolved escalation becomes reusable knowledge:

  Layer 1 (here): a deterministic gate on `escalation_reason`. Cheap, instant,
    and the hard safety guarantee — emergencies / hostility never learn, no
    matter what an LLM might think.
  Layer 2 (services.gemini_messenger.summarize_escalation): an LLM judgment of
    whether the Q&A is a stable, reusable fact vs a one-off/personal reply.

Only entries passing BOTH reach the host's Accept/Discard queue. Every outcome
(learned or dropped) is recorded, pseudonymized, in the learning_events ledger.
"""

# escalation_reasons whose resolutions are never worth learning. `emergency_*`
# is matched by prefix (emergency_fire, emergency_lockout, …).
_HARD_DROP_REASONS = {
    "guest_hostility",
    "out_of_scope_request",
    "financial_request",
}


def reason_disposition(escalation_reason: str | None) -> str:
    """Layer 1. Return 'drop' (never learn) or 'evaluate' (send to Layer 2).

    A null reason means the host took over manually (no auto-escalation category)
    — let the content check decide rather than dropping blindly.
    """
    reason = (escalation_reason or "").strip().lower()
    if reason.startswith("emergency"):
        return "drop"
    if reason in _HARD_DROP_REASONS:
        return "drop"
    return "evaluate"


def layer1_skip_reason(escalation_reason: str | None) -> str:
    """Coarse label stored on a Layer-1 drop (for ledger analytics)."""
    reason = (escalation_reason or "").strip().lower()
    return "emergency" if reason.startswith("emergency") else (reason or "unknown")
