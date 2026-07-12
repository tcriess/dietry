--
-- V5__water_intake_align.sql — bring water_intake in line with every other
-- user-owned table.
--
-- It was the only table in the schema left behind by 16_change_user_id_to_uuid
-- (the migration that no longer replays at all), and it drifted in three ways:
--
--   1. user_id was TEXT, while every other user table uses UUID.
--   2. It had NO foreign key to users — orphan rows were possible, and deleting
--      a user left their water rows behind instead of cascading.
--   3. Its RLS was a single FOR ALL policy on auth.user_id(), a function from
--      Neon's pg_session_jwt extension, where every other table uses the four
--      current_setting('request.jwt.claims') policies.
--
-- (3) is the one that mattered beyond tidiness: it was the last thing in the
-- Community Edition schema that depended on a Neon-specific extension, so CE
-- could not be self-hosted on stock PostgreSQL. After this migration nothing in
-- CE references auth.* at all.
--
-- Verified before writing: all 100 production rows hold valid UUIDs and none is
-- an orphan, so the column conversion cannot lose data.
--
-- Written idempotently: V1 already builds water_intake in its corrected shape,
-- so on a fresh database every step below is a no-op. On an existing database
-- (production) each step does the real work. Both converge on the same schema.
--

-- 1. Drop the existing policies FIRST. PostgreSQL refuses to change the type of
--    a column that a policy definition references ("cannot alter type of a
--    column used in a policy definition"), so the RLS has to come off before
--    step 2 can run.
DROP POLICY IF EXISTS "Users can manage own water intake" ON public.water_intake;
DROP POLICY IF EXISTS water_intake_select_own ON public.water_intake;
DROP POLICY IF EXISTS water_intake_insert_own ON public.water_intake;
DROP POLICY IF EXISTS water_intake_update_own ON public.water_intake;
DROP POLICY IF EXISTS water_intake_delete_own ON public.water_intake;

-- 2. user_id: TEXT -> UUID
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'water_intake'
      AND column_name = 'user_id' AND data_type = 'text'
  ) THEN
    ALTER TABLE public.water_intake
      ALTER COLUMN user_id TYPE uuid USING user_id::uuid;
  END IF;
END $$;

-- 3. The missing foreign key, matching cheat_days.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.water_intake'::regclass AND contype = 'f'
  ) THEN
    ALTER TABLE public.water_intake
      ADD CONSTRAINT water_intake_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $$;

-- 4. RLS back on, as the standard four policies.
--    Left as PUBLIC (no TO clause), exactly like cheat_days — the anonymous role
--    reaches its own rows through the same JWT `sub` claim, so restricting these
--    to `authenticated` would break anonymous users' water tracking.
--
--    RLS itself is never disabled at any point above; dropping the policies with
--    RLS still enabled means the table denies all non-owner access for the
--    duration of this migration, which runs in a single Flyway transaction. It
--    fails closed, not open.
CREATE POLICY water_intake_select_own ON public.water_intake FOR SELECT
  USING (user_id = ((current_setting('request.jwt.claims', true)::json ->> 'sub'))::uuid);

CREATE POLICY water_intake_insert_own ON public.water_intake FOR INSERT
  WITH CHECK (user_id = ((current_setting('request.jwt.claims', true)::json ->> 'sub'))::uuid);

CREATE POLICY water_intake_update_own ON public.water_intake FOR UPDATE
  USING      (user_id = ((current_setting('request.jwt.claims', true)::json ->> 'sub'))::uuid)
  WITH CHECK (user_id = ((current_setting('request.jwt.claims', true)::json ->> 'sub'))::uuid);

CREATE POLICY water_intake_delete_own ON public.water_intake FOR DELETE
  USING (user_id = ((current_setting('request.jwt.claims', true)::json ->> 'sub'))::uuid);
