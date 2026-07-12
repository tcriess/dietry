-- Repeatable migration: public.get_available_food_tags
-- Flyway re-applies this whenever the file's checksum changes, so it is the
-- SINGLE source of truth for this function. Edit here; never add another
-- CREATE OR REPLACE of it in a versioned migration (that is how the old
-- search_food_database ended up defined in six different files).

CREATE OR REPLACE FUNCTION public.get_available_food_tags()
 RETURNS TABLE(id uuid, name text, slug text, created_by uuid, created_at timestamp without time zone)
 LANGUAGE sql
 STABLE
AS $function$
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
$function$

;

GRANT ALL ON FUNCTION public.get_available_food_tags() TO authenticated;
