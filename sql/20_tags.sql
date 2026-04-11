-- ── Cleanup old tables (if migration is being re-applied) ─────────────────────
DROP TABLE IF EXISTS food_public_tags CASCADE;
DROP FUNCTION IF EXISTS search_food_database(TEXT, TEXT[], INT) CASCADE;

-- ── Global tag definitions ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tags (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  slug       TEXT NOT NULL UNIQUE,  -- LOWER(TRIM(name)), spaces→hyphens
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tags_slug ON tags(slug);
CREATE INDEX IF NOT EXISTS idx_tags_name_trgm ON tags USING GIN (name gin_trgm_ops);

ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
-- SELECT: all authenticated users
DROP POLICY IF EXISTS tags_select ON tags;
CREATE POLICY tags_select ON tags FOR SELECT USING (TRUE);
-- INSERT: any authenticated user (slug UNIQUE constraint prevents duplicates)
DROP POLICY IF EXISTS tags_insert ON tags;
CREATE POLICY tags_insert ON tags FOR INSERT
  WITH CHECK (created_by::text = current_setting('request.jwt.claims',true)::json->>'sub');
-- UPDATE/DELETE: creator only
DROP POLICY IF EXISTS tags_update ON tags;
CREATE POLICY tags_update ON tags FOR UPDATE
  USING (created_by::text = current_setting('request.jwt.claims',true)::json->>'sub');
DROP POLICY IF EXISTS tags_delete ON tags;
CREATE POLICY tags_delete ON tags FOR DELETE
  USING (created_by::text = current_setting('request.jwt.claims',true)::json->>'sub');

-- ── User food tags (any user can tag any visible food; visibility based on ownership) ──
-- If user_id = food owner, tags visible to all. Otherwise, only visible to that user.
CREATE TABLE IF NOT EXISTS user_food_tags (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  food_id UUID NOT NULL REFERENCES food_database(id) ON DELETE CASCADE,
  tag_id  UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, food_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_user_food_tags_user_food ON user_food_tags(user_id, food_id);
CREATE INDEX IF NOT EXISTS idx_user_food_tags_tag       ON user_food_tags(tag_id);

ALTER TABLE user_food_tags ENABLE ROW LEVEL SECURITY;
-- SELECT: see own tags OR owner-added tags (owner's curation)
DROP POLICY IF EXISTS uft_select ON user_food_tags;
CREATE POLICY uft_select ON user_food_tags FOR SELECT
  USING (
    user_id::text = current_setting('request.jwt.claims',true)::json->>'sub'
    OR EXISTS (
      SELECT 1 FROM food_database fd
      WHERE fd.id = food_id
        AND fd.user_id::text = user_id::text  -- tagger is the food owner
    )
  );
-- INSERT/DELETE: only own tags
DROP POLICY IF EXISTS uft_modify ON user_food_tags;
CREATE POLICY uft_modify ON user_food_tags FOR INSERT WITH CHECK
  (user_id::text = current_setting('request.jwt.claims',true)::json->>'sub');
CREATE POLICY uft_delete ON user_food_tags FOR DELETE
  USING (user_id::text = current_setting('request.jwt.claims',true)::json->>'sub');

-- ── Search function with tag-aware filtering ─────────────────────────────────
-- Returns food_database columns + tags as JSONB array.
-- Tags shown: owner-added (visible to all) + current user's tags.
DROP TYPE IF EXISTS food_tag CASCADE;
CREATE TYPE food_tag AS (id UUID, name TEXT, slug TEXT);

DROP FUNCTION IF EXISTS search_food_database(TEXT, TEXT[], INT);
CREATE OR REPLACE FUNCTION search_food_database(
  query       TEXT,
  filter_tags TEXT[]  DEFAULT NULL,  -- filter by tag slugs (NULL = no filter)
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
  tags           JSONB   -- [{id, name, slug}, ...] from owner or current user
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
    -- Tags added by food owner (visible to all) OR by current user (visible only to them)
    SELECT uft.food_id,
      jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'slug', t.slug)) AS tags
    FROM user_food_tags uft
    JOIN tags t ON t.id = uft.tag_id
    WHERE (
      -- Owner-added tags (food owner added this tag)
      EXISTS (
        SELECT 1 FROM food_database fd
        WHERE fd.id = uft.food_id AND fd.user_id::text = uft.user_id::text
      )
      -- OR current user's tags
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
    -- Text search
    (query = '' OR fd.name ILIKE '%' || query || '%'
      OR (fd.brand IS NOT NULL AND fd.brand ILIKE '%' || query || '%'))
    -- Tag filter (food must have ALL requested tags from visible tags)
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
              -- Tag from owner OR from current user
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
      COALESCE(similarity(fd.brand, query), 0.0)
    ) DESC,
    ulu.last_used DESC NULLS LAST,
    fd.name ASC
  LIMIT max_results
$$;

-- Helper: get all tags available for filtering in user's visible foods
-- Includes: owner-added tags (visible to all) + current user's tags
DROP FUNCTION IF EXISTS get_available_food_tags();
CREATE OR REPLACE FUNCTION get_available_food_tags()
RETURNS TABLE (id UUID, name TEXT, slug TEXT, created_by UUID, created_at TIMESTAMP)
LANGUAGE sql SECURITY INVOKER STABLE AS $$
  SELECT DISTINCT t.id, t.name, t.slug, t.created_by, t.created_at FROM tags t
  WHERE EXISTS (
    -- Owner-added tags (visible to all users)
    SELECT 1 FROM user_food_tags uft
    JOIN food_database fd ON fd.id = uft.food_id
    WHERE uft.tag_id = t.id
      AND fd.user_id::text = uft.user_id::text
  ) OR EXISTS (
    -- Current user's own tags
    SELECT 1 FROM user_food_tags uft
    WHERE uft.tag_id = t.id
      AND uft.user_id::text = current_setting('request.jwt.claims',true)::json->>'sub'
  )
  ORDER BY t.name
$$;
