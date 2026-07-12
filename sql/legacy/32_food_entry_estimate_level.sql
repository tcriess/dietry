-- 32_food_entry_estimate_level.sql — per-entry nutrition uncertainty
--
-- Revives the original per-entry confidence concept (the orphaned EstimateLevel
-- enum). `none` = weighed/packaged (exact); low/medium/high = increasing
-- estimation. This does NOT change any nutrition value — the app maps the level
-- to a coefficient of variation and shows a daily uncertainty band (variances
-- add). Default 'none' keeps every existing row exact, so it's backward-
-- compatible and the nutrition trigger / summary view are unaffected.

BEGIN;

ALTER TABLE food_entries
  ADD COLUMN IF NOT EXISTS estimate_level TEXT NOT NULL DEFAULT 'none'
    CHECK (estimate_level IN ('none', 'low', 'medium', 'high'));

COMMIT;
