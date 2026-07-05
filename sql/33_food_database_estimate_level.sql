-- 33_food_database_estimate_level.sql — inherent per-food uncertainty
--
-- A food can be inherently variable (a homemade dish) vs exact (a packaged
-- product). This column seeds a log entry's estimate level (see
-- EstimateLevel.defaultForLog): logging such a food starts at a higher default,
-- still overridable per log. Default 'none' keeps every existing food exact.
--
-- The three FoodItem-returning RPCs (search_food_database, list_own_foods,
-- list_visible_foods) are redefined only to ALSO return estimate_level — so the
-- app reads a food's level wherever it lists foods (logging seeds from it; the
-- editor round-trips it instead of resetting it). Bodies are otherwise verbatim
-- copies of sql/31 and sql/23.

BEGIN;

ALTER TABLE food_database
  ADD COLUMN IF NOT EXISTS estimate_level TEXT NOT NULL DEFAULT 'none'
    CHECK (estimate_level IN ('none', 'low', 'medium', 'high'));

-- ── search_food_database (copy of sql/31 + estimate_level) ──────────────────
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
  estimate_level TEXT,
  portions       JSONB,
  created_at     TIMESTAMPTZ,
  updated_at     TIMESTAMPTZ,
  tags           JSONB
)
LANGUAGE plpgsql
SECURITY INVOKER
STABLE
SET pg_trgm.word_similarity_threshold = 0.4
AS $$
#variable_conflict use_column
DECLARE
  ua       text    := public.f_unaccent(query);
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
    fd.estimate_level,
    fd.portions, fd.created_at, fd.updated_at,
    COALESCE(vt.tags, '[]'::jsonb) AS tags
  FROM food_database fd
  LEFT JOIN user_last_used ulu ON ulu.food_id = fd.id
  LEFT JOIN visible_tags vt ON vt.food_id = fd.id
  WHERE
    (
      query = ''
      OR fd.name_unaccent ILIKE '%' || ua || '%'
      OR (fd.brand_unaccent    IS NOT NULL AND fd.brand_unaccent    ILIKE '%' || ua || '%')
      OR (fd.category_unaccent IS NOT NULL AND fd.category_unaccent ILIKE '%' || ua || '%')
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
    CASE WHEN fd.user_id::text = uid THEN 0 ELSE 1 END ASC,
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

-- ── list_own_foods (copy of sql/23 + estimate_level) ────────────────────────
DROP FUNCTION IF EXISTS list_own_foods(INT);
CREATE OR REPLACE FUNCTION list_own_foods(max_results INT DEFAULT 500)
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
  estimate_level TEXT,
  portions       JSONB,
  created_at     TIMESTAMPTZ,
  updated_at     TIMESTAMPTZ,
  tags           JSONB
)
LANGUAGE sql
SECURITY INVOKER
STABLE
AS $$
  WITH own_tags AS (
    SELECT uft.food_id,
      jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'slug', t.slug)) AS tags
    FROM user_food_tags uft
    JOIN tags t ON t.id = uft.tag_id
    WHERE uft.user_id::text = current_setting('request.jwt.claims', true)::json->>'sub'
    GROUP BY uft.food_id
  )
  SELECT
    fd.id, fd.user_id, fd.name, fd.calories, fd.protein, fd.fat, fd.carbs,
    fd.fiber, fd.sugar, fd.sodium, fd.saturated_fat, fd.serving_size,
    fd.serving_unit, fd.category, fd.brand, fd.barcode, fd.is_public,
    fd.is_approved, fd.is_liquid, fd.is_favourite, fd.has_image, fd.source,
    fd.estimate_level,
    fd.portions, fd.created_at, fd.updated_at,
    COALESCE(ot.tags, '[]'::jsonb) AS tags
  FROM food_database fd
  LEFT JOIN own_tags ot ON ot.food_id = fd.id
  WHERE fd.user_id::text = current_setting('request.jwt.claims', true)::json->>'sub'
  ORDER BY fd.created_at DESC
  LIMIT max_results
$$;

-- ── list_visible_foods (copy of sql/23 + estimate_level) ────────────────────
DROP FUNCTION IF EXISTS list_visible_foods(INT);
CREATE OR REPLACE FUNCTION list_visible_foods(max_results INT DEFAULT 300)
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
  estimate_level TEXT,
  portions       JSONB,
  created_at     TIMESTAMPTZ,
  updated_at     TIMESTAMPTZ,
  tags           JSONB
)
LANGUAGE sql
SECURITY INVOKER
STABLE
AS $$
  WITH visible_tags AS (
    SELECT uft.food_id,
      jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'slug', t.slug)) AS tags
    FROM user_food_tags uft
    JOIN tags t ON t.id = uft.tag_id
    GROUP BY uft.food_id
  )
  SELECT
    fd.id, fd.user_id, fd.name, fd.calories, fd.protein, fd.fat, fd.carbs,
    fd.fiber, fd.sugar, fd.sodium, fd.saturated_fat, fd.serving_size,
    fd.serving_unit, fd.category, fd.brand, fd.barcode, fd.is_public,
    fd.is_approved, fd.is_liquid, fd.is_favourite, fd.has_image, fd.source,
    fd.estimate_level,
    fd.portions, fd.created_at, fd.updated_at,
    COALESCE(vt.tags, '[]'::jsonb) AS tags
  FROM food_database fd
  LEFT JOIN visible_tags vt ON vt.food_id = fd.id
  WHERE
    fd.user_id::text = current_setting('request.jwt.claims', true)::json->>'sub'
    OR (fd.is_public = TRUE AND fd.is_approved = TRUE)
  ORDER BY
    CASE WHEN fd.user_id::text = current_setting('request.jwt.claims', true)::json->>'sub'
         THEN 0 ELSE 1 END ASC,
    fd.created_at DESC
  LIMIT max_results
$$;

COMMIT;
