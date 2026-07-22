# Cooked-Weight Entry — Implementation Plan

## Problem

Nutrition labels are legally declared for the food **as sold**, not as eaten
(Reg. (EU) 1169/2011). Barcode-scanned products are therefore almost always on a
*raw / dry* basis, while users weigh what is on the plate. Cooking changes weight
substantially:

| Food | Yield (cooked ÷ raw) | Error when logging cooked grams against a raw label |
|---|---|---|
| Pasta, boiled | 2.0–2.5 | **+100 … +150 %** |
| Rice, boiled | 2.0–3.0 | **+100 … +200 %** |
| Dry legumes | 2.4–2.7 | +140 … +170 % |
| Chicken breast, grilled | 0.70–0.75 | −25 … −30 % |
| Ground beef 80/20 | 0.70–0.75 | −25 … −30 % |
| Salmon, baked | 0.80–0.85 | −15 … −20 % |
| Spinach, sautéed | 0.30–0.50 | −50 … −70 % |
| Mushrooms / onions | 0.50–0.70 | −30 … −50 % |
| Potato, baked | 0.80–0.85 | −15 … −20 % |
| Bread, baked | 0.85–0.90 | −10 … −15 % |

Concretely: 140 g of cooked white rice logged against the dry label yields
≈ 511 kcal instead of ≈ 182 kcal. This is a *biased* error, not noise — it never
averages out, and it dwarfs the ±10–45 % uncertainty band we already model via
`EstimateLevel`.

Open Food Facts does not solve this for us. The API supports `_prepared`
nutriment suffixes and `nutrition_data_prepared_per`, but coverage is
effectively nil for the affected categories — a spot check of Barilla spaghetti
(`8076809513722`) has `nutrition_data_prepared_per: "100g"` set with *zero*
`*_prepared` nutriment keys. The field is declared and empty. This has to be
solved client-side.

Sources: USDA Table of Cooking Yields for Meat and Poultry (Release 2), USDA
Table of Nutrient Retention Factors (Release 6), Bognár (FAO) weight-yield and
retention tables, Reg. (EU) 1169/2011.

## Why it is cheap in Dietry

Two pieces already exist:

1. **The entry pipeline already multiplies by an arbitrary factor.** Both entry
   paths resolve grams before applying `grams / 100.0`
   (`add_food_entry_screen.dart:_currentGrams`,
   `quick_food_entry_sheet.dart:_currentAmountG`). The conversion is a single
   division inserted *before* that scaling; nutrition math is untouched.
2. **Per-food, per-user unit memory already ships.** `user_food_prefs
   (user_id, food_id, last_amount, last_unit)` is written on every save and
   batch-prefetched in the quick sheet. "Answer once per product, never again"
   falls out of `last_unit` for free.

## Decision: how the conversion is represented

**Rejected — synthetic `FoodPortion` with a fractional `amountG`.** Would carry
the feature in a ~10-line diff, but `food_entries.unit` would then store a
*localized display string*, so switching DE→EN breaks unit→grams resolution for
every stored entry (portions are matched by `name`). Also pollutes the portion
dropdown with a non-portion.

**Chosen — an explicit third custom unit, canonical token `g_cooked`**, sitting
alongside the existing `'g'` / `'ml'` custom units. Locale-independent on disk,
localized only at render time.

```
rawGrams = cookedGrams / yieldFactor      // then the existing / 100.0 scaling
```

## Phase 1 — MVP, no migration

### `lib/services/cooking_yield.dart` (new)

Pure, no I/O, CE-safe, unit-testable.

```dart
enum YieldKind { absorption, evaporation, fatLoss }

class CookingYieldInfo {
  final double factor;             // cooked ÷ raw
  final YieldKind kind;
  final EstimateLevel uncertainty; // spread added by using a generic factor
}

class CookingYield {
  static CookingYieldInfo? defaultFor(FoodItem food);
  static bool alreadyCooked(FoodItem food);
  static double toRawGrams(double cookedGrams, double factor);
}
```

