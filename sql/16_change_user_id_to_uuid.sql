-- Migration 16: Change user_id column type from TEXT to UUID in water_intake and feedback tables

-- ============================================================
-- water_intake table
-- ============================================================

-- Disable RLS and drop policies first
ALTER TABLE water_intake DISABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "water_intake_own" ON water_intake;
DROP POLICY IF EXISTS "Users can manage own water intake" ON water_intake;

ALTER TABLE water_intake ALTER COLUMN user_id type uuid using user_id::uuid;

-- Re-enable RLS and recreate policy
ALTER TABLE water_intake ENABLE ROW LEVEL SECURITY;

CREATE POLICY "water_intake_own" ON water_intake FOR ALL
  USING  (user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::UUID)
  WITH CHECK (user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::UUID);

-- ============================================================
-- feedback table
-- ============================================================

-- Disable RLS and drop policies first
ALTER TABLE feedback DISABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users insert own feedback" ON feedback;
DROP POLICY IF EXISTS "users read own feedback" ON feedback;

ALTER TABLE feedback ALTER COLUMN user_id type uuid using user_id::uuid;

-- Re-enable RLS and recreate policies
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users insert own feedback"
  ON feedback FOR INSERT
  WITH CHECK (
    user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::UUID
  );

CREATE POLICY "users read own feedback"
  ON feedback FOR SELECT
  USING (
    user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::UUID
  );
