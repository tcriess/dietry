-- Add protein_only flag to nutrition_goals.
-- Sub-mode of macro_only: when true, only protein has a hard target. Fat and
-- carbs are still tracked but shown without a compliance target. Only
-- meaningful together with macro_only = TRUE.

BEGIN;

ALTER TABLE nutrition_goals
  ADD COLUMN IF NOT EXISTS protein_only BOOLEAN NOT NULL DEFAULT FALSE;

COMMIT;
