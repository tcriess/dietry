--
-- Flyway callback: lock down Flyway's own schema-history tables.
--
-- WHY THIS IS NEEDED
-- Neon configures the project with
--
--     ALTER DEFAULT PRIVILEGES FOR ROLE dietry IN SCHEMA public
--       GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
--
-- so EVERY table the migration role creates in `public` is automatically writable
-- by `authenticated`, with RLS off. Flyway creates flyway_history_ce /
-- flyway_history_cloud exactly that way — and `public` is the schema PostgREST
-- exposes. The result, verified on a migrated copy of production: any user who
-- signs up can, over the Data API,
--
--     DELETE /flyway_history_ce?version=eq.7        -> Flyway re-runs V7; V3 then
--                                                      dies on "table gear already
--                                                      exists" and deploys break
--     POST   /flyway_history_ce {version:8, ...}    -> marks a migration that has
--                                                      NOT run as applied, so it is
--                                                      silently SKIPPED forever
--     PATCH  /flyway_history_ce {checksum: 0}       -> `flyway validate` fails; CI
--                                                      goes permanently red
--
-- That is an integrity attack on the deployment pipeline, reachable by anyone with
-- an account. It is not caught by "add RLS" alone — see below.
--
-- WHY A CALLBACK AND NOT A VERSIONED MIGRATION
-- The history table is created by Flyway itself, before any migration runs, and it
-- is re-created if a database is ever re-baselined. A callback runs after EVERY
-- migrate, so the lock is re-asserted rather than being a one-time fix that a
-- future `baseline` would quietly undo.
--
-- ORDERING: this file is numbered 10 and the PostgREST reload is 90, because
-- Flyway runs callbacks in name order. The privileges must be gone BEFORE
-- PostgREST re-reads the schema, or it would keep exposing the table until the
-- next reload.
--

DO $$
DECLARE
  t    record;
  role text;
BEGIN
  FOR t IN
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND tablename LIKE 'flyway\_history%'
  LOOP
    -- 1. Take the privileges away. This is the real fix: with no privilege, RLS
    --    never even comes into play, and PostgREST stops exposing the table.
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC', t.tablename);

    FOREACH role IN ARRAY ARRAY['authenticated', 'anonymous', 'authenticator'] LOOP
      -- Guard: a self-hosted Community Edition may not have all of these roles.
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role) THEN
        EXECUTE format('REVOKE ALL ON public.%I FROM %I', t.tablename, role);
      END IF;
    END LOOP;

    -- 2. Defence in depth. RLS with NO policy denies every row to every non-owner,
    --    so even if something re-grants the table (a future ALTER DEFAULT
    --    PRIVILEGES, a careless GRANT ... ON ALL TABLES), it still leaks nothing.
    --
    --    This does not affect Flyway: it connects as the table's OWNER, and an
    --    owner bypasses RLS unless FORCE ROW LEVEL SECURITY is set — which it
    --    deliberately is not.
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t.tablename);
  END LOOP;
END $$;
