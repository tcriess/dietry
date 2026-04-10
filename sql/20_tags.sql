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

-- ── Public food tags (assigned by food owner, visible to all) ─────────────────
CREATE TABLE IF NOT EXISTS food_public_tags (
  food_id UUID NOT NULL REFERENCES food_database(id) ON DELETE CASCADE,
  tag_id  UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (food_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_food_public_tags_food ON food_public_tags(food_id);
CREATE INDEX IF NOT EXISTS idx_food_public_tags_tag  ON food_public_tags(tag_id);

ALTER TABLE food_public_tags ENABLE ROW LEVEL SECURITY;
-- SELECT: everyone sees public tags on visible foods
DROP POLICY IF EXISTS fpt_select ON food_public_tags;
CREATE POLICY fpt_select ON food_public_tags FOR SELECT USING (TRUE);
-- INSERT/DELETE: only the food owner
DROP POLICY IF EXISTS fpt_insert ON food_public_tags;
CREATE POLICY fpt_insert ON food_public_tags FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM food_database fd
    WHERE fd.id = food_id
      AND fd.user_id::text = current_setting('request.jwt.claims',true)::json->>'sub'
  ));
DROP POLICY IF EXISTS fpt_delete ON food_public_tags;
CREATE POLICY fpt_delete ON food_public_tags FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM food_database fd
    WHERE fd.id = food_id
      AND fd.user_id::text = current_setting('request.jwt.claims',true)::json->>'sub'
  ));

-- ── Private per-user food tags (any user, any visible food) ───────────────────
CREATE TABLE IF NOT EXISTS user_food_tags (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  food_id UUID NOT NULL REFERENCES food_database(id) ON DELETE CASCADE,
  tag_id  UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, food_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_user_food_tags_user_food ON user_food_tags(user_id, food_id);
CREATE INDEX IF NOT EXISTS idx_user_food_tags_tag       ON user_food_tags(tag_id);

ALTER TABLE user_food_tags ENABLE ROW LEVEL SECURITY;
-- All operations scoped to the calling user
DROP POLICY IF EXISTS uft_all ON user_food_tags;
CREATE POLICY uft_all ON user_food_tags
  USING (user_id::text = current_setting('request.jwt.claims',true)::json->>'sub')
  WITH CHECK (user_id::text = current_setting('request.jwt.claims',true)::json->>'sub');

-- ── Replace search_food_database with tag-aware version ───────────────────────
-- Returns food_database columns + public_tags + user_tags as JSONB arrays.
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
  public_tags    JSONB,  -- [{id, name, slug}, ...]
  user_tags      JSONB   -- [{id, name, slug}, ...]
)
LANGUAGE sql
SECURITY INVOKER
STABLE
AS $$
  WITH user_last_used AS (
    SELECT food_id, MAX(entry_date) AS last_used
    FROM food_entries WHERE food_id IS NOT NULL GROUP BY food_id
  ),
  pub_tags AS (
    SELECT fpt.food_id,
      jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'slug', t.slug)) AS tags
    FROM food_public_tags fpt JOIN tags t ON t.id = fpt.tag_id
    GROUP BY fpt.food_id
  ),
  usr_tags AS (
    SELECT uft.food_id,
      jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'slug', t.slug)) AS tags
    FROM user_food_tags uft JOIN tags t ON t.id = uft.tag_id
    WHERE uft.user_id::text = current_setting('request.jwt.claims',true)::json->>'sub'
    GROUP BY uft.food_id
  )
  SELECT
    fd.id, fd.user_id, fd.name, fd.calories, fd.protein, fd.fat, fd.carbs,
    fd.fiber, fd.sugar, fd.sodium, fd.saturated_fat, fd.serving_size,
    fd.serving_unit, fd.category, fd.brand, fd.barcode, fd.is_public,
    fd.is_approved, fd.is_liquid, fd.is_favourite, fd.has_image, fd.source,
    fd.portions, fd.created_at, fd.updated_at,
    COALESCE(pt.tags, '[]'::jsonb) AS public_tags,
    COALESCE(ut.tags, '[]'::jsonb) AS user_tags
  FROM food_database fd
  LEFT JOIN user_last_used ulu ON ulu.food_id = fd.id
  LEFT JOIN pub_tags pt ON pt.food_id = fd.id
  LEFT JOIN usr_tags ut ON ut.food_id = fd.id
  WHERE
    -- Text search
    (query = '' OR fd.name ILIKE '%' || query || '%'
      OR (fd.brand IS NOT NULL AND fd.brand ILIKE '%' || query || '%'))
    -- Tag filter (food must have ALL requested tags, from public OR user tags)
    AND (
      filter_tags IS NULL OR
      (
        SELECT count(*) = array_length(filter_tags, 1)
        FROM (
          SELECT DISTINCT t2.slug
          FROM food_public_tags fpt2
          JOIN tags t2 ON t2.id = fpt2.tag_id
          WHERE fpt2.food_id = fd.id AND t2.slug = ANY(filter_tags)
          UNION
          SELECT DISTINCT t2.slug
          FROM user_food_tags uft2
          JOIN tags t2 ON t2.id = uft2.tag_id
          WHERE uft2.food_id = fd.id
            AND uft2.user_id::text = current_setting('request.jwt.claims',true)::json->>'sub'
            AND t2.slug = ANY(filter_tags)
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

-- Helper: get all tags available for filtering (in user's visible foods)
DROP FUNCTION IF EXISTS get_available_food_tags();
CREATE OR REPLACE FUNCTION get_available_food_tags()
RETURNS SETOF tags
LANGUAGE sql SECURITY INVOKER STABLE AS $$
  SELECT DISTINCT t.* FROM tags t
  WHERE EXISTS (
    SELECT 1 FROM food_public_tags fpt
    JOIN food_database fd ON fd.id = fpt.food_id
    WHERE fpt.tag_id = t.id
  ) OR EXISTS (
    SELECT 1 FROM user_food_tags uft
    WHERE uft.tag_id = t.id
      AND uft.user_id::text = current_setting('request.jwt.claims',true)::json->>'sub'
  )
  ORDER BY t.name
$$;
