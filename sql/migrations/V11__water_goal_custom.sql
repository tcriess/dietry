-- Marks a water goal the user set by hand, so the automatic recalculation on
-- each new body measurement keeps it instead of overwriting it.
-- Existing rows default to false: their water goal follows the formula again.

ALTER TABLE public.nutrition_goals
  ADD COLUMN IF NOT EXISTS water_goal_custom boolean DEFAULT false NOT NULL;
