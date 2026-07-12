-- Repeatable migration: public.get_my_tags
-- Flyway re-applies this whenever the file's checksum changes, so it is the
-- SINGLE source of truth for this function. Edit here; never add another
-- CREATE OR REPLACE of it in a versioned migration (that is how the old
-- search_food_database ended up defined in six different files).

CREATE OR REPLACE FUNCTION public.get_my_tags()
 RETURNS TABLE(id uuid, name text, slug text, created_at timestamp without time zone, usage_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT
    t.id, t.name, t.slug, t.created_at,
    (SELECT count(*) FROM user_food_tags uft WHERE uft.tag_id = t.id) AS usage_count
  FROM tags t
  WHERE t.created_by::text = current_setting('request.jwt.claims', true)::json->>'sub'
  ORDER BY t.name
$function$

;

GRANT ALL ON FUNCTION public.get_my_tags() TO authenticated;
