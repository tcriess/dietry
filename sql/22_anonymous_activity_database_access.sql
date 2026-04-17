-- Migration 21: Allow anonymous users to read approved public foods

BEGIN TRANSACTION;

-- Grant SELECT privilege to anonymous role on required tables
GRANT SELECT ON activity_database TO "anonymous";

-- Drop existing policies if they exist (for idempotency)
DROP POLICY IF EXISTS "activity_database_select_public_for_anonymous" ON activity_database;

-- Add RLS policy for anonymous users to read public foods
CREATE POLICY "activity_database_select_public_for_anonymous" ON activity_database
  FOR SELECT
  TO "anonymous"
  USING (is_public = TRUE AND is_approved = TRUE);

COMMIT;
