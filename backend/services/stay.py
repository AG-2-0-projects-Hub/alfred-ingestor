"""Stay dates for a guest: the host types calendar dates (+ optional HH:MM times);
the time zone comes from the listing. We keep ONE instant per end
(guests.check_in / guests.check_out) so the per-message cutoff is a plain comparison.

check_out is the check-out date + time in the listing's zone. With NO time it is
the END of the check-out day (start of the next) — a guest is never cut off before
their real check-out, whatever hour that was. The chat then stays open for GRACE
more (follow-ups, forgotten items, feedback). Rule for reading an instant back:
local midnight = "no time given" (check-in = start of day, check-out = end of day).
"""
import re
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo, available_timezones

from services.welcome import _extract_country

GRACE = timedelta(hours=24)
# A link created without dates ("Add later") still gets an end, so no link lives
# forever. stay_timezone stays NULL until the host confirms real dates.
PROVISIONAL = timedelta(days=7)
# A typo'd year must not mint an effectively eternal link.
MAX_AHEAD = timedelta(days=366)


class StayError(ValueError):
    """Host-facing reason the dates were refused (mapped to HTTP 422)."""


_HHMM = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")


def _hhmm(text: str | None) -> time | None:
    """'15:00' -> time(15, 0); None for None/''; StayError for anything else."""
    if not text:
        return None
    m = _HHMM.match(text)
    if not m:
        raise StayError("Enter times as HH:MM (24 h), e.g. 15:00.")
    return time(int(m[1]), int(m[2]))


def to_instants(
    check_in_date: str, check_out_date: str, tz_name: str,
    now: datetime | None = None,
    *, check_in_time: str | None = None, check_out_time: str | None = None,
) -> tuple[datetime, datetime]:
    """('2026-11-10', '2026-11-12', 'America/Mexico_City') -> (check_in, check_out)
    as UTC instants. Without a time: start of the check-in day, end of the
    check-out day. With one: that local time on that date."""
    now = now or datetime.now(timezone.utc)
    try:
        tz = ZoneInfo(tz_name)
        d_in = date.fromisoformat(check_in_date)
        d_out = date.fromisoformat(check_out_date)
    except (ValueError, KeyError, OSError):
        raise StayError("Enter valid dates (YYYY-MM-DD) and a valid time zone.")
    if d_out < d_in:
        raise StayError("Check-out can't be before check-in.")
    t_in, t_out = _hhmm(check_in_time), _hhmm(check_out_time)
    check_in = datetime.combine(d_in, t_in or time.min, tzinfo=tz)
    check_out = (
        datetime.combine(d_out, t_out, tzinfo=tz) if t_out
        else datetime.combine(d_out + timedelta(days=1), time.min, tzinfo=tz)
    )
    if check_out <= check_in:
        raise StayError("Check-out can't be before check-in.")
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


def _parse_iso(value: str | None) -> datetime | None:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")) if value else None
    except ValueError:
        return None


def describe(
    check_in: str | None, check_out: str | None, tz_name: str | None,
    now: datetime | None = None,
) -> dict:
    """A guest's stay as the host reads it (local dates/times in the stay's zone),
    so the UI never does time-zone math. No zone = dates were never confirmed
    (provisional): only the instant the chat closes is returned."""
    cin, cout = _parse_iso(check_in), _parse_iso(check_out)
    ended = is_over(check_out, now)
    closes = cout + GRACE if cout else None
    try:
        tz = ZoneInfo(tz_name) if tz_name else None
    except (KeyError, OSError, ValueError):
        tz = None
    if not (tz and cin and cout):
        return {"provisional": True, "ended": ended,
                "closes_at": closes.isoformat() if closes else None}
    li, lo, lc = cin.astimezone(tz), cout.astimezone(tz), closes.astimezone(tz)
    out_whole = lo.time() == time.min  # no check-out time: midnight = end of the day before
    out_date = (lo.date() - timedelta(days=1)) if out_whole else lo.date()
    return {
        "provisional": False, "ended": ended, "timezone": tz_name,
        "check_in_date": li.date().isoformat(),
        "check_in_time": None if li.time() == time.min else li.strftime("%H:%M"),
        "check_out_date": out_date.isoformat(),
        "check_out_time": None if out_whole else lo.strftime("%H:%M"),
        # whole days: the chat is open through the whole day after check-out
        "closes_date": ((out_date + timedelta(days=1)) if out_whole else lc.date()).isoformat(),
        "closes_time": None if out_whole else lc.strftime("%H:%M"),
    }


# ── What we already know about the listing ───────────────────────────────────

_LISTING_TIME = re.compile(r"(\d{1,2})(?::(\d{2}))?\s*(?:([ap])\.?\s*m\b\.?)?", re.I)


