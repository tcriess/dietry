-- 26_search_word_boundary_priority.sql — rank word-boundary matches above mid-word matches
--
-- The previous WHERE clause (sql/24) accepts any substring match in
-- name/brand/category via ILIKE '%' || query || '%'. That includes mid-word
-- hits: searching "milk" also matches "Smilk Fitness Powder" because "milk"
-- happens to appear inside "Smilk". Combined with own-foods-first sorting and
-- LIMIT 20, those weak matches can crowd out the genuine word-boundary hits
-- ("Milk Chocolate", "Whole Milk") that the user actually expects.
--
-- Symptom users observed: persistent search results that have nothing in
-- common with the search term, only fixed by typing a trailing space (which
-- forces ILIKE '%milk %' and so removes the mid-word matches).
--
-- Fix: keep the WHERE clause as-is so substring search remains a fallback,
-- but extend ORDER BY with a word-boundary priority key. Rows where the
-- query matches at the start of any word in name/brand/category come first
-- within each ownership group; mid-word substring matches sort below and get
-- cut off by LIMIT once enough word-boundary matches are present.

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
    -- Word-boundary priority. 0 if the query starts a word in name/brand/
    -- category (prefix or " " || query), 1 if it only appears mid-word.
    -- Pushes "Smilk Fitness" below "Milk Chocolate" when searching "milk".
    CASE WHEN query <> '' AND (
      fd.name ILIKE query || '%'
      OR fd.name ILIKE '% ' || query || '%'
      OR (fd.brand IS NOT NULL AND (
        fd.brand ILIKE query || '%' OR fd.brand ILIKE '% ' || query || '%'
      ))
      OR (fd.category IS NOT NULL AND (
        fd.category ILIKE query || '%' OR fd.category ILIKE '% ' || query || '%'
      ))
    ) THEN 0 ELSE 1 END ASC,
    GREATEST(
      similarity(fd.name, query),
      COALESCE(similarity(fd.brand,    query), 0.0),
      COALESCE(similarity(fd.category, query), 0.0)
    ) DESC,
    ulu.last_used DESC NULLS LAST,
    fd.name ASC
  LIMIT max_results
$$;