Factor table: a `const` list of (keywords, factor, kind) matched against a
lowercased, unaccented `name` + `category`. Matching must be multilingual — the
database holds German BLS, English FDC and OFF products in any language — and
`OpenFoodFactsService._mapCategory` only ever emits hardcoded German buckets, so
category is a weak secondary signal at best.

| Group | Factor | Kind | Added uncertainty |
|---|---|---|---|
| Pasta | 2.2 | absorption | `low` |
| Rice | 2.6 | absorption | `low` |
| Dry legumes | 2.5 | absorption | `low` |
| Other grains (couscous, bulgur, quinoa, polenta, oats) | 2.6 | absorption | `low` |
| Poultry | 0.73 | fatLoss | `medium` |
| Red meat | 0.72 | fatLoss | `medium` |
| Fish | 0.82 | evaporation | `low` |
| Leaf vegetables | 0.40 | evaporation | `medium` |
| Mushrooms / onions | 0.60 | evaporation | `medium` |
| Potato | 0.82 | evaporation | `low` |

**`alreadyCooked()` is not optional.** The seed data ships `'Reis (gekocht)'`,
`'Ei (gekocht)'`, `'Kartoffel (gekocht)'`, and both BLS and FDC contain explicit
cooked variants. Offering a cooked unit on a food already expressed on a cooked
basis would divide twice — a 2.6× *under*count. When `alreadyCooked` is true the
unit is suppressed entirely.

A negative-keyword list (salat/salad, sauce/soße, suppe/soup, fertig) suppresses
composite dishes. When in doubt, return null: a missing option is harmless, a
wrong factor is not.

### Screen changes

`lib/screens/add_food_entry_screen.dart`

- `_buildPortionSelector()` — insert a `g_cooked` item after `'g'` when a yield
  info exists. Relabel the plain `'g'` item to "g (roh/trocken)" *only* when the
  cooked option is present, so nothing changes for foods this does not apply to.
- `onChanged` — `g_cooked` takes the existing custom-unit branch.
- `_currentGrams()` — insert the conversion. This makes `_computeTotals()` and
  the preview card correct for free.
- `_saveEntry()` — call `_currentGrams()` instead of recomputing grams inline;
  the two are currently duplicated and must not diverge.
- `_autoEstimate()` — `.orHigher(info.uncertainty)` when the cooked unit is
  selected.
- `_buildTotalsPreview()` — show "≈ 100 g roh". This is the trust-builder: the
  user watches the conversion happen.
- The liquid path must not produce an `amountMl` for `g_cooked`.

`lib/widgets/quick_food_entry_sheet.dart` (`_ConfirmDialog`)

- `_isGramMl` must **not** include `g_cooked` (it is not a 1:1 gram unit).
- `_currentAmountG()` — add the `g_cooked` branch before the portion lookup.
- `_availableUnits()` / `_onUnitChanged()` — mirror the above.

### Shared helper

`unitLabel()` and unit→grams resolution move into one place. The two screens
duplicate this logic today, and this feature makes the duplication dangerous.

### i18n

Add to `lib/l10n/intl_de.arb` **first** (it is the gen_l10n template), then
`intl_en.arb`, `intl_es.arb`: `unitGramsRaw`, `unitGramsCooked`, `cookedHintRaw`
(with a `{grams}` placeholder).

### Acceptance

Scan a Barilla barcode, pick "g (gekocht)", enter 220 → preview shows ≈ 348 kcal,
not ≈ 766, and the hint reads "≈ 100 g roh". Re-open the same product the next
day → cooked is preselected via `last_unit`.

## Phase 2 — barcode nudge

The error is born when an OFF product is confirmed, so intercept there.
`BarcodeLookupResult` already carries `fromOff`. When `fromOff` **and** a yield
info exists **and** the kind is `absorption` (dry goods — highest magnitude,
most certain), show a dismissible banner in the confirm sheet:

> ⚠️ Die Nährwerte auf der Packung gelten für die **rohe/trockene** Ware.
> Wiegst du gekocht? → **[ Auf gekocht umstellen ]**

The action only sets the unit — no new state. Suppress once the user has an
explicit `last_unit` for that food. The claim is factually safe: under
Reg. (EU) 1169/2011 the mandatory declaration *is* the as-sold state.

## Phase 3 — personal calibration (migration)

