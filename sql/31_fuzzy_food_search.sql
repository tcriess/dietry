-- 31_fuzzy_food_search.sql — typo-tolerant + accent-insensitive food search
--
-- pg_trgm has been enabled since sql/19, but the search only used it for
-- RANKING: the WHERE gated on ILIKE '%q%' (exact substring), so misspellings
-- that aren't a literal substring returned zero rows. This adds:
--   1. unaccent      — "müsli"/"muesli"→"musli", "crème"/"creme", "jalapeño".
--   2. word_similarity (%>) in the WHERE — typos surface ("jogurt"→"Joghurt",
--      "bananna"→"Banana"), ranked below exact/word-boundary hits.
--
-- PERF (learned the hard way, on a ~450k-row table):
--   a) Wrapping columns in f_unaccent() at query time makes the bitmap RECHECK
--      and ORDER BY re-run the dictionary lookup per row → timeout. Fix: store
--      the unaccented text in STORED generated columns and index/search THOSE,
--      so f_unaccent runs once per row at write time.
--   b) The unaccented QUERY value must be a plain scalar (a plpgsql local
--      variable), NOT a CROSS JOIN / correlated subquery — otherwise the GIN
--      index can't be used for %> / ILIKE and it seq-scans → timeout. Measured:
--      `name_unaccent %> $localvar` uses idx_food_database_name_ua_trgm in ~1.5 ms.
--
-- NOTE (German ü↔ue): unaccent maps ü→u, not ü→ue, so "muesli" won't fuzzily
-- reach "Müsli" via accents alone. A custom unaccent dictionary would — out of
-- scope here.

BEGIN;

-- Accent folding (Neon-supported; installs into public by default).
CREATE EXTENSION IF NOT EXISTS unaccent;

-- IMMUTABLE wrapper (2-arg form pins the dictionary → safe in a generated
-- column). Assumes the unaccent extension lives in public.
CREATE OR REPLACE FUNCTION public.f_unaccent(text)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  PARALLEL SAFE
  STRICT
AS $$
  SELECT public.unaccent('public.unaccent', $1)
$$;

-- Precompute the unaccented text once, at write time. One-time table rewrite;
-- ACCESS EXCLUSIVE lock while it runs — apply to dev first.
ALTER TABLE food_database
  ADD COLUMN IF NOT EXISTS name_unaccent     text GENERATED ALWAYS AS (public.f_unaccent(name))     STORED,
  ADD COLUMN IF NOT EXISTS brand_unaccent    text GENERATED ALWAYS AS (public.f_unaccent(brand))    STORED,
  ADD COLUMN IF NOT EXISTS category_unaccent text GENERATED ALWAYS AS (public.f_unaccent(category)) STORED;

-- Trigram indexes on the stored columns (accelerate ILIKE '%q%' AND %>).
DROP INDEX IF EXISTS idx_food_database_name_trgm;
DROP INDEX IF EXISTS idx_food_database_brand_trgm;
DROP INDEX IF EXISTS idx_food_database_category_trgm;
DROP INDEX IF EXISTS idx_food_database_name_unaccent_trgm;
DROP INDEX IF EXISTS idx_food_database_brand_unaccent_trgm;
DROP INDEX IF EXISTS idx_food_database_category_unaccent_trgm;

