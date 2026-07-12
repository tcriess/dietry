--
-- V3__gear.sql — attribute a workout to a piece of equipment (running shoes, a
-- bike, …) so the user can ask "how many km / how many hours are on these shoes?".
--
-- Design notes:
--  * ONE gear item per activity (nullable FK), not a join table. A workout is
--    done in one pair of shoes or on one bike; the generality of a join table
--    buys nothing today and complicates the full-row INSERT/PATCH the app uses.
--  * ON DELETE SET NULL, like activity_id: deleting worn-out shoes must not
--    delete the runs made in them.
--  * default_activity_type lets Health Connect imports auto-attach gear. Most
--    runs arrive from HC, not the manual form — without this the totals would
--    stay near zero because nobody edits imported workouts by hand.
--
-- No BEGIN/COMMIT: Flyway runs each migration in its own transaction, and an
-- explicit COMMIT here would commit Flyway's transaction out from under it.
--
-- The get_gear_totals() RPC is NOT here — functions live in sql/repeatable/
-- (see R__fn_get_gear_totals.sql).
--

CREATE TABLE gear (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name                  TEXT        NOT NULL CHECK (LENGTH(TRIM(name)) >= 2),
  category              TEXT        NOT NULL DEFAULT 'shoes'
                                    CHECK (category IN ('shoes', 'bike', 'other')),
  -- ActivityType enum name (e.g. 'running'). NULL = no auto-attach.
  default_activity_type TEXT,
  -- km already on the item before tracking started.
  initial_distance_km   NUMERIC(7,2) NOT NULL DEFAULT 0 CHECK (initial_distance_km >= 0),
  -- Optional wear budget ("replace at 800 km"). NULL = no budget.
  retire_at_km          NUMERIC(7,2) CHECK (retire_at_km > 0),
  retired               BOOLEAN     NOT NULL DEFAULT FALSE,
  notes                 TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_gear_user_id ON gear(user_id);
CREATE INDEX idx_gear_default_activity_type
  ON gear(user_id, default_activity_type)
  WHERE default_activity_type IS NOT NULL AND retired = FALSE;

CREATE TRIGGER update_gear_updated_at
  BEFORE UPDATE ON gear
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE gear ENABLE ROW LEVEL SECURITY;

CREATE POLICY gear_select_own ON gear FOR SELECT TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY gear_insert_own ON gear FOR INSERT TO authenticated
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY gear_update_own ON gear FOR UPDATE TO authenticated
  USING  (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'))
  WITH CHECK (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

CREATE POLICY gear_delete_own ON gear FOR DELETE TO authenticated
  USING (user_id::text = (current_setting('request.jwt.claims', true)::json->>'sub'));

-- Explicit, rather than relying on Neon's ALTER DEFAULT PRIVILEGES. Those are
-- part of the Neon project setup and invisible to a self-hoster; without an
-- explicit GRANT their PostgREST would 404 on this table.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE gear TO authenticated;

-- ---------------------------------------------------------------------------
-- physical_activities.gear_id
-- ---------------------------------------------------------------------------

ALTER TABLE physical_activities
  ADD COLUMN gear_id UUID REFERENCES gear(id) ON DELETE SET NULL;

CREATE INDEX idx_physical_activities_gear_id
  ON physical_activities(user_id, gear_id) WHERE gear_id IS NOT NULL;
