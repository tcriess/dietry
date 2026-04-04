-- Add macro_only flag to nutrition_goals
-- When true, users track macros in grams without a calorie goal
ALTER TABLE nutrition_goals
  ADD COLUMN macro_only BOOLEAN NOT NULL DEFAULT FALSE;
