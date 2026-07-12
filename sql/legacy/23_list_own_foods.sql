-- Two optimised list functions that replace search_food_database(query='', max_results=1000)
-- for preload use cases. Both skip similarity() and the food_entries MRU join (client-side).
--
-- list_own_foods()     → manage screen: only the calling user's own foods
-- list_visible_foods() → add-food screen: own foods + public approved foods (own first)
--
-- Key improvements over search_food_database(query=''):
--   - No similarity() computed per-row (was O(n), all returning 0.0 for empty query)
--   - No food_entries join (MRU order is done client-side via getRecentlyUsedFoodIds)
--   - Tags CTE uses RLS (SECURITY INVOKER) instead of correlated EXISTS subqueries
--   - Additional partial index for fast public-approved food lookups

-- Partial index: makes the (is_public AND is_approved) part of list_visible_foods fast
CREATE INDEX IF NOT EXISTS idx_food_database_public_approved
  ON food_database(created_at DESC)
  WHERE is_public = TRUE AND is_approved = TRUE;


-- ── list_own_foods ─────────────────────────────────────────────────────────────
-- Returns only the calling user's own foods.
-- Tags: only tags the current user added (who IS the food owner for these rows).

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
    fd.portions, fd.created_at, fd.updated_at,
    COALESCE(ot.tags, '[]'::jsonb) AS tags
  FROM food_database fd
  LEFT JOIN own_tags ot ON ot.food_id = fd.id
  WHERE fd.user_id::text = current_setting('request.jwt.claims', true)::json->>'sub'
  ORDER BY fd.created_at DESC
  LIMIT max_results
$$;


-- ── list_visible_foods ─────────────────────────────────────────────────────────
-- Returns the calling user's own foods + all public approved foods.
-- Own foods are sorted first; within each group newest first.
-- MRU sort is done client-side.
--
-- Tags: SECURITY INVOKER means RLS on user_food_tags is applied automatically,
-- so the CTE sees exactly the tags the caller is allowed to see (own tags +
-- owner-added tags on public foods). No explicit EXISTS filter needed.

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
    -- RLS on user_food_tags (SECURITY INVOKER) already limits rows to:
    --   own tags + owner-added tags on foods visible to this user.
    -- No explicit EXISTS subquery needed.
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
