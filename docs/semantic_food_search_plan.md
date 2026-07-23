# Semantic meal-description search — implementation plan

Status: **PLANNING** (no code/DB changes yet). Written 2026-07-23.

## Goal

Make the "describe your meal" flow match parsed food names by **meaning**, not
just spelling — so "gaspaccho" reaches a tomato/vegetable soup, "grilled chicken
breast" reaches the right poultry row, and near-synonyms/foreign spellings match
even when trigram similarity is far too low.

This is **not** a greenfield feature. Describe-your-meal already exists (the
nutrition-uncertainty project, Phases 2 & 3): an offline heuristic parser
(`MealDescriptionParser`), an on-device LLM parser (`AiMealParser`, cactus +
smollm2-360m, Pro/mobile), voice input, and a matcher (`MealSuggestionService`).
The single gap is the **matching step**.

## Where it plugs in

`lib/services/meal_suggestion_service.dart`:

- `MealSuggestionService._bestMatch(query)` calls
  `FoodDatabaseService.searchFoods(query, limit: 1)`, which is the server RPC
  `search_food_database` (pg_trgm fuzzy). Its own comment states the limit:
  *"the food search matches spelling, not meaning, so it can never get from
  'gaspaccho' to a tomato soup (word_similarity 0.357)."*
- There is already an `AliasResolver` seam: when the AI parser is active,
  unmatched items get a second chance via `parser.resolveAliases` (LLM-generated
  alternative search terms), re-routed through pg_trgm. This is Pro-only and
  capped by the small on-device model's quality.

Semantic search **augments the fallback**, it does not replace the primary
search. pg_trgm stays first (fast, free, exact + typo + accent). Semantic ANN
runs only where keyword matching came back empty or weak — i.e. exactly the
`match == null` branch, and specifically in the describe-meal path, never in the
instant search-as-you-type box.

## Constraints (locked with the user, 2026-07-23)

1. **Neon only.** No external backend beyond Neon (auth + DB). Embeddings must be
   generated **in-DB or on-device** — no OpenAI/Gemini/hosted embedding API.
2. **All tiers, including CE.** Not gated to Pro. Because embedding happens
   server-side, every tier and platform (free, CE, web, desktop, mobile)
   benefits with no client work.
3. **CE may depend on Neon.** The user accepts that CE self-hosters must run on
   Neon (so a Neon-proprietary extension in a CE migration is acceptable). This
   requires adjusting the CE-isolation CI (see Deploy notes).

## Technology findings

- **In-DB embeddings: `pgrag`.** Provides local, in-Postgres embedding
  generation with a bundled model — no external call:
  - `rag_bge_small_en_v15.embedding_for_passage(text) -> vector(384)` (corpus)
  - `rag_bge_small_en_v15.embedding_for_query(text) -> vector(384)` (query)
  - Model: **bge-small-en-v1.5**, 33M params, **384 dimensions**.
- **ANN index: `lakebase_vector`.** Drop-in companion to pgvector — same
  `vector` type, distance operators, and query syntax; adds the `lakebase_ann`
  index (cosine). The user chose this over plain pgvector.
- **pgvector** is the fallback if `lakebase_vector` proves troublesome — same
  columns/queries, HNSW/IVFFlat index instead of `lakebase_ann`. Keep this in
  our back pocket; the schema does not change if we swap the index type.

### The two caveats that gate this whole plan

1. **The local model is English-only.** bge-small-en-v1.5 is `-en-`. Our
   `food_database.name` is **de/en/es**. Embedding German compounds
   ("Vollkornnudeln") and Spanish ("gazpacho") with an English model is exactly
   where quality is weakest — and cross-lingual matching is the headline use
   case. The only multilingual option pgrag offers is
   `rag.openai_text_embedding_3_small` (the external call we ruled out). **This
   is the primary risk and the reason for a spike before committing.**
2. **`pgrag` is experimental.** Requires `SET
   neon.allow_unstable_extensions='true'`, and Neon *recommends a separate
   dedicated project* rather than the production DB. Query-time embedding must
   run where search runs, so we cannot keep pgrag off prod if we want in-DB query
   embedding. Putting an unstable extension on the DB that serves every food
   search is a genuine operational risk to weigh.

## Phase 0 — Spike & go/no-go gate (dev DB only)

Do this before any production change. The multilingual quality is unknowable
until measured on our own data.

1. On the **dev** Neon DB: `SET neon.allow_unstable_extensions='true'`, enable
   `pgrag` and `lakebase_vector`. Record the exact enable steps (preload libs?
   compute restart?) — the docs are silent, so capture reality.
2. Add a nullable `name_embedding vector(384)` column to `food_database` on dev.
   Batch-populate a representative slice (~20–50k rows spanning de/en/es and the
   BLS/FDC/OFF sources) via `embedding_for_passage(name)`. Measure how long the
   batch takes and its compute cost.
3. Build a `lakebase_ann` index on the populated column.
4. Assemble ~30 real, messy queries across all three languages — the cases
   pg_trgm misses today (foreign spellings, synonyms, descriptive phrases:
   "gaspaccho", "grilled chicken breast", "Vollkornnudeln", "requesón",
   "porridge oats"). For each, compare ANN top-1 against today's pg_trgm top-1.
5. Measure **query-embed + ANN latency** end to end, and the **cold-start** hit
   (Neon scales to zero; first query after wake loads the model).

