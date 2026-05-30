-- Tag management: let a user list the tags they created and delete them
-- globally. Deleting a tag cascades to user_food_tags (ON DELETE CASCADE in
-- sql/20_tags.sql), removing it from every food it was applied to.
--
-- get_my_tags() returns the calling user's own tags plus a GLOBAL usage count
-- (how many food assignments reference the tag, across all users). The count
-- must be global so the delete confirmation can warn honestly, but
-- user_food_tags RLS hides other users' rows from a plain SELECT — hence
-- SECURITY DEFINER. Listing is still restricted to tags the caller created,
-- so no foreign tags or per-user details leak.

BEGIN;

DROP FUNCTION IF EXISTS get_my_tags();
CREATE OR REPLACE FUNCTION get_my_tags()
RETURNS TABLE (
  id          UUID,
  name        TEXT,
  slug        TEXT,
  created_at  TIMESTAMP,
  usage_count BIGINT
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT
    t.id, t.name, t.slug, t.created_at,
    (SELECT count(*) FROM user_food_tags uft WHERE uft.tag_id = t.id) AS usage_count
  FROM tags t
  WHERE t.created_by::text = current_setting('request.jwt.claims', true)::json->>'sub'
  ORDER BY t.name
$$;

COMMIT;
