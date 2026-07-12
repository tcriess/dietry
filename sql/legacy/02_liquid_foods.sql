-- Migration 02: Add liquid food support
-- Allows foods to be marked as liquid and have their ml entries count toward water intake

ALTER TABLE food_database
  ADD COLUMN is_liquid BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE food_entries
  ADD COLUMN is_liquid BOOLEAN NOT NULL DEFAULT FALSE;
