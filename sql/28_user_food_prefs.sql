-- Per-user portion presets for foods (public or own). Stores the amount/unit
-- the user last logged for a given food so the quick-add flow can pre-fill
-- their typical portion instead of the food's generic serving size.

BEGIN;

CREATE TABLE IF NOT EXISTS user_food_prefs (
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  food_id      UUID NOT NULL REFERENCES food_database(id) ON DELETE CASCADE,
  last_amount  DECIMAL(10, 2) NOT NULL,
  last_unit    TEXT NOT NULL,
  updated_at   TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (user_id, food_id)
);

-- Lookup pattern is "give me my prefs for this set of food ids" — the PK
-- covers (user_id, food_id) already; no extra index needed.

ALTER TABLE user_food_prefs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_food_prefs_select ON user_food_prefs;
CREATE POLICY user_food_prefs_select ON user_food_prefs FOR SELECT
  USING (user_id::text = current_setting('request.jwt.claims', true)::json->>'sub');

DROP POLICY IF EXISTS user_food_prefs_insert ON user_food_prefs;
CREATE POLICY user_food_prefs_insert ON user_food_prefs FOR INSERT
  WITH CHECK (user_id::text = current_setting('request.jwt.claims', true)::json->>'sub');

DROP POLICY IF EXISTS user_food_prefs_update ON user_food_prefs;
CREATE POLICY user_food_prefs_update ON user_food_prefs FOR UPDATE
  USING (user_id::text = current_setting('request.jwt.claims', true)::json->>'sub');

DROP POLICY IF EXISTS user_food_prefs_delete ON user_food_prefs;
CREATE POLICY user_food_prefs_delete ON user_food_prefs FOR DELETE
  USING (user_id::text = current_setting('request.jwt.claims', true)::json->>'sub');

COMMIT;
