--
-- V7__anonymous_read_access.sql — make guest mode actually work, and close a leak
-- that granting it would otherwise widen.
--
-- WHAT WAS BROKEN
-- The app's guest mode fetches an anonymous JWT from Neon Auth
-- (AnonymousAuthService) and uses it to read the public food and activity
-- databases — add_food_entry_screen.dart:229 and add_activity_screen.dart:108.
-- That token carries `role: "anonymous"`, so PostgREST switches to the Postgres
-- role of the same name. In production that role has **no table privileges at
-- all**, so every guest food search and activity lookup fails with
--
--     ERROR: permission denied for table food_database
--
-- FoodDatabaseService.searchFoods swallows the error and returns [], so it
-- surfaces as a silently empty list rather than an error — which is why it went
-- unnoticed.
--
-- The old sql/legacy/21_ and 22_ migrations were written to grant exactly this
-- and were never applied to production (neither their GRANTs nor their policies
-- are present). This is them, corrected.
--
-- WHY food_entries IS GRANTED
-- search_food_database is SECURITY INVOKER (correctly — it relies on RLS to hide
-- private foods) and its `user_last_used` CTE reads food_entries. Without the
-- grant the whole function fails for the anonymous role. With it, RLS still
-- applies: food_entries' only SELECT policy is `TO authenticated`, so no policy
-- matches the anonymous role and it sees zero rows. The LEFT JOIN then just
-- yields a NULL last_used, which is right.
--
-- SAFETY OF THE ANONYMOUS JWT
-- Its `sub` claim is the literal string "anonymous", NOT a uuid. A policy that
-- casts sub to uuid would therefore THROW ("invalid input syntax for type uuid")
-- rather than simply match nothing. Checked: every policy the anonymous role can
-- reach compares as text. Do not add a uuid-casting policy to any table granted
-- below.
--

-- ---------------------------------------------------------------------------
-- 1. Fix a tautology in user_food_tags' policy FIRST.
-- ---------------------------------------------------------------------------
-- The existing policy reads:
--
--     user_id = sub  OR  EXISTS (SELECT 1 FROM food_database fd
--                                WHERE fd.id = food_id
--                                  AND fd.user_id::text = fd.user_id::text)
--                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
--                                      always TRUE — compares a column to itself
--
-- so the second branch matches every row: **every user can already read every
-- other user's tag assignments.** tag_service.dart:204 even documents the
-- intent it fails to implement — "RLS will automatically filter to visible tags
-- (owner + current user)".
--
-- The intended rule is the one search_food_database's `visible_tags` CTE gets
-- right: a tag is visible if the FOOD'S OWNER applied it, or if it is your own.
-- Fixing it is a prerequisite for the grant below — otherwise handing
-- `anonymous` SELECT on this table would publish every user's tags to anyone
-- with an anonymous token.
--
-- No app change needed: the only direct reader (tag_service.dart:205) already
-- expects exactly this rule, and search results are unaffected because the
-- function applies the same condition itself.
DROP POLICY IF EXISTS uft_select ON public.user_food_tags;

CREATE POLICY uft_select ON public.user_food_tags FOR SELECT
  USING (
    user_id::text = (current_setting('request.jwt.claims', true)::json ->> 'sub')
    OR EXISTS (
      SELECT 1 FROM public.food_database fd
      WHERE fd.id = user_food_tags.food_id
        AND fd.user_id::text = user_food_tags.user_id::text
    )
  );

-- ---------------------------------------------------------------------------
-- 2. Privileges for the anonymous role.
-- ---------------------------------------------------------------------------
-- RLS still decides which ROWS; these only decide which TABLES may be touched.
GRANT SELECT ON public.food_database     TO anonymous;
GRANT SELECT ON public.food_images       TO anonymous;
GRANT SELECT ON public.food_entries      TO anonymous;  -- 0 rows; needed by the search RPC
GRANT SELECT ON public.tags              TO anonymous;
GRANT SELECT ON public.user_food_tags    TO anonymous;
GRANT SELECT ON public.activity_database TO anonymous;

-- ---------------------------------------------------------------------------
-- 3. Row policies for the anonymous role.
-- ---------------------------------------------------------------------------
-- food_database and activity_database have exactly one SELECT policy each, both
-- `TO authenticated`, which does not apply to the anonymous role — so without a
-- policy of its own it would see nothing even with the grant. Public + APPROVED
-- rows only: an unapproved public food is still its author's private business.
--
-- food_images needs no policy: its food_images_select policy is TO PUBLIC and
-- already permits images of approved foods.
DROP POLICY IF EXISTS food_database_select_public_for_anonymous ON public.food_database;
CREATE POLICY food_database_select_public_for_anonymous ON public.food_database
  FOR SELECT TO anonymous
  USING (is_public = TRUE AND is_approved = TRUE);

DROP POLICY IF EXISTS activity_database_select_public_for_anonymous ON public.activity_database;
CREATE POLICY activity_database_select_public_for_anonymous ON public.activity_database
  FOR SELECT TO anonymous
  USING (is_public = TRUE AND is_approved = TRUE);
