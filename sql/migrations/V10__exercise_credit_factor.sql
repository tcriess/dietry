--
-- V10__exercise_credit_factor.sql — count only *part* of a workout's burn
-- towards the day's calorie budget.
--
-- WHY
-- Today a logged workout is added to the budget one-for-one: burn 600 kcal, eat
-- 600 kcal more. Three separate effects say that is too generous:
--
--  1. Double counting. A goal built from TDEE already contains an activity
--     multiplier (see lib/models/tracking_method.dart) — with `tdeeComplete`
--     the training is priced in *before* a single activity is logged.
--  2. Gross vs. net. MET maths (MET × kg × hours) reports the total energy of
--     the hour, resting metabolism included — energy the body would have spent
--     lying on the sofa. The genuinely extra part is (MET − 1)/MET of it.
--  3. Compensation. Roughly a quarter to a third of an exercise burn is
--     absorbed by lower resting expenditure and less spontaneous movement over
--     the following day (Careau et al. 2021, n = 1754).
--
-- Plus the input itself is soft: consumer trackers' energy estimates are the
-- least accurate number they produce.
--
-- So: one factor, resolved from the most specific level that has an opinion.
--
--     activity.credit_factor  →  exercise_credit_days.factor  →  users.exercise_credit_factor  →  1.0
--
-- NULL everywhere means 1.0, i.e. exactly today's behaviour — nobody's numbers
-- move until they set a factor.
--
-- WHY A SEPARATE TABLE FOR THE PER-DAY VALUE
-- There is no row that exists for every tracked day. `nutrition_goals` is
-- valid_from-ranged (one row covers many days), `cheat_days` only exists on the
-- days that are marked. So the per-day override needs a home of its own, shaped
-- like cheat_days: surrogate id, UNIQUE (user_id, date), FK cascade.
--
-- No BEGIN/COMMIT: Flyway runs each migration in its own transaction.
--

-- ---------------------------------------------------------------------------
-- 1. The profile default.
-- ---------------------------------------------------------------------------

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS exercise_credit_factor numeric(4,3);

ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS users_exercise_credit_factor_range;

-- Upper bound 2 rather than 1: crediting *more* than was burned is not
-- something we want to recommend, but it is a legitimate way to model a goal
-- that was set too low on training days, and a bound keeps a fat-fingered
-- "50" (meant as a percentage) out of the database.
ALTER TABLE public.users
  ADD CONSTRAINT users_exercise_credit_factor_range
  CHECK (exercise_credit_factor IS NULL
         OR (exercise_credit_factor >= 0 AND exercise_credit_factor <= 2));

COMMENT ON COLUMN public.users.exercise_credit_factor IS
  'Default share of a workout''s burn added to the daily calorie budget. NULL = 1.0 (count all of it).';

-- ---------------------------------------------------------------------------
-- 2. The per-activity override.
-- ---------------------------------------------------------------------------

ALTER TABLE public.physical_activities
  ADD COLUMN IF NOT EXISTS credit_factor numeric(4,3);

ALTER TABLE public.physical_activities
  DROP CONSTRAINT IF EXISTS physical_activities_credit_factor_range;

ALTER TABLE public.physical_activities
  ADD CONSTRAINT physical_activities_credit_factor_range
  CHECK (credit_factor IS NULL OR (credit_factor >= 0 AND credit_factor <= 2));

COMMENT ON COLUMN public.physical_activities.credit_factor IS
  'Share of THIS workout''s burn to credit. NULL = fall through to the day, then the profile, then 1.0.';

-- ---------------------------------------------------------------------------
-- 3. The per-day override.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.exercise_credit_days (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  credit_date DATE        NOT NULL,
  factor      NUMERIC(4,3) NOT NULL CHECK (factor >= 0 AND factor <= 2),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, credit_date)
);

CREATE INDEX IF NOT EXISTS idx_exercise_credit_days_user_date
  ON public.exercise_credit_days(user_id, credit_date);

DROP TRIGGER IF EXISTS update_exercise_credit_days_updated_at
  ON public.exercise_credit_days;
CREATE TRIGGER update_exercise_credit_days_updated_at
  BEFORE UPDATE ON public.exercise_credit_days
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Every table this role creates in `public` is writable by `authenticated` with
-- RLS off (Neon's ALTER DEFAULT PRIVILEGES; see docs/database/MIGRATIONS.md).
-- Without the two statements below the table would be world-writable over the
-- Data API from the moment it exists.
ALTER TABLE public.exercise_credit_days ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS exercise_credit_days_select_own ON public.exercise_credit_days;
CREATE POLICY exercise_credit_days_select_own ON public.exercise_credit_days
  FOR SELECT TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

DROP POLICY IF EXISTS exercise_credit_days_insert_own ON public.exercise_credit_days;
CREATE POLICY exercise_credit_days_insert_own ON public.exercise_credit_days
  FOR INSERT TO authenticated
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

DROP POLICY IF EXISTS exercise_credit_days_update_own ON public.exercise_credit_days;
CREATE POLICY exercise_credit_days_update_own ON public.exercise_credit_days
  FOR UPDATE TO authenticated
  USING  (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'))
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

DROP POLICY IF EXISTS exercise_credit_days_delete_own ON public.exercise_credit_days;
CREATE POLICY exercise_credit_days_delete_own ON public.exercise_credit_days
  FOR DELETE TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

-- Explicit, because a self-hoster does not get Neon's default privileges and
-- their PostgREST would 404 on the table.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.exercise_credit_days TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Teach the reports view what is actually credited.
-- ---------------------------------------------------------------------------
--
-- The reports page draws the daily target as "goal + burn". Leaving that alone
-- would have the charts and the overview screen disagree about the same day, so
-- the view gains a second sum next to the gross one. total_calories keeps its
-- meaning — what the body spent — and the new column is what the budget got.
--
-- Appended at the end: CREATE OR REPLACE VIEW may add columns but not rename,
-- retype or reorder the existing ones.
--
-- security_invoker is re-asserted below. It survives a replace in current
-- PostgreSQL, but this view is the one V4 had to retrofit precisely because
-- nobody noticed it was missing; saying it out loud costs nothing.
--
-- The joins are safe under RLS: the caller may read their own users row
-- (users_select_own) and their own credit days, and every physical_activities
-- row they can see is theirs, so the join can only ever match their own values.

CREATE OR REPLACE VIEW public.daily_activity_summary AS
 SELECT pa.user_id,
    date(pa.start_time) AS activity_date,
    count(*) AS activity_count,
    sum(pa.duration_minutes) AS total_minutes,
    sum(pa.calories_burned) AS total_calories,
    sum(pa.distance_km) AS total_distance_km,
    sum(pa.steps) AS total_steps,
    array_agg(DISTINCT pa.activity_type) AS activity_types,
    sum(pa.calories_burned
        * COALESCE(pa.credit_factor, ecd.factor, u.exercise_credit_factor, 1))
      AS total_credited_calories
   FROM public.physical_activities pa
   LEFT JOIN public.users u
          ON u.id = pa.user_id
   LEFT JOIN public.exercise_credit_days ecd
          ON ecd.user_id = pa.user_id
         AND ecd.credit_date = date(pa.start_time)
  GROUP BY pa.user_id, date(pa.start_time);

ALTER VIEW public.daily_activity_summary SET (security_invoker = true);

GRANT SELECT ON public.daily_activity_summary TO authenticated;
