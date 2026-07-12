-- Fix cheat_days schema: change user_id from TEXT to UUID and add proper RLS
-- This ensures consistency with other tables and fixes the daily_nutrition_summary view

-- 1. Drop the existing policy first (since we're modifying the table)
DROP POLICY IF EXISTS "cheat_days_own" ON cheat_days;

-- 2. Alter the column type from TEXT to UUID
ALTER TABLE cheat_days
  ALTER COLUMN user_id TYPE UUID USING user_id::uuid;

-- 3. Add foreign key constraint to users(id)
ALTER TABLE cheat_days
  ADD CONSTRAINT cheat_days_user_id_fk
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- 4. Create new RLS policies (matching pattern from other UUID user_id tables)
CREATE POLICY "cheat_days_select_own" ON cheat_days FOR SELECT
  USING (user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::uuid);

CREATE POLICY "cheat_days_insert_own" ON cheat_days FOR INSERT
  WITH CHECK (user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::uuid);

CREATE POLICY "cheat_days_update_own" ON cheat_days FOR UPDATE
  USING (user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::uuid)
  WITH CHECK (user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::uuid);

CREATE POLICY "cheat_days_delete_own" ON cheat_days FOR DELETE
  USING (user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::uuid);

-- 5. Fix daily_nutrition_summary view to exclude cheat days
CREATE OR REPLACE VIEW daily_nutrition_summary AS
SELECT
  user_id,
  entry_date,
  COUNT(*)        AS total_entries,
  SUM(calories)   AS total_calories,
  SUM(protein)    AS total_protein,
  SUM(fat)        AS total_fat,
  SUM(carbs)      AS total_carbs,
  SUM(fiber)      AS total_fiber,
  SUM(sugar)      AS total_sugar,
  SUM(sodium)     AS total_sodium
FROM food_entries
WHERE NOT EXISTS (
  SELECT 1 FROM cheat_days
  WHERE cheat_days.user_id = food_entries.user_id
  AND cheat_days.cheat_date = food_entries.entry_date
)
GROUP BY user_id, entry_date;
