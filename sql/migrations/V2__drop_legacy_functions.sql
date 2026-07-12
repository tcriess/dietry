--
-- V2__drop_legacy_functions.sql — remove two dead objects found in production.
--
-- Both are drift, not features. Dropping them here makes a freshly-built
-- database and a migrated production database converge on the same schema.
--
-- 1. search_food_database(text, integer)
--    The two-argument overload, superseded by the three-argument
--    (query, filter_tags, max_results) version when tag filtering landed. It was
--    never dropped, so production carries two overloads of the same RPC. The app
--    only ever calls the three-argument one, but PostgREST resolving an RPC
--    against two candidate signatures is a bug waiting to happen.
--
-- 2. update_physical_activities_updated_at()
--    An orphan. The physical_activities_updated_at trigger uses the shared
--    update_updated_at_column() instead; nothing references this function.
--
-- IF EXISTS: on a fresh database V1 never created these, so this is a no-op.
--

DROP FUNCTION IF EXISTS public.search_food_database(text, integer);

DROP FUNCTION IF EXISTS public.update_physical_activities_updated_at();
