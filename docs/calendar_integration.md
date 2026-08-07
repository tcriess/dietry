# Calendar integration

Two directions, four phases. Phases 1 and 2 are shipped; 3 and 4 are written
down here so the reasoning behind the cheap versions is not lost.

## Shipped

### Phase 1 — read: prefill a holiday from a calendar entry

`Holidays → "From calendar"` reads the phone's all-day events and lets the user
turn one into a holiday.

- `lib/services/calendar_service.dart` + `calendar_native.dart` /
  `calendar_stub.dart` — the `health_connect_*` conditional-import pattern.
  Mobile only; web and desktop get the stub and the entry point is hidden.
- Goes through the OS calendar provider (`device_calendar`), so every account
  the phone syncs — Google, Outlook, iCloud — is covered **without** the app
  holding a calendar OAuth token.
- Only all-day events are offered. A 14:00 dentist appointment is not a holiday,
  and offering it would invite marking that day a cheat day by accident.
- The picked event **prefills** the date-range picker and the name dialog. It
  never creates the holiday directly. See "Why confirmation is not optional".

### Phase 2 — write: export nutrition history as `.ics`

`Reports → calendar icon` writes the visible range out as an iCalendar file:
one all-day entry per logged day, calories in the summary and the macro
breakdown in the description.

- `lib/services/nutrition_ics_export.dart`, a pure function with unit tests.
- Goes out through `platform_export.dart` — a download on web, the share sheet
  on mobile, a chosen folder on desktop.
- Available in **every edition**: generated on the device from data already on
  screen, so it needs no backend.
- UIDs are stable (`dietry-nutrition-<yyyymmdd>@dietry.de`), so re-exporting an
  overlapping range updates the existing entries instead of stacking duplicates.

## Not built

### Phase 3 — recurring calendar → holiday sync

Turning the one-shot import into a subscription that keeps holidays in step with
the calendar.

**What it needs**

- A `V10` migration adding `holiday_source` and `external_uid` to `cheat_days`,
  so a re-sync can recognise an event it already imported.
- A rule for *which* events count. Ranked by how well they hold up:
  1. a user-chosen source calendar ("which calendar means vacation?") — one tap,
     beats every heuristic;
  2. an explicit marker in the title, e.g. `#cheat` — locale-proof;
  3. keyword matching (`Urlaub|Vacation|PTO`) — fragile across de/en/es, and the
     failure mode is silent.
- A confirmation step regardless: a checklist of detected ranges, not an
  automatic write.

**The rule that matters: the past is a record, the future is a plan.**
A re-sync may move or remove *future* days freely. It must never un-cheat a past
day that already has entries logged against it. Otherwise a calendar tidy-up in
December silently rewrites the user's summer statistics.

**Worth knowing before starting**

`DTEND` is exclusive for all-day events in both RFC 5545 and Android's
`CalendarContract`: 10–12 August is stored as 10 August → 13 August 00:00.
`_toCalendarEvent` normalises this on the way in and
`buildNutritionIcs` re-applies it on the way out. Every calendar integration
gets this wrong once; here it means one spurious cheat day per imported holiday.

### Phase 4 — a live subscribable feed (Cloud only)

`https://cloud.dietry.de/ics/<token>.ics`, subscribed once in Google or Apple
Calendar and always current. This is the version people actually want, and the
one that cannot be cheap:

- PostgREST will not serve `text/calendar` sanely and Neon has no `pg_net`, so
  it is a **new service**, not a new query. That makes it a poor fit for CE,
  whose deployment is a static web bundle plus PostgREST.
- A subscription URL is an unauthenticated bearer credential by construction.
  The calendar provider's servers fetch and cache it, and there is no revoking
  access short of rotating the token. Publishing calorie history to it means
  health data leaving the user's control permanently.
- If built: opt-in, rotatable token, and coarse by default (day totals, not
  every logged item).

## Why confirmation is not optional

A cheat day is not cosmetic. `daily_nutrition_summary` excludes it, so a false
positive does not merely add a label — it removes a day from the user's own
statistics. An event title is a hint about the world, not an instruction about
the user's diet. Every path here therefore proposes and lets the user confirm,
which also neutralises the `DTEND` ambiguity above: a mis-read range is visible
in the date picker before a single row is written.

## Rejected: Google Calendar API via OAuth

`calendar.readonly` is a *sensitive* scope, so going past the 100-user cap needs
Google app verification (brand review plus a demo video). Worse for this repo:
verification is per-Google-Cloud-project, so **every CE self-hoster would have to
run their own**. It buys nothing over the OS calendar provider on mobile, which
already sees the user's Google calendar.

## Rejected for now: secret ICS URL polling

Pasting a Google "secret address in iCal format" would work on every platform
with no permissions at all — except that Google's ical endpoint sends no CORS
headers, so the **web build cannot fetch it** without a proxy. It also means
storing a bearer credential to the user's entire calendar. Revisit only if
desktop/web demand appears.
