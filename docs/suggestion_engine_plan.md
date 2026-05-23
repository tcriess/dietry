# Suggestion engine plan — Quick Add sheet

Roadmap for evolving the "Recent" list inside `lib/widgets/quick_food_entry_sheet.dart`
from a static "most recently logged" feed into a context-aware suggester. Keep
everything client-local — no telemetry, no cloud aggregation across users.

## Phase 1 — Time-of-day match (shipped)

The Recent list is ranked by `(mealType matches current selection,
hour-of-day distance to now, recency)`, then deduped by name. Tapping a
different meal-type chip re-ranks live without a network call.

See `_rankAndDedupRecent` / `_compareRecent` in `quick_food_entry_sheet.dart`.

## Phase 2 — Co-occurrence within a meal session

For each `(user, entry_date, mealType)` bucket in the last ~90 days, count
name pairs `{a, b}` that appear together. After the user logs item `a`,
surface the top 2–3 `b`'s by `count(a, b) / count(a)` as a "you usually also
log…" chip row, inline above the Recent list for ~5 s.

- Runs over the same `food_entries` fetch — no backend change.
- Cost: O(entries²) per bucket, but with ~10 entries/session × ~300 sessions
  this is sub-millisecond.
- Gives the "milk + cereal" / "rice + chicken" effect.

## Phase 3 — Daily / weekly recurrence

For each `(name, dayOfWeek, hourBucket)` count occurrences. If the user
logged coffee on the last 4 weekdays at 07–08, predict coffee and float it
to the very top *before* anything else.

Stronger signal than phase 1's hour-distance — distinguishes "every Friday
pizza" from "I once ate pizza on a Friday".

## Phase 4 — Macro-gap awareness

Late in the day, compare `goal − consumed` per macro and boost foods that
would close the largest remaining gap (short on protein → boost
chicken/quark/protein bar). The goal + day's entries are already in memory.

Combine with phase 3 by multiplying scores rather than picking one.

## Phase 5 — Server-side aggregation (only if needed)

If client-side recomputation per sheet-open ever feels sluggish, push
co-occurrence + recurrence counters into a Postgres materialized view
refreshed nightly per user. Probably unnecessary given the sheet is opened a
handful of times per day.

## UX placement notes

- "Suggested next" chips work best **after** the user logs something — a
  small chip row appears above Recent for ~5 s.
- When the sheet first opens with nothing logged yet, fall back to the
  phase-1 time-of-day-ranked Recent list.
- Avoid stacking too many lists side-by-side — the sheet is already dense.

## Deliberate non-goals

- **No cloud-side ML or telemetry.** Single-user, client-local only.
- **No "trending across all users".** Dietry is single-user-centric and the
  cross-user signal would dilute the personal one.
