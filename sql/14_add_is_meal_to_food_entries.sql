-- sql/14_add_is_meal_to_food_entries.sql
-- Add is_meal column to reliably distinguish meal entries from food entries.
-- Meals store totals directly; foods store totals (scaled from per-100g).

ALTER TABLE food_entries
  ADD COLUMN is_meal BOOLEAN NOT NULL DEFAULT FALSE;

-- Backfill: existing entries with unit='Portion' are meal entries
UPDATE food_entries SET is_meal = TRUE WHERE unit = 'Portion';