Published yield ranges are wide (pasta 2.0–2.5, rice 2.0–3.0) not because the
data is poor but because yield genuinely depends on how *this* user cooks — al
dente vs. soft, lid on vs. off. A generic factor removes ~90 % of the error; a
personal one removes ~99 %.

### `sql/migrations/V{next}__user_food_prefs_cooked_factor.sql`

```sql
ALTER TABLE public.user_food_prefs
  ADD COLUMN IF NOT EXISTS cooked_factor numeric(6,3);

ALTER TABLE public.user_food_prefs
  ADD CONSTRAINT user_food_prefs_cooked_factor_range
  CHECK (cooked_factor IS NULL OR (cooked_factor >= 0.1 AND cooked_factor <= 10));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_food_prefs TO authenticated;
```

No `BEGIN`/`COMMIT` (Flyway wraps each migration). Explicit `GRANT` per the
migration checklist. **No RPC signature changes** — `user_food_prefs` is read
directly via PostgREST, not through `search_food_database`. This is the main
reason to put the factor here rather than on `food_database`, which would drag
in three repeatable `RETURNS TABLE` signatures plus `FoodItem` serialization.

### `lib/services/user_food_prefs_service.dart`

- `UserFoodPref` gains `final double? cookedFactor`.
- `getForFoodIds` select list → `food_id,last_amount,last_unit,cooked_factor`.
- New `upsertCookedFactor({foodId, factor})` — kept separate from the existing
  `upsert`, which fires on every save and is not given a factor.

**Verify first:** the existing `upsert` uses
`Prefer: resolution=merge-duplicates`. PostgREST builds the
`ON CONFLICT DO UPDATE SET` list from the payload's keys, so a payload without
`cooked_factor` *should* leave it intact — confirm empirically on dev before
shipping. If it nulls the column, every ordinary food log silently wipes the
user's calibration.

### Calibration UI

Reachable from the unit dropdown ("Faktor anpassen…") and the food-database
detail screen:

```
Wie viel wird daraus?
  Trocken/roh gewogen:  [ 250 ] g
  Gekocht gewogen:      [ 560 ] g
  → Faktor 2,24  (Standard: 2,2)
```

When a user-set factor exists, `_autoEstimate()` does **not** bump the level — a
measured personal factor is as good as weighing.

### Offline mirror

Determine whether `user_food_prefs` is part of the local SQLite mirror. If it
is, this needs a local schema-version bump and a column add in
`LocalDataService`. If it is not, the factor requires connectivity on first use
and falls back to the Phase-1 default table offline — acceptable, but decide
deliberately rather than discovering it during testing.

## Out of scope

- **Per-nutrient accuracy for fried/grilled meat.** A single weight factor is
  structurally wrong there: pork loses ~25 % weight but only ~20 % energy,
  because fat drips out. This is why USDA/EuroFIR pair yield factors with
  separate *nutrient retention* factors. Phase 1 ships the toggle for meat with a
  `medium` uncertainty bump, which is honest; doing it properly is a separate
  data problem.
- **Cooked-state metadata on `food_database`** — would touch the table, three RPC
  signatures and `FoodItem` serialization. Not needed here.
- **Parsing OFF `serving_size` / `quantity`**, currently requested by
  `OpenFoodFactsService` and then discarded in `_parseProduct`. Adjacent,
  worthwhile, unrelated.

## Risks

| Risk | Mitigation |
|---|---|
| Double conversion on already-cooked rows | `alreadyCooked()` suppression + unit test |
| Matcher misfires on composite dishes | Negative-keyword list; return null when in doubt |
| `merge-duplicates` nulls `cooked_factor` | Verify on dev before Phase 3 UI exists |
| Unresolvable unit breaks re-log-from-recents | `_currentAmountG()` already returns null safely and shortcuts skip non-`g`/`ml` units — degrades, does not corrupt |
| Two divergent copies of unit logic | Extract the shared helper before Phase 3 adds branches |

## Sequencing

Phase 1 is independently shippable and carries nearly all the value; no
migration, so it rides a normal release with no deploy ordering. Phase 3 needs
the CE migration deployed to production before the release that uses it.
