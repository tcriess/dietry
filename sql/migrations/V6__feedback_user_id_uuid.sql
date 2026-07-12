--
-- V6__feedback_user_id_uuid.sql — bring `feedback` in line with every other
-- user-owned table, the same way V5 did for water_intake.
--
-- Two drifts, both left over from 16_change_user_id_to_uuid (the migration that
-- no longer replays):
--
--   1. user_id was TEXT, while every other user table uses UUID.
--   2. No foreign key to users — orphan rows were possible, and deleting a user
--      left their feedback behind.
--
-- Its RLS already used current_setting('request.jwt.claims'), so unlike
-- water_intake there was no auth.* dependency here. But the policies compare
-- user_id to the `sub` claim as TEXT; once the column is UUID that comparison no
-- longer type-checks (PostgreSQL has no implicit uuid = text), so they are
-- re-expressed with an explicit cast — exactly the form cheat_days already uses.
--
-- Verified before writing: 0 rows in production, so the conversion cannot lose
-- data.
--
-- NOTE — behaviour change worth knowing about: ON DELETE CASCADE means deleting a
-- user now deletes their feedback rows too. user_id is NOT NULL, so SET NULL is
-- not available, and cascading is both the convention here and the
-- privacy-correct default (a feedback message can contain personal data). If you
-- would rather keep feedback after an account is deleted, this is the line to
-- change — say so and we make user_id nullable with ON DELETE SET NULL instead.
--
-- Idempotent: every step is guarded, so re-running is a no-op.
--

-- 1. Policies come off first: PostgreSQL refuses to change the type of a column
--    that a policy definition references.
DROP POLICY IF EXISTS "users insert own feedback" ON public.feedback;
DROP POLICY IF EXISTS "users read own feedback"   ON public.feedback;
DROP POLICY IF EXISTS feedback_insert_own ON public.feedback;
DROP POLICY IF EXISTS feedback_select_own ON public.feedback;

-- 2. Drop the DEFAULT before retyping the column.
--
--    feedback.user_id is the ONLY user_id in the schema with a default:
--        DEFAULT (current_setting('request.jwt.claims', true)::json ->> 'sub')
--    which is a TEXT expression. PostgreSQL will not retype a column whose
--    default cannot be cast to the new type, and fails with
--        ERROR: default for column "user_id" cannot be cast automatically to type uuid
--
--    That is precisely — and only — why legacy 16_change_user_id_to_uuid.sql
--    still fails when replayed: it ALTERs the type without dropping this first.
--    The default is worth keeping (clients need not send user_id at all), so it
--    is dropped, the column retyped, and the default re-added cast to uuid.
ALTER TABLE public.feedback ALTER COLUMN user_id DROP DEFAULT;

-- 3. user_id: TEXT -> UUID
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'feedback'
      AND column_name = 'user_id' AND data_type = 'text'
  ) THEN
    ALTER TABLE public.feedback
      ALTER COLUMN user_id TYPE uuid USING user_id::uuid;
  END IF;
END $$;

-- 4. Restore the default, now uuid-typed.
ALTER TABLE public.feedback
  ALTER COLUMN user_id
  SET DEFAULT ((current_setting('request.jwt.claims', true)::json ->> 'sub'))::uuid;

-- 5. The missing foreign key.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.feedback'::regclass AND contype = 'f'
  ) THEN
    ALTER TABLE public.feedback
      ADD CONSTRAINT feedback_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $$;

-- 6. RLS back on. Same two commands as before (users may write and read their own
--    feedback, nothing else), renamed to the snake_case convention the rest of
--    the schema uses, and left as PUBLIC so anonymous users can still submit.
CREATE POLICY feedback_insert_own ON public.feedback FOR INSERT
  WITH CHECK (user_id = ((current_setting('request.jwt.claims', true)::json ->> 'sub'))::uuid);

CREATE POLICY feedback_select_own ON public.feedback FOR SELECT
  USING (user_id = ((current_setting('request.jwt.claims', true)::json ->> 'sub'))::uuid);
