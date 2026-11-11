"""Stay dates for a guest: the host types calendar dates + a time zone, we keep ONE
instant (guests.check_out) so the per-message cutoff is a plain comparison.

check_out is the END of the check-out day in the stay's time zone — a guest is
never cut off before their real check-out, whatever hour that was. The chat then
stays open for GRACE more (follow-ups, forgotten items, feedback).
"""
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

GRACE = timedelta(hours=24)
# A link created without dates ("Add later") still gets an end, so no link lives
# forever. stay_timezone stays NULL until the host confirms real dates.
PROVISIONAL = timedelta(days=7)
# A typo'd year must not mint an effectively eternal link.
MAX_AHEAD = timedelta(days=366)


class StayError(ValueError):
    """Host-facing reason the dates were refused (mapped to HTTP 422)."""


def to_instants(
    check_in_date: str, check_out_date: str, tz_name: str,
    now: datetime | None = None,
) -> tuple[datetime, datetime]:
    """('2026-11-10', '2026-11-12', 'America/Mexico_City') -> (check_in, check_out)
    as UTC instants: start of the check-in day, end of the check-out day."""
    now = now or datetime.now(timezone.utc)
    try:
        tz = ZoneInfo(tz_name)
        d_in = date.fromisoformat(check_in_date)
        d_out = date.fromisoformat(check_out_date)
    except (ValueError, KeyError, OSError):
        raise StayError("Enter valid dates (YYYY-MM-DD) and a valid time zone.")
    if d_out < d_in:
        raise StayError("Check-out can't be before check-in.")
    check_in = datetime.combine(d_in, time.min, tzinfo=tz)
    check_out = datetime.combine(d_out + timedelta(days=1), time.min, tzinfo=tz)
    if check_out - now > MAX_AHEAD:
        raise StayError("Check-out is more than a year away — check the date.")
    return check_in.astimezone(timezone.utc), check_out.astimezone(timezone.utc)


def is_over(check_out: str | None, now: datetime | None = None) -> bool:
    """True once check_out + GRACE has passed. A missing or unreadable value is
    never "over" — better to answer a guest than to lock one out by mistake."""
    if not check_out:
        return False
    try:
        end = datetime.fromisoformat(check_out.replace("Z", "+00:00"))
    except ValueError:
        return False
    return (now or datetime.now(timezone.utc)) > end + GRACE


def _STAY_TEST() -> None:
    utc = timezone.utc
    now = datetime(2026, 11, 9, 12, tzinfo=utc)
    # Mexico City is UTC-6 in November: end of 12 Nov local = 13 Nov 06:00 UTC.
    cin, cout = to_instants("2026-11-10", "2026-11-12", "America/Mexico_City", now)
    assert cin == datetime(2026, 11, 10, 6, tzinfo=utc), cin
    assert cout == datetime(2026, 11, 13, 6, tzinfo=utc), cout
    # Same-day stay is valid; check-out before check-in is not.
    to_instants("2026-11-10", "2026-11-10", "UTC", now)
    for bad in (("2026-11-12", "2026-11-10", "UTC"),
                ("2026-11-10", "2026-11-12", "Not/AZone"),
                ("nope", "2026-11-12", "UTC"),
                ("2026-11-10", "2028-01-01", "UTC")):
        try:
            to_instants(*bad, now)
        except StayError:
            continue
        raise AssertionError(f"accepted {bad}")
    # Cutoff: still open right at check_out + 24 h, closed a second later.
    stamp = cout.isoformat()
    assert not is_over(stamp, cout + GRACE)
    assert is_over(stamp, cout + GRACE + timedelta(seconds=1))
    assert not is_over(None) and not is_over("garbage")
    print("_STAY_TEST: PASS")


if __name__ == "__main__":
    _STAY_TEST()