CREATE INDEX IF NOT EXISTS idx_food_database_name_ua_trgm
  ON food_database USING GIN (name_unaccent gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_food_database_brand_ua_trgm
  ON food_database USING GIN (brand_unaccent gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_food_database_category_ua_trgm
  ON food_database USING GIN (category_unaccent gin_trgm_ops);

DROP FUNCTION IF EXISTS search_food_database(TEXT, TEXT[], INT);
CREATE OR REPLACE FUNCTION search_food_database(
  query       TEXT,
  filter_tags TEXT[]  DEFAULT NULL,
  max_results INT     DEFAULT 50
)
RETURNS TABLE (
  id             UUID,
  user_id        UUID,
  name           TEXT,
  calories       NUMERIC,
  protein        NUMERIC,
  fat            NUMERIC,
  carbs          NUMERIC,
  fiber          NUMERIC,
  sugar          NUMERIC,
  sodium         NUMERIC,
  saturated_fat  NUMERIC,
  serving_size   NUMERIC,
  serving_unit   TEXT,
  category       TEXT,
  brand          TEXT,
  barcode        TEXT,
  is_public      BOOLEAN,
  is_approved    BOOLEAN,
  is_liquid      BOOLEAN,
  is_favourite   BOOLEAN,
  has_image      BOOLEAN,
  source         TEXT,
  portions       JSONB,
  created_at     TIMESTAMPTZ,
  updated_at     TIMESTAMPTZ,
  tags           JSONB
)
LANGUAGE plpgsql
SECURITY INVOKER
STABLE
-- Typo-tolerance knob for %> (default 0.6 is strict; 0.4 is forgiving).
SET pg_trgm.word_similarity_threshold = 0.4
AS $$
#variable_conflict use_column
DECLARE
  -- Unaccent the query into a LOCAL scalar so the GIN indexes on the *_unaccent
  -- columns are actually used for %> / ILIKE (see PERF (b) in the header).
  ua       text    := public.f_unaccent(query);
  -- Fuzzy only for tokens long enough for trigrams to be meaningful/selective;
  -- short type-ahead stays exact-substring-only (fast).
  do_fuzzy boolean := char_length(public.f_unaccent(query)) >= 3;
  uid      text    := current_setting('request.jwt.claims', true)::json->>'sub';
BEGIN
  RETURN QUERY
  WITH user_last_used AS (
    SELECT food_id, MAX(entry_date) AS last_used
    FROM food_entries WHERE food_id IS NOT NULL GROUP BY food_id
  ),
  visible_tags AS (
    SELECT uft.food_id,
      jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'slug', t.slug)) AS tags
    FROM user_food_tags uft
    JOIN tags t ON t.id = uft.tag_id
    WHERE (
      EXISTS (
        SELECT 1 FROM food_database fd
        WHERE fd.id = uft.food_id AND fd.user_id::text = uft.user_id::text
      )
      OR uft.user_id::text = uid
    )
    GROUP BY uft.food_id
  )
  SELECT
    fd.id, fd.user_id, fd.name, fd.calories, fd.protein, fd.fat, fd.carbs,
    fd.fiber, fd.sugar, fd.sodium, fd.saturated_fat, fd.serving_size,
    fd.serving_unit, fd.category, fd.brand, fd.barcode, fd.is_public,
    fd.is_approved, fd.is_liquid, fd.is_favourite, fd.has_image, fd.source,
    fd.portions, fd.created_at, fd.updated_at,
    COALESCE(vt.tags, '[]'::jsonb) AS tags
  FROM food_database fd
  LEFT JOIN user_last_used ulu ON ulu.food_id = fd.id
  LEFT JOIN visible_tags vt ON vt.food_id = fd.id
  WHERE
    (
      query = ''
      -- Exact substring, accent-insensitive (all lengths).
      OR fd.name_unaccent ILIKE '%' || ua || '%'
      OR (fd.brand_unaccent    IS NOT NULL AND fd.brand_unaccent    ILIKE '%' || ua || '%')
      OR (fd.category_unaccent IS NOT NULL AND fd.category_unaccent ILIKE '%' || ua || '%')
      -- Fuzzy (typo tolerance) — only when do_fuzzy.
      OR (do_fuzzy AND fd.name_unaccent %> ua)
      OR (do_fuzzy AND fd.brand_unaccent    IS NOT NULL AND fd.brand_unaccent    %> ua)
      OR (do_fuzzy AND fd.category_unaccent IS NOT NULL AND fd.category_unaccent %> ua)
    )
    AND (
      filter_tags IS NULL OR
      (
        SELECT count(*) = array_length(filter_tags, 1)
        FROM (
          SELECT DISTINCT t2.slug
          FROM user_food_tags uft2
          JOIN tags t2 ON t2.id = uft2.tag_id
          WHERE uft2.food_id = fd.id
            AND t2.slug = ANY(filter_tags)
            AND (
              EXISTS (
                SELECT 1 FROM food_database fd2
                WHERE fd2.id = uft2.food_id AND fd2.user_id::text = uft2.user_id::text
              )
              OR uft2.user_id::text = uid
            )
        ) AS matched_tags
      )
    )
  ORDER BY
    -- Own foods first.
    CASE WHEN fd.user_id::text = uid THEN 0 ELSE 1 END ASC,
    -- Word-boundary priority (stored unaccented columns; no per-row f_unaccent).
    CASE WHEN query <> '' AND (
      fd.name_unaccent ILIKE ua || '%'
      OR fd.name_unaccent ILIKE '% ' || ua || '%'
      OR (fd.brand_unaccent IS NOT NULL AND (
        fd.brand_unaccent ILIKE ua || '%' OR fd.brand_unaccent ILIKE '% ' || ua || '%'
      ))
      OR (fd.category_unaccent IS NOT NULL AND (
        fd.category_unaccent ILIKE ua || '%' OR fd.category_unaccent ILIKE '% ' || ua || '%'
      ))
    ) THEN 0 ELSE 1 END ASC,
    -- Fuzzy rank — skipped (constant) for short queries so they stay cheap.
    CASE WHEN do_fuzzy THEN GREATEST(
      word_similarity(ua, fd.name_unaccent),
      COALESCE(word_similarity(ua, fd.brand_unaccent),    0.0),
      COALESCE(word_similarity(ua, fd.category_unaccent), 0.0)
    ) ELSE 0 END DESC,
    ulu.last_used DESC NULLS LAST,
    fd.name ASC
  LIMIT max_results;
END;
$$;

COMMIT;
