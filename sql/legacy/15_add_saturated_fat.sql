-- sql/15_add_saturated_fat.sql
-- Add saturated_fat column to track dietary saturated fat content

ALTER TABLE food_database
  ADD COLUMN IF NOT EXISTS saturated_fat NUMERIC(8,2) CHECK (saturated_fat >= 0);

ALTER TABLE food_entries
  ADD COLUMN IF NOT EXISTS saturated_fat NUMERIC(8,2) CHECK (saturated_fat >= 0);
