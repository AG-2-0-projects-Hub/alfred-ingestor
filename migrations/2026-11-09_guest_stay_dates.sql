-- Item C: stay dates on a guest + the post-check-out cutoff.
--
-- guests.check_in / check_out already exist (timestamptz) but held synthetic
-- testing defaults (created + 96 h). They now carry the real stay: the host types
-- calendar dates + a time zone, the backend stores the instants (check_out = END
-- of the check-out day in that zone) and process_guest_message stops answering
-- 24 h after check_out.
--
-- stay_timezone: the IANA zone the dates were entered in. NULL = the host has not
-- confirmed real dates, so check_in/check_out are provisional (a link created with
-- "Add later", or an existing guest backfilled below).
--
-- No new RLS/trigger: guests already allows SELECT only (guest: own booking; host:
-- own property's guests); every write goes through the service-role backend, which
-- checks ownership itself.

alter table public.guests add column if not exists stay_timezone text;

-- Backfill. Every existing guest holds a synthetic check_out, so enforcing the
-- cutoff as-is would lock real guests out. Founder-approved formula (2026-11-09):
-- a week from the guest's last activity. "created + 7 d" alone was rejected: it
-- would have expired 29 of 34 prod guests at once, 4 of them active in the last
-- 14 days. Guarded by stay_timezone IS NULL so a re-run never overwrites dates a
-- host has since confirmed.
update public.guests g
set check_out = greatest(
      g.created_at,
      coalesce(
        (select max(c.last_message_at) from public.conversations c
          where c.booking_id = g.booking_id),
        g.created_at)
    ) + interval '7 days'
where g.stay_timezone is null;
