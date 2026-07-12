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
  -- The query, safe to embed in a regex: every non-alphanumeric character is
  -- escaped, so a search for "a+b" or "100%" cannot blow up the pattern.
  re       text    := regexp_replace(public.f_unaccent(query),
                                     '([^[:alnum:][:space:]])', '\\\1', 'g');
  lit_count integer := 0;
  use_fuzzy boolean := false;
BEGIN
  -- The `%>` operator (the only trigram-index-accelerated way to do fuzzy
  -- matching here) compares against pg_trgm.word_similarity_threshold, whose
  -- Postgres default is a very strict 0.6. At 0.6 the fuzzy branch is nearly
  -- dead: "jogurt", "brokoli", "spagetti" all return nothing.
  --
  -- sql/legacy/31 said this "must be set DB-wide by the owner" — and it never
  -- was, because it cannot be: ALTER DATABASE ... SET pg_trgm.* is refused
  -- ("permission denied to set parameter") until pg_trgm is loaded into the
  -- session, which it is not when you connect to run the ALTER. Setting it here
  -- sidesteps that entirely: transaction-local (is_local = true), so it cannot
  -- leak into the connection pool, and it ships with the function instead of
  -- living in a comment nobody executed.
  PERFORM set_config('pg_trgm.word_similarity_threshold', '0.4', true);

  -- Fuzzy matching is expensive and almost never actually needed, so decide up
  -- front whether to do it at all.
  --
  -- It used to be an unconditional OR in the WHERE clause. At the 0.4 threshold
  -- that is ruinous: "milch" already has 264 literal matches, but the fuzzy
  -- branch drags in a further 20,710 rows — a 34x bigger candidate set for the
  -- ranking to sort, for no benefit whatsoever. Measured: 51 ms -> 1012 ms.
  --
  -- So look literally first (this count is served by the same GIN trigram indexes,
  -- which accelerate ILIKE '%…%' as well as %>), and only fall back to fuzzy when
  -- the literal search comes back thin: a typo, an umlaut the user did not type,
  -- a foreign spelling. Passing the decision in as a variable lets the planner
  -- prune the fuzzy branches from the plan entirely rather than evaluate and
  -- discard them.
  IF do_fuzzy AND query <> '' THEN
    SELECT count(*) INTO lit_count
    FROM food_database fd
    WHERE fd.name_unaccent ILIKE '%' || ua || '%'
       OR (fd.brand_unaccent    IS NOT NULL AND fd.brand_unaccent    ILIKE '%' || ua || '%')
       OR (fd.category_unaccent IS NOT NULL AND fd.category_unaccent ILIKE '%' || ua || '%');
    use_fuzzy := lit_count < max_results;
  END IF;

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
      OR (use_fuzzy AND fd.name_unaccent %> ua)
      OR (use_fuzzy AND fd.brand_unaccent    IS NOT NULL AND fd.brand_unaccent    %> ua)
      OR (use_fuzzy AND fd.category_unaccent IS NOT NULL AND fd.category_unaccent %> ua)
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
    -- 1. Your own foods first, as before.
    CASE WHEN fd.user_id::text = uid THEN 0 ELSE 1 END ASC,

    -- 2. HOW the NAME matches, graded. The old ranking had a single
    --    "word-boundary" tier that lumped together three very different things:
    --    the name STARTING with the query, the query appearing as a word ANYWHERE
    --    in the name, and a hit on the brand or category. So "BROCCOLI" and
    --    "BBQ SRIRACHA WILD SALMON MEAL WITH BROCCOLI, ..." landed in the same
    --    tier, and the ordering below could not tell them apart.
    --
    --    Brand and category are deliberately NOT in this ladder. They are a weak
    --    signal — a food is not "broccoli" because its category mentions it — and
    --    they now rank strictly below any name match (tier 5).
    --
    --    Tiers 1 and 2 look alike but are not. In German, a HYPHEN is a word
    --    boundary, so "Kartoffel-Nuss-Brot" starts with the word "Kartoffel" —
    --    but it is a bread, not a potato. "Kartoffel geschält, roh" IS the potato.
    --    So tier 1 demands the term be followed by end-of-name, a space or a
    --    comma (the thing itself, possibly qualified), and a hyphen-compound
    --    drops to tier 2. Same for "Joghurt-Dip" vs "Joghurt ...".
    CASE
      WHEN query = ''                                            THEN 9
      WHEN fd.name_unaccent ILIKE ua                             THEN 0  -- IS the thing
      WHEN fd.name_unaccent ~* ('^' || re || '($|[[:space:],])') THEN 1  -- the thing, qualified
      WHEN fd.name_unaccent ~* ('^' || re || '\y')               THEN 2  -- a compound of it
      WHEN fd.name_unaccent ~* ('\y' || re || '\y')              THEN 3  -- a word in the name
      WHEN fd.name_unaccent ILIKE '%' || ua || '%'               THEN 4  -- substring (Milchschokolade)
      WHEN do_fuzzy AND fd.name_unaccent %> ua                   THEN 5  -- fuzzy (typos)
      ELSE                                                            6  -- brand/category only
    END ASC,

    -- 3. Within a tier: specificity, and this is the fix for the tie.
    --    word_similarity() is LENGTH-BLIND — it scores the best-matching WORD and
    --    ignores everything else — so a 116-character branded name containing
    --    "BROCCOLI" scores exactly the same 0.62 as the bare word "BROCCOLI".
    --    Every candidate tied, and the sort fell through to alphabetical, which is
    --    why "brokoli" returned a BBQ salmon meal.
    --
    --    similarity() is whole-string, so the noise around the match counts
    --    against it: 0.06 for that 116-char name vs 0.22 for a short one. That is
    --    exactly the signal the ranking was missing.
    CASE WHEN query = '' THEN 0 ELSE similarity(ua, fd.name_unaccent) END DESC,

    -- 4. Then the usual: what you actually eat, then the least padded name.
    ulu.last_used DESC NULLS LAST,
    length(fd.name) ASC,
    fd.name ASC
  LIMIT max_results;
END;
$function$

;

GRANT ALL ON FUNCTION public.search_food_database(text,text[],integer) TO authenticated;
