-- Per-user raw→cooked yield factor for a food.
--
-- Nutrition values are declared for the food as sold (raw/dry), but users weigh
-- what is on the plate. The app ships generic yield factors, but the published
-- ranges are wide (pasta 2.0–2.5, rice 2.0–3.0) mostly because yield depends on
-- how a given person cooks — al dente vs. soft, lid on vs. off. Letting the user
-- measure their own factor once ("250 g dry became 560 g") removes nearly all of
-- the remaining error.
--
-- Lives on user_food_prefs rather than food_database because it is per-user
-- state on a possibly-shared food row, keyed by (user_id, food_id). That also
-- keeps it out of the search RPC signatures.

ALTER TABLE public.user_food_prefs
  ADD COLUMN IF NOT EXISTS cooked_factor numeric(6,3);

-- Guards against a typo turning into a silent 100x logging error. The widest
-- real factors are ~0.3 (spinach) and ~3.0 (rice).
ALTER TABLE public.user_food_prefs
  DROP CONSTRAINT IF EXISTS user_food_prefs_cooked_factor_range;

ALTER TABLE public.user_food_prefs
  ADD CONSTRAINT user_food_prefs_cooked_factor_range
  CHECK (cooked_factor IS NULL OR (cooked_factor >= 0.1 AND cooked_factor <= 10));

-- Explicit grants: production only works without them because Neon has
-- ALTER DEFAULT PRIVILEGES configured at project level, which is invisible here
-- and absent for self-hosters.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_food_prefs TO authenticated;

COMMENT ON COLUMN public.user_food_prefs.cooked_factor IS
  'User-measured cooked weight / raw weight for this food. NULL = use the app''s generic factor.';