**Gate:**
- **Go** if English-model semantic top-1 clearly beats pg_trgm on the miss cases
  — including acceptable (not necessarily great) de/es behaviour — and latency in
  the describe-meal flow is tolerable (target < ~1s per item incl. cold path).
- **No-go / reconsider** if de/es quality is poor. Then the decision returns to
  the user: relax "Neon-only" for a multilingual embedding call, or gate semantic
  to Pro-mobile via the on-device stack, or wait for a multilingual local model /
  pgrag GA.

Record the spike results in this doc before proceeding.

## Phase 1 — Corpus embeddings (prod, behind the gate)

- Versioned migration: add `name_embedding vector(384)` to `food_database`
  (nullable — existing rows embed lazily/batched, no table rewrite).
- Repeatable backfill or a one-off maintenance script:
  `UPDATE food_database SET name_embedding = embedding_for_passage(name) WHERE
  name_embedding IS NULL` in batches (449k rows — chunk it, watch compute).
- Keep new/edited foods embedded: a `BEFORE INSERT/UPDATE` trigger on
  `food_database` that sets `name_embedding = embedding_for_passage(NEW.name)`
  when the name changes. (Trigger, not a generated column — generated columns
  can't call a non-IMMUTABLE embedding function.)
- Build the `lakebase_ann` index.
- **GRANT** appropriately; `security_invoker` on any view; follow the migration
  checklist. RLS on `food_database` is unchanged.

## Phase 2 — Semantic search RPC

- New function `public.semantic_search_food(query text, max_results int)`
  (`SECURITY INVOKER`, `STABLE`), living in `sql/repeatable/` like
  `search_food_database`:
  - `q := rag_bge_small_en_v15.embedding_for_query(query);`
  - `SELECT fd.* FROM food_database fd ORDER BY fd.name_embedding <=> q LIMIT
    max_results;` (respecting RLS + the same visibility rules as
    `search_food_database`).
  - Consider returning a distance/score so the client can threshold weak hits.
- Optional (later): a hybrid RPC that fuses pg_trgm rank and ANN rank via RRF
  (`1/(60+rank)`), the pattern lakebase documents. Not needed for v1 — keep the
  two paths separate and simple first.

## Phase 3 — Wire into the matcher (client)

- `FoodDatabaseService.semanticSearchFoods(query, limit)` → RPC
  `semantic_search_food` (mirror `searchFoods`: token refresh, error handling,
  returns `List<FoodItem>`).
- `MealSuggestionService`: in `suggest()`, when `_bestMatch(query) == null`, try
  semantic search **before** the existing `AliasResolver` (or as the resolver's
  new default for the heuristic/free path, which today has no fallback at all).
  Mark such matches as substitutes (`matchedVia`) so the review UI flags them —
  a semantic guess deserves the same "wrong match?" affordance the alias path
  already shows.
- Tag semantic-matched draft entries as uncertain (they already are — this feeds
  the EstimateLevel band; a meaning-match is inherently less certain than an
  exact hit).
- No new tier gating — all-tiers per the decision.

## Phase 4 — Verify & measure

- `flutter analyze` + tests; new tests for `semanticSearchFoods` and the
  `MealSuggestionService` fallback ordering (mock the RPC).
- Manual: describe a mixed de/en/es meal with deliberately misspelled / foreign
  items; confirm previously-unmatched items now resolve and are flagged for
  review.
- Watch prod compute after enabling: embedding on write + query-time embedding
  add load; confirm cold-start is acceptable for the first describe-meal after
  the DB wakes.

## Deploy notes

- **CE-isolation CI (`.github/workflows/db-migrations.yml`) will break.** It
  builds CE against a stock empty Postgres and fails on Neon-only objects. CE now
  legitimately depends on `pgrag`/`lakebase_vector` (per the locked constraint),
  so that job needs adjusting — either provision the extensions in the CI DB or
  exempt the embedding migration. Do this in the same PR as Phase 1.
- **Deploy order** is unchanged: CE first, then cloud (the cloud DB shares the CE
  `food_database` + `search_food_database`; the semantic column/RPC are CE
  objects, no cloud migration needed).
- `pgrag` enable requires `neon.allow_unstable_extensions='true'` and possibly a
  compute restart — capture the exact steps from the Phase 0 spike and put them
  in `docs/database/MIGRATIONS.md`.

## Open questions / risks

- **Multilingual quality** (the gate) — see Phase 0.
- **Experimental extension on prod** — Neon's "use a dedicated project"
  recommendation vs. our need for query embedding on the search DB. If this
  proves unacceptable, the only in-DB path collapses and we fall back to the
  Pro/on-device route.
- **Dimension/cost** — 449k × vector(384) ≈ ~690 MB before the index; modest.
- **Model/version lock-in** — if the local model changes, corpus + query must be
  re-embedded together. Store the model name/version somewhere (a comment or a
  small metadata row) so a mismatch is detectable.
- **Fallback swap** — if `lakebase_vector` is troublesome, switch the index to
  pgvector HNSW with no schema/RPC change.

## Related

- Matcher & parsers: `lib/services/meal_suggestion_service.dart`,
  `meal_description_parser.dart`, `ai_meal_parser.dart`,
  `screens/meal_description_screen.dart`.
- Keyword search this augments: `sql/repeatable/R__fn_search_food_database.sql`
  (see also `docs/…` and the fuzzy-search history).
- On-device LLM stack (the alternative if the gate fails): nutrition-uncertainty
  Phase 3 (cactus + smollm2-360m, Pro/mobile).