def parse_listing_time(text: object) -> str | None:
    """'After 2:00 PM' / 'A partir de las 3:00 p.m.' / 'From 16:00' / '11 AM' ->
    'HH:MM'; the FIRST time in the text. None when there isn't a clear one (a
    bare number with neither minutes nor am/pm is not taken as a time)."""
    if not isinstance(text, str):
        return None
    for m in _LISTING_TIME.finditer(text):
        h, mins, ap = int(m[1]), int(m[2] or 0), (m[3] or "").lower()
        if not (m[2] or ap) or mins > 59:
            continue
        if ap:
            if not 1 <= h <= 12:
                continue
            h = h % 12 + (12 if ap == "p" else 0)
        elif h > 23:
            continue
        return f"{h:02d}:{mins:02d}"
    return None


# master_json is freeform: the same fact lives under several key names (seen on
# staging: check_in_out.check_in_time / .checkin_time, check_in.time, ...).
_TIME_PATHS = {
    "in": (("check_in_out", "check_in_time"), ("check_in_out", "checkin_time"),
           ("check_in", "time"), ("check_in", "check_in_time"),
           ("check_in_time",), ("checkin_time",), ("check_in",)),
    "out": (("check_in_out", "check_out_time"), ("check_in_out", "checkout_time"),
            ("check_out", "time"), ("check_out", "check_out_time"),
            ("check_out_time",), ("checkout_time",), ("check_out",)),
}


def _dig(data: object, path: tuple[str, ...]) -> object:
    for key in path:
        data = data.get(key) if isinstance(data, dict) else None
    return data


def listing_times(master_json: dict | None) -> tuple[str | None, str | None]:
    """(check_in 'HH:MM' | None, check_out 'HH:MM' | None) as the listing states them."""
    found = []
    for end in ("in", "out"):
        found.append(next(
            (t for p in _TIME_PATHS[end] if (t := parse_listing_time(_dig(master_json, p)))),
            None,
        ))
    return found[0], found[1]


# One MAIN zone per country, for listings without coordinates. A listing's own
# coordinates win (see zone_for), so this only decides Cancun-vs-Mexico-City style
# questions for listings that have none. Unknown country -> the host's browser zone.
# ponytail: curated list, add a country when a real listing falls outside it.
_COUNTRY_ZONE = {
    "America/Mexico_City": ("mexico", "méxico", "mexiko", "mexique"),
    "Europe/Paris": ("france", "frankreich", "francia"),
    "Europe/Madrid": ("spain", "españa", "espana", "spanien", "espagne"),
    "Europe/Berlin": ("germany", "deutschland", "alemania", "allemagne"),
    "Europe/Rome": ("italy", "italia", "italien", "italie"),
    "Europe/Lisbon": ("portugal",),
    "Europe/London": ("united kingdom", "uk", "england", "reino unido", "großbritannien", "royaume-uni"),
    "Europe/Amsterdam": ("netherlands", "the netherlands", "países bajos", "holanda", "niederlande", "pays-bas"),
    "America/New_York": ("united states", "usa", "us", "estados unidos", "ee.uu.", "vereinigte staaten", "états-unis"),
    "America/Toronto": ("canada", "canadá", "kanada"),
    "America/Bogota": ("colombia", "kolumbien"),
    "America/Lima": ("peru", "perú"),
    "America/Santiago": ("chile",),
    "America/Argentina/Buenos_Aires": ("argentina", "argentinien"),
    "America/Sao_Paulo": ("brazil", "brasil", "brasilien", "brésil"),
    "America/Guayaquil": ("ecuador",),
    "America/Guatemala": ("guatemala",),
    "America/Costa_Rica": ("costa rica",),
    "America/Panama": ("panama", "panamá"),
    "America/Santo_Domingo": ("dominican republic", "república dominicana", "republica dominicana"),
    "America/Montevideo": ("uruguay",),
}
_ZONE_BY_COUNTRY = {n: z for z, names in _COUNTRY_ZONE.items() for n in names}
_tzf = None


def _coords(master_json: dict | None) -> tuple[float, float] | None:
    loc = _dig(master_json, ("location", "coordinates"))
    if not isinstance(loc, dict):
        return None
    for la, lo in (("lat", "lng"), ("latitude", "longitude")):
        try:
            lat, lng = float(loc[la]), float(loc[lo])
        except (KeyError, TypeError, ValueError):
            continue
        if abs(lat) <= 90 and abs(lng) <= 180 and (lat, lng) != (0.0, 0.0):
            return lat, lng
    return None


def zone_for(master_json: dict | None) -> tuple[str | None, str | None]:
    """(IANA zone, 'coordinates' | 'country') of the LISTING, or (None, None).
    Coordinates -> exact (offline lookup); else the country's main zone."""
    global _tzf
    coords = _coords(master_json)
    if coords:
        try:
            if _tzf is None:
                from timezonefinder import TimezoneFinder
                _tzf = TimezoneFinder()
            zone = _tzf.timezone_at(lat=coords[0], lng=coords[1])
            if zone:
                return zone, "coordinates"
        except Exception:  # lib missing or failed: fall through to the country
            pass
    country = _extract_country(master_json)  # same two shapes the welcome copy reads
    if country:
        # "Frankreich (France)" -> try the whole text, then each part.
        for part in [country, *re.split(r"[()/,]", country)]:
            zone = _ZONE_BY_COUNTRY.get(part.strip().lower())
            if zone:
                return zone, "country"
    return None, None


