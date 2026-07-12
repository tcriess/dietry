-- Flyway callback: runs after every successful `migrate`.
--
-- PostgREST caches the database schema. After DDL it keeps serving the old
-- shape, so a freshly-added table or RPC 404s until the cache is reloaded —
-- the "I ran the migration but the API doesn't see it" class of bug. This
-- replaces the manual tmp/refresh_schema_cache.sh step.
--
-- Harmless when nothing is listening (e.g. a scratch branch with no Data API).
NOTIFY pgrst, 'reload schema';
