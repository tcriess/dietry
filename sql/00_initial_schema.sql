-- ============================================================
-- Dietry — Community Edition — Initial Schema
-- ============================================================
-- Run this on a fresh database to create the complete schema.
-- Cloud Edition additions are in dietry-cloud/sql/00_cloud_schema.sql.
--
-- Supersedes migrations 00–16, 21, 22.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. Shared trigger function
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 2. users
-- ============================================================

CREATE TABLE IF NOT EXISTS users (
  id              UUID        PRIMARY KEY,
  email           TEXT        NOT NULL UNIQUE,
  name            TEXT,

  -- Static profile data (migration 07)
  birthdate       DATE,
  height          NUMERIC(5,1) CHECK (height >= 100 AND height <= 250),
  gender          TEXT        CHECK (gender IN ('male', 'female')),
  activity_level  TEXT        CHECK (activity_level IN ('sedentary', 'light', 'moderate', 'active', 'veryActive')),
  weight_goal     TEXT        CHECK (weight_goal IN ('lose', 'maintain', 'gain')),

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_login_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_users_email      ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at DESC);

CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_select_own" ON users FOR SELECT TO authenticated
  USING (id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "users_insert_own" ON users FOR INSERT TO authenticated
  WITH CHECK (id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "users_update_own" ON users FOR UPDATE TO authenticated
  USING  (id::text = (current_setting('request.jwt.claims', true)::json->>'sub'))
  WITH CHECK (id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "users_delete_own" ON users FOR DELETE TO authenticated
  USING (id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

-- upsert_user: handles same-email/different-id after Neon Auth regenerates sub
CREATE OR REPLACE FUNCTION upsert_user(
  p_id    UUID,
  p_email TEXT,
  p_name  TEXT DEFAULT NULL
)
RETURNS SETOF users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM users WHERE id = p_id) THEN
    RETURN QUERY
      UPDATE users
      SET name = COALESCE(p_name, name), last_login_at = NOW(), updated_at = NOW()
      WHERE id = p_id
      RETURNING *;
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE email = p_email) THEN
    DELETE FROM users WHERE email = p_email;
  END IF;

  RETURN QUERY
    INSERT INTO users (id, email, name, last_login_at)
    VALUES (p_id, p_email, p_name, NOW())
    RETURNING *;
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_user(UUID, TEXT, TEXT) TO authenticated;

-- ============================================================
-- 3. nutrition_goals
-- ============================================================

CREATE TABLE IF NOT EXISTS nutrition_goals (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  calories         NUMERIC(8,2) NOT NULL CHECK (calories > 0),
  protein          NUMERIC(8,2) NOT NULL CHECK (protein >= 0),
  fat              NUMERIC(8,2) NOT NULL CHECK (fat >= 0),
  carbs            NUMERIC(8,2) NOT NULL CHECK (carbs >= 0),
  tracking_method  TEXT,                   -- migration 14; NULL = legacy (tdeeHybrid)
  water_goal_ml    INTEGER,                -- migration 15
  valid_from       DATE        NOT NULL DEFAULT CURRENT_DATE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, valid_from)
);

CREATE INDEX IF NOT EXISTS idx_nutrition_goals_user_id    ON nutrition_goals(user_id);
CREATE INDEX IF NOT EXISTS idx_nutrition_goals_valid_from ON nutrition_goals(valid_from);

CREATE TRIGGER update_nutrition_goals_updated_at
  BEFORE UPDATE ON nutrition_goals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE nutrition_goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "nutrition_goals_insert_own" ON nutrition_goals FOR INSERT TO authenticated
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "nutrition_goals_select_own" ON nutrition_goals FOR SELECT TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "nutrition_goals_update_own" ON nutrition_goals FOR UPDATE TO authenticated
  USING  (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'))
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "nutrition_goals_delete_own" ON nutrition_goals FOR DELETE TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

-- ============================================================
-- 4. user_body_measurements  (migration 07 — replaces user_body_data)
-- ============================================================

CREATE TABLE IF NOT EXISTS user_body_measurements (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  weight              NUMERIC(5,1) NOT NULL CHECK (weight >= 30 AND weight <= 300),
  body_fat_percentage NUMERIC(4,1) CHECK (body_fat_percentage >= 0 AND body_fat_percentage <= 50),
  muscle_mass_kg      NUMERIC(5,1),
  waist_cm            NUMERIC(5,1),
  measured_at         DATE        NOT NULL DEFAULT CURRENT_DATE,
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, measured_at)
);

CREATE INDEX IF NOT EXISTS idx_user_body_measurements_user_id
  ON user_body_measurements(user_id);
CREATE INDEX IF NOT EXISTS idx_user_body_measurements_date
  ON user_body_measurements(user_id, measured_at DESC);

CREATE TRIGGER user_body_measurements_updated_at
  BEFORE UPDATE ON user_body_measurements
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE user_body_measurements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_body_measurements_select_own" ON user_body_measurements FOR SELECT
  USING (user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::uuid);

CREATE POLICY "user_body_measurements_insert_own" ON user_body_measurements FOR INSERT
  WITH CHECK (user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::uuid);

CREATE POLICY "user_body_measurements_update_own" ON user_body_measurements FOR UPDATE
  USING (user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::uuid);

CREATE POLICY "user_body_measurements_delete_own" ON user_body_measurements FOR DELETE
  USING (user_id = (current_setting('request.jwt.claims', true)::json->>'sub')::uuid);

-- View: current profile + latest measurement
CREATE OR REPLACE VIEW user_current_data AS
SELECT
  u.id AS user_id,
  u.email,
  u.name,
  u.birthdate,
  u.height,
  u.gender,
  u.activity_level,
  u.weight_goal,
  EXTRACT(YEAR FROM AGE(CURRENT_DATE, u.birthdate))::INTEGER AS age,
  m.id AS measurement_id,
  m.weight,
  m.body_fat_percentage,
  m.muscle_mass_kg,
  m.waist_cm,
  m.measured_at,
  m.notes
FROM users u
LEFT JOIN LATERAL (
  SELECT * FROM user_body_measurements
  WHERE user_id = u.id
  ORDER BY measured_at DESC
  LIMIT 1
) m ON true;

ALTER VIEW user_current_data SET (security_invoker = true);

-- ============================================================
-- 5. food_database
-- ============================================================

CREATE TABLE IF NOT EXISTS food_database (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        REFERENCES users(id) ON DELETE CASCADE,  -- NULL = admin seed
  name         TEXT        NOT NULL CHECK (LENGTH(TRIM(name)) >= 2),

  -- Nutrition per 100 g / 100 ml
  calories     NUMERIC(8,2) NOT NULL CHECK (calories >= 0),
  protein      NUMERIC(8,2) NOT NULL CHECK (protein >= 0),
  fat          NUMERIC(8,2) NOT NULL CHECK (fat >= 0),
  carbs        NUMERIC(8,2) NOT NULL CHECK (carbs >= 0),
  fiber        NUMERIC(8,2) CHECK (fiber >= 0),
  sugar        NUMERIC(8,2) CHECK (sugar >= 0),
  sodium       NUMERIC(8,2) CHECK (sodium >= 0),  -- mg

  serving_size NUMERIC(8,2),
  serving_unit TEXT,
  category     TEXT,
  brand        TEXT,
  barcode      TEXT,

  is_public    BOOLEAN     NOT NULL DEFAULT FALSE,
  -- migration 10: user-submitted public items require admin approval
  is_approved  BOOLEAN     NOT NULL DEFAULT FALSE,
  -- migration 12: named portion sizes [{name, amount_g}, ...]
  portions     JSONB       NOT NULL DEFAULT '[]'::jsonb,
  -- migration 16: favourites
  is_favourite BOOLEAN     NOT NULL DEFAULT FALSE,

  source       TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CHECK (
    (is_public = FALSE AND user_id IS NOT NULL AND is_approved = FALSE) OR
    (is_public = TRUE)
  )
);

CREATE INDEX IF NOT EXISTS idx_food_database_user_id   ON food_database(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_food_database_name      ON food_database(LOWER(name));
CREATE INDEX IF NOT EXISTS idx_food_database_barcode   ON food_database(barcode) WHERE barcode IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_food_database_is_public ON food_database(is_public) WHERE is_public = TRUE;
CREATE INDEX IF NOT EXISTS idx_food_database_category  ON food_database(category) WHERE category IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_food_database_portions  ON food_database USING GIN (portions) WHERE portions != '[]'::jsonb;

CREATE TRIGGER update_food_database_updated_at
  BEFORE UPDATE ON food_database
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE food_database ENABLE ROW LEVEL SECURITY;

-- approved public items visible to all; own items always visible
CREATE POLICY "food_database_select_own_and_public" ON food_database FOR SELECT TO authenticated
  USING (
    (is_public = TRUE AND is_approved = TRUE) OR
    user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub')
  );

-- users may not self-approve
CREATE POLICY "food_database_insert_own" ON food_database FOR INSERT TO authenticated
  WITH CHECK (
    user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub') AND
    is_approved = FALSE
  );

-- editing resets approval
CREATE POLICY "food_database_update_own" ON food_database FOR UPDATE TO authenticated
  USING  (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'))
  WITH CHECK (
    user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub') AND
    is_approved = FALSE
  );

CREATE POLICY "food_database_delete_own" ON food_database FOR DELETE TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

-- Seed data (admin-owned public items, pre-approved)
INSERT INTO food_database (name, calories, protein, fat, carbs, serving_size, serving_unit, category, is_public, is_approved, source) VALUES
  ('Apfel',                52,  0.3,  0.2,  14,  150, 'g',           'Obst',         TRUE, TRUE, 'USDA'),
  ('Banane',               89,  1.1,  0.3,  23,  120, 'g',           'Obst',         TRUE, TRUE, 'USDA'),
  ('Orange',               47,  0.9,  0.1,  12,  130, 'g',           'Obst',         TRUE, TRUE, 'USDA'),
  ('Tomate',               18,  0.9,  0.2,   3.9, 100, 'g',          'Gemüse',       TRUE, TRUE, 'USDA'),
  ('Gurke',                16,  0.7,  0.1,   3.6, 100, 'g',          'Gemüse',       TRUE, TRUE, 'USDA'),
  ('Brokkoli',             34,  2.8,  0.4,   7,  100, 'g',           'Gemüse',       TRUE, TRUE, 'USDA'),
  ('Hühnerbrust (roh)',   165, 31,    3.6,   0,  100, 'g',           'Fleisch',      TRUE, TRUE, 'USDA'),
  ('Lachs (roh)',         208, 20,   13,     0,  100, 'g',           'Fisch',        TRUE, TRUE, 'USDA'),
  ('Ei (gekocht)',        155, 13,   11,     1.1,  50, 'g (1 Ei)',   'Eier',         TRUE, TRUE, 'USDA'),
  ('Reis (gekocht)',      130,  2.7,  0.3,  28,  100, 'g',           'Getreide',     TRUE, TRUE, 'USDA'),
  ('Vollkornbrot',        247, 13,    3.3,  41,   50, 'g (1 Scheibe)','Brot',        TRUE, TRUE, 'USDA'),
  ('Kartoffel (gekocht)',  87,  2,    0.1,  20,  150, 'g',           'Gemüse',       TRUE, TRUE, 'USDA'),
  ('Milch (3,5%)',         64,  3.3,  3.5,   4.8, 250, 'ml',         'Milchprodukte',TRUE, TRUE, 'USDA'),
  ('Naturjoghurt',         61,  3.5,  3.3,   4.7, 150, 'g',          'Milchprodukte',TRUE, TRUE, 'USDA'),
  ('Magerquark',           67, 13,    0.2,   4,  100, 'g',           'Milchprodukte',TRUE, TRUE, 'USDA'),
  ('Olivenöl',            884,  0,  100,     0,   10, 'ml (1 EL)',   'Fette',        TRUE, TRUE, 'USDA'),
  ('Butter',              717,  0.9, 81,     0.1,  10, 'g',          'Fette',        TRUE, TRUE, 'USDA'),
  ('Wasser',                0,  0,    0,     0,  250, 'ml',           'Getränke',    TRUE, TRUE, 'USDA'),
  ('Apfelsaft',            46,  0.1,  0.1,  11,  200, 'ml',          'Getränke',    TRUE, TRUE, 'USDA')
ON CONFLICT DO NOTHING;

-- ============================================================
-- 6. activity_database
-- ============================================================

CREATE TABLE IF NOT EXISTS activity_database (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        REFERENCES users(id) ON DELETE CASCADE,  -- NULL = admin seed
  name         TEXT        NOT NULL CHECK (LENGTH(TRIM(name)) >= 2),
  met_value    NUMERIC(4,2) NOT NULL CHECK (met_value >= 0 AND met_value <= 20),
  category     TEXT,
  intensity    TEXT        CHECK (intensity IN ('low', 'moderate', 'high', 'very_high')),
  description  TEXT,
  avg_speed_kmh NUMERIC(5,2) CHECK (avg_speed_kmh >= 0),
  is_public    BOOLEAN     NOT NULL DEFAULT FALSE,
  -- migration 11: approval flow (same as food_database)
  is_approved  BOOLEAN     NOT NULL DEFAULT FALSE,
  -- migration 16: favourites
  is_favourite BOOLEAN     NOT NULL DEFAULT FALSE,
  source       TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CHECK (
    (is_public = FALSE AND user_id IS NOT NULL AND is_approved = FALSE) OR
    (is_public = TRUE)
  )
);

CREATE INDEX IF NOT EXISTS idx_activity_database_user_id   ON activity_database(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activity_database_name      ON activity_database(LOWER(name));
CREATE INDEX IF NOT EXISTS idx_activity_database_is_public ON activity_database(is_public) WHERE is_public = TRUE;
CREATE INDEX IF NOT EXISTS idx_activity_database_category  ON activity_database(category) WHERE category IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activity_database_met_value ON activity_database(met_value);

CREATE TRIGGER update_activity_database_updated_at
  BEFORE UPDATE ON activity_database
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE activity_database ENABLE ROW LEVEL SECURITY;

CREATE POLICY "activity_database_select_own_and_public" ON activity_database FOR SELECT TO authenticated
  USING (
    (is_public = TRUE AND is_approved = TRUE) OR
    user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub')
  );

CREATE POLICY "activity_database_insert_own" ON activity_database FOR INSERT TO authenticated
  WITH CHECK (
    user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub') AND
    is_approved = FALSE
  );

CREATE POLICY "activity_database_update_own" ON activity_database FOR UPDATE TO authenticated
  USING  (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'))
  WITH CHECK (
    user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub') AND
    is_approved = FALSE
  );

CREATE POLICY "activity_database_delete_own" ON activity_database FOR DELETE TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

-- Seed data
INSERT INTO activity_database (name, met_value, category, intensity, description, avg_speed_kmh, is_public, is_approved, source) VALUES
  ('Gehen (langsam)',        2.5, 'Ausdauer', 'low',       'Spaziergang, gemütliches Tempo',    3.0,  TRUE, TRUE, 'Compendium'),
  ('Gehen (normal)',         3.5, 'Ausdauer', 'moderate',  'Normale Gehgeschwindigkeit',         5.0,  TRUE, TRUE, 'Compendium'),
  ('Gehen (schnell)',        4.5, 'Ausdauer', 'moderate',  'Zügiges Gehen',                      6.0,  TRUE, TRUE, 'Compendium'),
  ('Wandern',                5.0, 'Ausdauer', 'moderate',  'Wandern mit Rucksack',               NULL, TRUE, TRUE, 'Compendium'),
  ('Joggen (langsam)',       7.0, 'Ausdauer', 'high',      'Lockeres Joggen',                    8.0,  TRUE, TRUE, 'Compendium'),
  ('Laufen (moderat)',       9.0, 'Ausdauer', 'high',      'Mittleres Lauftempo',               10.0,  TRUE, TRUE, 'Compendium'),
  ('Laufen (schnell)',      11.5, 'Ausdauer', 'very_high', 'Schnelles Laufen',                  12.0,  TRUE, TRUE, 'Compendium'),
  ('Sprinten',              15.0, 'Ausdauer', 'very_high', 'Maximale Geschwindigkeit',           NULL, TRUE, TRUE, 'Compendium'),
  ('Radfahren (langsam)',    4.0, 'Ausdauer', 'low',       'Gemütliches Radfahren',             12.0,  TRUE, TRUE, 'Compendium'),
  ('Radfahren (normal)',     6.8, 'Ausdauer', 'moderate',  'Normal Radfahren',                  20.0,  TRUE, TRUE, 'Compendium'),
  ('Radfahren (schnell)',   10.0, 'Ausdauer', 'high',      'Zügiges Radfahren',                 25.0,  TRUE, TRUE, 'Compendium'),
  ('Mountainbiken',          8.5, 'Ausdauer', 'high',      'Mountainbike-Tour',                  NULL, TRUE, TRUE, 'Compendium'),
  ('Schwimmen (langsam)',    5.0, 'Ausdauer', 'moderate',  'Gemütliches Schwimmen',              NULL, TRUE, TRUE, 'Compendium'),
  ('Schwimmen (normal)',     7.0, 'Ausdauer', 'high',      'Normal Schwimmen',                   NULL, TRUE, TRUE, 'Compendium'),
  ('Schwimmen (intensiv)',  10.0, 'Ausdauer', 'very_high', 'Intensives Schwimmen',               NULL, TRUE, TRUE, 'Compendium'),
  ('Krafttraining (leicht)', 3.5, 'Kraft',   'moderate',  'Leichtes Gewichtstraining',           NULL, TRUE, TRUE, 'Compendium'),
  ('Krafttraining (intensiv)',6.0,'Kraft',   'high',      'Intensives Gewichtstraining',         NULL, TRUE, TRUE, 'Compendium'),
  ('Bodyweight-Training',    4.5, 'Kraft',   'moderate',  'Training mit eigenem Körpergewicht',  NULL, TRUE, TRUE, 'Compendium'),
  ('Fußball',                7.0, 'Sport',   'high',      'Fußballspiel',                        NULL, TRUE, TRUE, 'Compendium'),
  ('Basketball',             6.5, 'Sport',   'high',      'Basketballspiel',                     NULL, TRUE, TRUE, 'Compendium'),
  ('Tennis',                 7.3, 'Sport',   'high',      'Tennisspiel',                         NULL, TRUE, TRUE, 'Compendium'),
  ('Volleyball',             4.0, 'Sport',   'moderate',  'Volleyballspiel',                     NULL, TRUE, TRUE, 'Compendium'),
  ('Badminton',              5.5, 'Sport',   'moderate',  'Badminton (Freizeit)',                 NULL, TRUE, TRUE, 'Compendium'),
  ('Yoga',                   2.5, 'Fitness', 'low',       'Hatha Yoga',                          NULL, TRUE, TRUE, 'Compendium'),
  ('Pilates',                3.0, 'Fitness', 'low',       'Pilates-Übungen',                     NULL, TRUE, TRUE, 'Compendium'),
  ('Aerobic',                6.5, 'Fitness', 'high',      'Aerobic-Kurs',                        NULL, TRUE, TRUE, 'Compendium'),
  ('Zumba',                  6.5, 'Fitness', 'high',      'Zumba-Tanzkurs',                      NULL, TRUE, TRUE, 'Compendium'),
  ('Spinning',               8.5, 'Fitness', 'high',      'Indoor-Cycling',                      NULL, TRUE, TRUE, 'Compendium'),
  ('Hausarbeit (leicht)',    2.3, 'Alltag',  'low',       'Leichte Hausarbeiten',                NULL, TRUE, TRUE, 'Compendium'),
  ('Hausarbeit (schwer)',    3.8, 'Alltag',  'moderate',  'Schwere Hausarbeiten',                NULL, TRUE, TRUE, 'Compendium'),
  ('Gartenarbeit',           4.0, 'Alltag',  'moderate',  'Gartenarbeit allgemein',              NULL, TRUE, TRUE, 'Compendium'),
  ('Rasenmähen',             5.5, 'Alltag',  'moderate',  'Rasenmähen (Handmäher)',              NULL, TRUE, TRUE, 'Compendium'),
  ('Treppensteigen',         8.0, 'Alltag',  'high',      'Treppensteigen',                      NULL, TRUE, TRUE, 'Compendium'),
  ('Skifahren (Alpin)',      6.0, 'Sport',   'moderate',  'Alpines Skifahren',                   NULL, TRUE, TRUE, 'Compendium'),
  ('Langlauf',               9.0, 'Ausdauer','high',      'Skilanglauf',                         NULL, TRUE, TRUE, 'Compendium'),
  ('Snowboarden',            5.5, 'Sport',   'moderate',  'Snowboarden',                         NULL, TRUE, TRUE, 'Compendium'),
  ('Rudern',                 7.0, 'Ausdauer','high',      'Rudern (moderat)',                    NULL, TRUE, TRUE, 'Compendium'),
  ('Kanufahren',             5.0, 'Ausdauer','moderate',  'Kanufahren (gemütlich)',              NULL, TRUE, TRUE, 'Compendium'),
  ('Stand-Up Paddling',      4.0, 'Ausdauer','moderate',  'SUP (Freizeit)',                      NULL, TRUE, TRUE, 'Compendium')
ON CONFLICT DO NOTHING;

-- ============================================================
-- 7. physical_activities
-- ============================================================
-- Note: migration 04 was corrupted; table structure reconstructed
-- from DATABASE_SETUP.md + migration 09 (activity_id/activity_name).

CREATE TABLE IF NOT EXISTS physical_activities (
  id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_type            TEXT        NOT NULL,
  -- migration 09: link to activity_database + display name
  activity_id              UUID        REFERENCES activity_database(id) ON DELETE SET NULL,
  activity_name            TEXT,
  start_time               TIMESTAMPTZ NOT NULL,
  end_time                 TIMESTAMPTZ NOT NULL,
  duration_minutes         INTEGER     NOT NULL,
  calories_burned          NUMERIC(7,2),
  distance_km              NUMERIC(6,2),
  steps                    INTEGER,
  avg_heart_rate           NUMERIC(5,2),
  notes                    TEXT,
  source                   TEXT        NOT NULL DEFAULT 'manual',
  health_connect_record_id TEXT,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, health_connect_record_id)
);

CREATE INDEX IF NOT EXISTS idx_physical_activities_user_id
  ON physical_activities(user_id);
CREATE INDEX IF NOT EXISTS idx_physical_activities_start_time
  ON physical_activities(user_id, start_time DESC);
CREATE INDEX IF NOT EXISTS idx_physical_activities_activity_id
  ON physical_activities(activity_id) WHERE activity_id IS NOT NULL;

CREATE TRIGGER update_physical_activities_updated_at
  BEFORE UPDATE ON physical_activities
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE physical_activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "physical_activities_select_own" ON physical_activities FOR SELECT TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "physical_activities_insert_own" ON physical_activities FOR INSERT TO authenticated
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "physical_activities_update_own" ON physical_activities FOR UPDATE TO authenticated
  USING  (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'))
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "physical_activities_delete_own" ON physical_activities FOR DELETE TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

-- Activity summary views
CREATE OR REPLACE VIEW daily_activity_summary AS
SELECT
  user_id,
  DATE(start_time)        AS activity_date,
  COUNT(*)                AS total_activities,
  SUM(duration_minutes)   AS total_minutes,
  SUM(calories_burned)    AS total_calories,
  SUM(distance_km)        AS total_distance_km,
  SUM(steps)              AS total_steps
FROM physical_activities
GROUP BY user_id, DATE(start_time);

CREATE OR REPLACE VIEW weekly_activity_summary AS
SELECT
  user_id,
  DATE_TRUNC('week', start_time) AS week_start,
  COUNT(*)                       AS total_activities,
  SUM(duration_minutes)          AS total_minutes,
  SUM(calories_burned)           AS total_calories,
  SUM(distance_km)               AS total_distance_km,
  SUM(steps)                     AS total_steps
FROM physical_activities
GROUP BY user_id, DATE_TRUNC('week', start_time);

CREATE OR REPLACE FUNCTION get_daily_active_minutes(p_user_id UUID, p_date DATE)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(SUM(duration_minutes), 0)::INTEGER
  FROM physical_activities
  WHERE user_id = p_user_id AND DATE(start_time) = p_date;
$$;

CREATE OR REPLACE FUNCTION get_weekly_active_minutes(p_user_id UUID, p_date DATE)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(SUM(duration_minutes), 0)::INTEGER
  FROM physical_activities
  WHERE user_id = p_user_id
    AND DATE_TRUNC('week', start_time) = DATE_TRUNC('week', p_date::TIMESTAMPTZ);
$$;

-- ============================================================
-- 8. food_entries
-- ============================================================

CREATE TABLE IF NOT EXISTS food_entries (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  food_id    UUID        REFERENCES food_database(id) ON DELETE SET NULL,
  entry_date DATE        NOT NULL DEFAULT CURRENT_DATE,
  meal_type  TEXT        NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
  name       TEXT        NOT NULL CHECK (LENGTH(TRIM(name)) >= 2),
  -- amount = grams/ml when unit IN ('g','ml'), portion count otherwise
  amount     NUMERIC(8,2) NOT NULL CHECK (amount > 0),
  unit       TEXT        NOT NULL,
  calories   NUMERIC(8,2) NOT NULL CHECK (calories >= 0),
  protein    NUMERIC(8,2) NOT NULL CHECK (protein >= 0),
  fat        NUMERIC(8,2) NOT NULL CHECK (fat >= 0),
  carbs      NUMERIC(8,2) NOT NULL CHECK (carbs >= 0),
  fiber      NUMERIC(8,2) CHECK (fiber >= 0),
  sugar      NUMERIC(8,2) CHECK (sugar >= 0),
  sodium     NUMERIC(8,2) CHECK (sodium >= 0),
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_food_entries_user_id   ON food_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_food_entries_entry_date ON food_entries(entry_date);
CREATE INDEX IF NOT EXISTS idx_food_entries_user_date  ON food_entries(user_id, entry_date);
CREATE INDEX IF NOT EXISTS idx_food_entries_food_id    ON food_entries(food_id) WHERE food_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_food_entries_meal_type  ON food_entries(meal_type);

CREATE TRIGGER update_food_entries_updated_at
  BEFORE UPDATE ON food_entries
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Auto-calculate nutrition for g/ml entries only.
-- Named-portion entries (e.g. unit='Scheibe') store amount as count;
-- the client sends pre-computed totals which must not be overwritten.
CREATE OR REPLACE FUNCTION calculate_nutrition_from_food_database()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.food_id IS NOT NULL
    AND NEW.unit IN ('g', 'ml')
    AND (
      OLD IS NULL OR
      (OLD.calories = NEW.calories AND OLD.protein = NEW.protein)
    ) THEN
    SELECT
      (NEW.amount / 100.0) * f.calories,
      (NEW.amount / 100.0) * f.protein,
      (NEW.amount / 100.0) * f.fat,
      (NEW.amount / 100.0) * f.carbs,
      (NEW.amount / 100.0) * f.fiber,
      (NEW.amount / 100.0) * f.sugar,
      (NEW.amount / 100.0) * f.sodium
    INTO
      NEW.calories, NEW.protein, NEW.fat, NEW.carbs,
      NEW.fiber, NEW.sugar, NEW.sodium
    FROM food_database f
    WHERE f.id = NEW.food_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calculate_nutrition_before_insert_or_update
  BEFORE INSERT OR UPDATE ON food_entries
  FOR EACH ROW EXECUTE FUNCTION calculate_nutrition_from_food_database();

ALTER TABLE food_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "food_entries_select_own" ON food_entries FOR SELECT TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "food_entries_insert_own" ON food_entries FOR INSERT TO authenticated
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "food_entries_update_own" ON food_entries FOR UPDATE TO authenticated
  USING  (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'))
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY "food_entries_delete_own" ON food_entries FOR DELETE TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

-- Views
CREATE OR REPLACE VIEW food_entries_detailed AS
SELECT
  e.id, e.user_id, e.entry_date, e.meal_type, e.name,
  e.amount, e.unit, e.calories, e.protein, e.fat, e.carbs,
  e.fiber, e.sugar, e.sodium, e.notes, e.created_at, e.updated_at,
  f.id       AS food_db_id,
  f.name     AS food_db_name,
  f.category,
  f.brand,
  f.is_public AS is_public_food
FROM food_entries e
LEFT JOIN food_database f ON e.food_id = f.id;

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
GROUP BY user_id, entry_date;

-- ============================================================
-- 9. water_intake  (migration 15)
-- ============================================================

CREATE TABLE IF NOT EXISTS water_intake (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    TEXT        NOT NULL,
  date       DATE        NOT NULL,
  amount_ml  INTEGER     NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, date)
);

ALTER TABLE water_intake ENABLE ROW LEVEL SECURITY;

CREATE POLICY "water_intake_own" ON water_intake FOR ALL
  USING  (user_id = (current_setting('request.jwt.claims', true)::json->>'sub'))
  WITH CHECK (user_id = (current_setting('request.jwt.claims', true)::json->>'sub'));

-- ── cheat_days ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS cheat_days (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    TEXT        NOT NULL,
  cheat_date DATE        NOT NULL,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, cheat_date)
);

ALTER TABLE cheat_days ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cheat_days_own" ON cheat_days FOR ALL
  USING  (user_id = (current_setting('request.jwt.claims', true)::json->>'sub'))
  WITH CHECK (user_id = (current_setting('request.jwt.claims', true)::json->>'sub'));

COMMIT;
