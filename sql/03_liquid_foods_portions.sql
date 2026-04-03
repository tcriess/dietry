-- Migration 03: Store ml amount for liquid food entries
-- Allows liquid food portions to count toward water intake

ALTER TABLE food_entries
  ADD COLUMN amount_ml NUMERIC,
  ADD COLUMN is_liquid_portion_ml BOOLEAN NOT NULL DEFAULT FALSE;

-- Store portion definitions in grams for liquid foods
-- (1g liquid ≈ 1ml, so we can use the same amountG field)
-- The is_liquid_portion_ml flag indicates the amount should be treated as ml
