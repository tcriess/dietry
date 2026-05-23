# Suggestion engine plan — Quick Add sheet

Roadmap for evolving the "Recent" list inside `lib/widgets/quick_food_entry_sheet.dart`
from a static "most recently logged" feed into a context-aware suggester.
Personal phases stay client-local; the deferred cross-user cold-start
(Phase 6) deliberately confines its surface to public foods only.

## Phase 1 — Time-of-day match (shipped)

The Recent list is ranked by `(mealType matches current selection,
hour-of-day distance to now, recency)`, then deduped by name. Tapping a
different meal-type chip re-ranks live without a network call.

See `_rankAndDedupRecent` / `_compareRecent` in `quick_food_entry_sheet.dart`.

## Phase 2 — Co-occurrence within a meal session (shipped)

`_CooccurrenceIndex` builds from the same 90-day fetch. After every add the
sheet surfaces up-to-three foods the user typically logs alongside the
just-added item in the same `(date, mealType)` bucket, ranked by
`P(B|A) = co[A][B] / occ[A]` with `minSupport ≥ 2`.

## Phase 3 — Daily / weekly recurrence (shipped)

`_RecurrenceIndex` counts distinct dates per `(name, mealType, weekday)`
slot over the 90-day window. Names that appear on `≥4` matching slots
sort to the very top of the Recent list (count-descending tiebreak),
ahead of the phase-1 meal-type/hour-distance heuristic.

Distinguishes "every Friday pizza" from "I once ate pizza on a Friday".
Uses `widget.date.weekday` so back-filling a past day still benefits from
that weekday's pattern.

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

## Phase 6 — Cross-user cold-start (deferred, public foods only)

For new users whose personal index is empty/sparse (< ~2 weeks of history),
seed suggestions from aggregated patterns across all users — **strictly
restricted to public `food_database` rows** so that:

- **Privacy is solved by construction.** Public foods are public by
  definition; aggregating co-occurrence over them leaks nothing private.
  User-typed names and user-private foods are excluded entirely.
- **Name canonicalization is solved by construction.** Key on `food_id`,
  not on free-text name — sidesteps the "Banane" vs "banana, raw"
  fragmentation that would dilute the cross-user signal anyway.
- **Edition gate is natural.** Cloud Edition only (CE users are
  self-hosted and have no peer data).

Sketch:

- Postgres view / materialized view aggregating co-occurrence over pairs
  where both items have a non-null `food_id` linked to a public
  `food_database` row.
- `get_popular_cooccurrences(seed_food_id, limit)` SECURITY DEFINER
  function, returns `(other_food_id, support_count)` with
  `support_count ≥ ~10` (k-anonymity floor).
- Client falls back to the global index only when the personal one
  returns empty. Once the user has data, personal always wins.

**Phase 6B — Goal-similarity cohorts.** Bucket users into ~5–8 macro
profile cohorts via a nightly job (low-carb, balanced, high-protein,
vegetarian, …), then condition the global query on cohort id. Ship the
un-cohorted version first to see if it moves the needle for new users.

## UX placement notes

- "Suggested next" chips work best **after** the user logs something — a
  small chip row appears above Recent for ~5 s.
- When the sheet first opens with nothing logged yet, fall back to the
  phase-1 time-of-day-ranked Recent list.
- Avoid stacking too many lists side-by-side — the sheet is already dense.

## Deliberate non-goals

- **No cloud-side ML or telemetry.** Personal phases stay client-local.
- **No user-typed names in cross-user aggregation.** Phase 6 only ever
  joins on canonical public `food_database` rows.