def resolve_zone(master_json: dict | None, browser_tz: str | None) -> tuple[str | None, str | None]:
    """The listing's zone, else the host's browser zone (validated), else nothing."""
    zone, source = zone_for(master_json)
    if zone:
        return zone, source
    if browser_tz and browser_tz in available_timezones():
        return browser_tz, "browser"
    return None, None


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

    # ── times: exact local instants, DST-aware ──
    cin, cout = to_instants("2026-11-12", "2026-11-14", "America/Mexico_City", now,
                            check_in_time="15:00", check_out_time="11:00")
    assert cin == datetime(2026, 11, 12, 21, tzinfo=utc), cin       # UTC-6
    assert cout == datetime(2026, 11, 14, 17, tzinfo=utc), cout
    _, cout = to_instants("2026-07-01", "2026-07-03", "Europe/Berlin", now,
                          check_out_time="11:00")                   # UTC+2 in summer
    assert cout == datetime(2026, 7, 3, 9, tzinfo=utc), cout
    for bad in (dict(check_in_time="25:00"), dict(check_out_time="9:5"),
                dict(check_out_time="11am")):
        try:
            to_instants("2026-11-12", "2026-11-14", "UTC", now, **bad)
        except StayError:
            continue
        raise AssertionError(f"accepted {bad}")
    try:  # same day, check-out time before check-in time
        to_instants("2026-11-12", "2026-11-12", "UTC", now,
                    check_in_time="15:00", check_out_time="11:00")
        raise AssertionError("accepted check-out before check-in")
    except StayError:
        pass

    # ── describe: read an instant back as the host typed it ──
    d = describe(*(x.isoformat() for x in to_instants(
        "2026-11-12", "2026-11-14", "America/Mexico_City", now,
        check_in_time="15:00", check_out_time="11:00")), "America/Mexico_City", now)
    assert (d["check_in_date"], d["check_in_time"], d["check_out_date"], d["check_out_time"],
            d["closes_date"], d["closes_time"]) == (
        "2026-11-12", "15:00", "2026-11-14", "11:00", "2026-11-15", "11:00"), d
    d = describe(*(x.isoformat() for x in to_instants(
        "2026-11-12", "2026-11-14", "America/Mexico_City", now)), "America/Mexico_City", now)
    assert (d["check_in_time"], d["check_out_date"], d["check_out_time"],
            d["closes_date"], d["closes_time"]) == (None, "2026-11-14", None, "2026-11-15", None), d
    assert describe("2026-11-10T00:00:00+00:00", "2026-11-17T00:00:00+00:00", None, now)["provisional"]

    # ── listing times: the wordings seen on real listings ──
    for text, want in (("After 2:00 PM", "14:00"), ("A partir de las 3:00 p.m.", "15:00"),
                       ("3:00 PM onwards", "15:00"), ("15:00", "15:00"), ("From 16:00", "16:00"),
                       ("Before 11:00 AM", "11:00"), ("12:30 p.m.", "12:30"), ("11 AM", "11:00"),
                       ("12 AM", "00:00"), ("Flexible", None), ("3", None), (None, None)):
        assert parse_listing_time(text) == want, (text, parse_listing_time(text))
    assert listing_times({"check_in_out": {"check_in_time": "After 2:00 PM",
                                           "check_out_time": "Before 11:00 AM"}}) == ("14:00", "11:00")
    assert listing_times({"check_in": {"time": "14:00"}, "check_out": {"time": "11:00"}}) == ("14:00", "11:00")
    assert listing_times({"check_in_out": {"checkin_time": "3:00 p.m.", "checkout_time": "11:00 a.m."}}) == ("15:00", "11:00")
    assert listing_times({}) == (None, None) and listing_times(None) == (None, None)

    # ── zone: coordinates beat country; country; browser; nothing ──
    assert zone_for({"location": {"coordinates": {"lat": 21.16, "lng": -86.85},
                                  "country": "Mexico"}}) == ("America/Cancun", "coordinates")
    assert zone_for({"location": {"coordinates": {"latitude": 32.5, "longitude": -117.0}}}) == ("America/Tijuana", "coordinates")
    assert zone_for({"location": {"coordinates": {"latitude": None, "longitude": None}, "country": "México"}}) == ("America/Mexico_City", "country")
    assert zone_for({"location": {"address": {"country": "Mexiko"}}}) == ("America/Mexico_City", "country")
    assert zone_for({"location": {"country": "Frankreich (France)"}}) == ("Europe/Paris", "country")
    assert zone_for({"location": {"country": "Atlantis"}}) == (None, None) and zone_for(None) == (None, None)
    assert zone_for({"location": {"coordinates": {"lat": 0, "lng": 0}}}) == (None, None)
    assert resolve_zone({"location": {"country": "Atlantis"}}, "Europe/Berlin") == ("Europe/Berlin", "browser")
    assert resolve_zone({}, "Not/AZone") == (None, None) and resolve_zone({}, None) == (None, None)
    assert resolve_zone({"location": {"country": "Mexico"}}, "Europe/Berlin")[1] == "country"
    print("_STAY_TEST: PASS")


if __name__ == "__main__":
    _STAY_TEST()
