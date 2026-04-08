-- Enable pg_trgm extension for trigram similarity search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Drop old B-tree index on LOWER(name) — cannot be used for %term% queries
DROP INDEX IF EXISTS idx_food_database_name;

-- GIN trigram index on name — makes ILIKE '%term%' fast, enables similarity()
CREATE INDEX idx_food_database_name_trgm
  ON food_database USING GIN (name gin_trgm_ops);

-- GIN trigram index on brand — same benefits for brand search
CREATE INDEX idx_food_database_brand_trgm
  ON food_database USING GIN (brand gin_trgm_ops);

-- Improved food search function
--
-- Searches both name and brand using trigram similarity and ILIKE.
-- Results ordered by:
--   1. Own (private) entries first
--   2. Best trigram match (higher similarity = higher rank)
--   3. Most recently used by the calling user (for both own and public items)
--   4. Alphabetical (tie-break)
--
-- RLS is automatically applied:
--   - SECURITY INVOKER allows RLS on food_database and food_entries
--   - User sees own private items + approved public items (per food_database RLS)
--   - last_used_date via food_entries LEFT JOIN only includes user's own entries
--
-- Parameters:
--   query: search term (supports empty string to list by recently used)
--   max_results: result limit (default 50)
--
CREATE OR REPLACE FUNCTION search_food_database(
  query TEXT,
  max_results INT DEFAULT 50
)
RETURNS SETOF food_database
LANGUAGE sql
SECURITY INVOKER
STABLE
AS $$
  WITH user_last_used AS (
    SELECT food_id, MAX(entry_date) AS last_used
    FROM food_entries
    WHERE food_id IS NOT NULL
    GROUP BY food_id
    -- RLS on food_entries automatically scopes to calling user's entries
  )
  SELECT fd.*
  FROM food_database fd
  LEFT JOIN user_last_used ulu ON ulu.food_id = fd.id
  WHERE
    fd.name ILIKE '%' || query || '%'
    OR (fd.brand IS NOT NULL AND fd.brand ILIKE '%' || query || '%')
  ORDER BY
    -- 1. Own entries (private items) first
    CASE WHEN fd.user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub')
         THEN 0 ELSE 1 END ASC,
    -- 2. Best trigram match (higher similarity = better)
    GREATEST(
      similarity(fd.name, query),
      COALESCE(similarity(fd.brand, query), 0.0)
    ) DESC,
    -- 3. Most recently used by this user (NULL = never used → last)
    ulu.last_used DESC NULLS LAST,
    -- 4. Alphabetical fallback
    fd.name ASC
  LIMIT max_results
$$;
