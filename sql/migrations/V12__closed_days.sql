--
-- V12__closed_days.sql — let the user "close" a day.
--
-- Closing is a psychological commitment ("I'm done eating today"), not a data
-- rule: the app hides its edit controls for a closed day until the user reopens
-- it. Nothing on the server refuses writes for a closed day — offline replays
-- and Health Connect imports must still land.
--
-- Shaped like cheat_days / exercise_credit_days: one row per closed day,
-- absent = open.
--
-- No BEGIN/COMMIT: Flyway runs each migration in its own transaction.
--

CREATE TABLE IF NOT EXISTS public.closed_days (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  closed_date DATE        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, closed_date)
);

-- RLS on: Neon's default privileges would otherwise leave the table writable
-- by every authenticated user (see docs/database/MIGRATIONS.md).
ALTER TABLE public.closed_days ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS closed_days_select_own ON public.closed_days;
CREATE POLICY closed_days_select_own ON public.closed_days
  FOR SELECT TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

DROP POLICY IF EXISTS closed_days_insert_own ON public.closed_days;
CREATE POLICY closed_days_insert_own ON public.closed_days
  FOR INSERT TO authenticated
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

DROP POLICY IF EXISTS closed_days_update_own ON public.closed_days;
CREATE POLICY closed_days_update_own ON public.closed_days
  FOR UPDATE TO authenticated
  USING  (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'))
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

DROP POLICY IF EXISTS closed_days_delete_own ON public.closed_days;
CREATE POLICY closed_days_delete_own ON public.closed_days
  FOR DELETE TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

-- Explicit for self-hosters, who don't get Neon's default privileges.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.closed_days TO authenticated;

COMMENT ON TABLE public.closed_days IS
  'Days the user closed. The app treats them as read-only until reopened; the server does not enforce it.';
