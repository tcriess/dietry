-- 24_search_includes_category.sql — extend search_food_database to match category
--
-- The add-food screen's My DB search now uses search_food_database server-side
-- (instead of client-side filtering of a 300-row preload). The previous version
-- only matched name + brand, which is narrower than the client-side filter the
-- user is replacing. Add category to the WHERE clause so that typing a category
-- like "Obst" still surfaces matches.
--
-- Trigram index on category for fast ILIKE.

CREATE INDEX IF NOT EXISTS idx_food_database_category_trgm
  ON food_database USING GIN (category gin_trgm_ops);

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
LANGUAGE sql
SECURITY INVOKER
STABLE
AS $$
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
      OR uft.user_id::text = current_setting('request.jwt.claims',true)::json->>'sub'
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
      OR fd.name ILIKE '%' || query || '%'
      OR (fd.brand    IS NOT NULL AND fd.brand    ILIKE '%' || query || '%')
      OR (fd.category IS NOT NULL AND fd.category ILIKE '%' || query || '%')
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
              OR uft2.user_id::text = current_setting('request.jwt.claims',true)::json->>'sub'
            )
        ) AS matched_tags
      )
    )
  ORDER BY
    CASE WHEN fd.user_id::text = (current_setting('request.jwt.claims',true)::json->>'sub')
         THEN 0 ELSE 1 END ASC,
    GREATEST(
      similarity(fd.name, query),
      COALESCE(similarity(fd.brand,    query), 0.0),
      COALESCE(similarity(fd.category, query), 0.0)
    ) DESC,
    ulu.last_used DESC NULLS LAST,
    fd.name ASC
  LIMIT max_results
$$;
