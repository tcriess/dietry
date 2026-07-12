-- Repeatable migration: public.search_food_database
-- Flyway re-applies this whenever the file's checksum changes, so it is the
-- SINGLE source of truth for this function. Edit here; never add another
-- CREATE OR REPLACE of it in a versioned migration (that is how the old
-- search_food_database ended up defined in six different files).

CREATE OR REPLACE FUNCTION public.search_food_database(query text, filter_tags text[] DEFAULT NULL::text[], max_results integer DEFAULT 50)
 RETURNS TABLE(id uuid, user_id uuid, name text, calories numeric, protein numeric, fat numeric, carbs numeric, fiber numeric, sugar numeric, sodium numeric, saturated_fat numeric, serving_size numeric, serving_unit text, category text, brand text, barcode text, is_public boolean, is_approved boolean, is_liquid boolean, is_favourite boolean, has_image boolean, source text, estimate_level text, portions jsonb, created_at timestamp with time zone, updated_at timestamp with time zone, tags jsonb)
 LANGUAGE plpgsql
 STABLE
AS $function$
#variable_conflict use_column
DECLARE
  ua       text    := public.f_unaccent(query);
  do_fuzzy boolean := char_length(public.f_unaccent(query)) >= 3;
  uid      text    := current_setting('request.jwt.claims', true)::json->>'sub';
BEGIN
  RETURN QUERY
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
      OR uft.user_id::text = uid
    )
    GROUP BY uft.food_id
  )
  SELECT
    fd.id, fd.user_id, fd.name, fd.calories, fd.protein, fd.fat, fd.carbs,
    fd.fiber, fd.sugar, fd.sodium, fd.saturated_fat, fd.serving_size,
    fd.serving_unit, fd.category, fd.brand, fd.barcode, fd.is_public,
    fd.is_approved, fd.is_liquid, fd.is_favourite, fd.has_image, fd.source,
    fd.estimate_level,
    fd.portions, fd.created_at, fd.updated_at,
    COALESCE(vt.tags, '[]'::jsonb) AS tags
  FROM food_database fd
  LEFT JOIN user_last_used ulu ON ulu.food_id = fd.id
  LEFT JOIN visible_tags vt ON vt.food_id = fd.id
  WHERE
    (
      query = ''
      OR fd.name_unaccent ILIKE '%' || ua || '%'
      OR (fd.brand_unaccent    IS NOT NULL AND fd.brand_unaccent    ILIKE '%' || ua || '%')
      OR (fd.category_unaccent IS NOT NULL AND fd.category_unaccent ILIKE '%' || ua || '%')
      OR (do_fuzzy AND fd.name_unaccent %> ua)
      OR (do_fuzzy AND fd.brand_unaccent    IS NOT NULL AND fd.brand_unaccent    %> ua)
      OR (do_fuzzy AND fd.category_unaccent IS NOT NULL AND fd.category_unaccent %> ua)
    )
    AND (
      filter_tags IS NULL OR
      -- An EMPTY array means "no tag filter", same as NULL. Without this branch
      -- it means "match nothing": array_length('{}', 1) is NULL (not 0), so
      -- `count(*) = array_length(...)` evaluates to NULL, which is not TRUE, and
      -- every food is filtered out. The Dart client currently converts an empty
      -- list to NULL before calling (food_database_service.dart), which is the
      -- only reason this has never bitten — but any caller passing '{}' would
      -- silently get zero results for every query.
      array_length(filter_tags, 1) IS NULL OR
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
              OR uft2.user_id::text = uid
            )
        ) AS matched_tags
      )
    )
  ORDER BY
    CASE WHEN fd.user_id::text = uid THEN 0 ELSE 1 END ASC,
    CASE WHEN query <> '' AND (
      fd.name_unaccent ILIKE ua || '%'
      OR fd.name_unaccent ILIKE '% ' || ua || '%'
      OR (fd.brand_unaccent IS NOT NULL AND (
        fd.brand_unaccent ILIKE ua || '%' OR fd.brand_unaccent ILIKE '% ' || ua || '%'
      ))
      OR (fd.category_unaccent IS NOT NULL AND (
        fd.category_unaccent ILIKE ua || '%' OR fd.category_unaccent ILIKE '% ' || ua || '%'
      ))
    ) THEN 0 ELSE 1 END ASC,
    CASE WHEN do_fuzzy THEN GREATEST(
      word_similarity(ua, fd.name_unaccent),
      COALESCE(word_similarity(ua, fd.brand_unaccent),    0.0),
      COALESCE(word_similarity(ua, fd.category_unaccent), 0.0)
    ) ELSE 0 END DESC,
    ulu.last_used DESC NULLS LAST,
    fd.name ASC
  LIMIT max_results;
END;
$function$

;

GRANT ALL ON FUNCTION public.search_food_database(text,text[],integer) TO authenticated;
