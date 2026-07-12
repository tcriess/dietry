-- Repeatable migration: public.list_own_foods
-- Flyway re-applies this whenever the file's checksum changes, so it is the
-- SINGLE source of truth for this function. Edit here; never add another
-- CREATE OR REPLACE of it in a versioned migration (that is how the old
-- search_food_database ended up defined in six different files).

CREATE OR REPLACE FUNCTION public.list_own_foods(max_results integer DEFAULT 500)
 RETURNS TABLE(id uuid, user_id uuid, name text, calories numeric, protein numeric, fat numeric, carbs numeric, fiber numeric, sugar numeric, sodium numeric, saturated_fat numeric, serving_size numeric, serving_unit text, category text, brand text, barcode text, is_public boolean, is_approved boolean, is_liquid boolean, is_favourite boolean, has_image boolean, source text, estimate_level text, portions jsonb, created_at timestamp with time zone, updated_at timestamp with time zone, tags jsonb)
 LANGUAGE sql
 STABLE
AS $function$
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
$function$

;

GRANT ALL ON FUNCTION public.list_own_foods(integer) TO authenticated;
