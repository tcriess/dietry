-- Migration 21: Allow anonymous users to read approved public foods

BEGIN TRANSACTION;

-- Grant SELECT privilege to anonymous role on required tables
-- (needed for search_food_database RPC function)
GRANT SELECT ON food_database TO "anonymous";
GRANT SELECT ON food_images TO "anonymous";
GRANT SELECT ON food_entries TO "anonymous";
GRANT SELECT ON tags TO "anonymous";
GRANT SELECT ON user_food_tags TO "anonymous";

-- Drop existing policies if they exist (for idempotency)
DROP POLICY IF EXISTS "food_database_select_public_for_anonymous" ON food_database;
DROP POLICY IF EXISTS "food_images_select_public_for_anonymous" ON food_images;

-- Add RLS policy for anonymous users to read public foods
CREATE POLICY "food_database_select_public_for_anonymous" ON food_database
  FOR SELECT
  TO "anonymous"
  USING (is_public = TRUE AND is_approved = TRUE);

-- Similarly, allow anonymous users to read public food images
CREATE POLICY "food_images_select_public_for_anonymous" ON food_images
  FOR SELECT
  TO "anonymous"
  USING (
    -- Can only see images for public approved foods
    EXISTS (
      SELECT 1 FROM food_database
      WHERE food_database.id = food_images.food_id
      AND food_database.is_public = TRUE
      AND food_database.is_approved = TRUE
    )
  );

COMMIT;
