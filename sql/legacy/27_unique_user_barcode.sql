-- 27_unique_user_barcode.sql — one barcode per (user, food) within a user's own foods
--
-- The barcode column had only a regular partial index (sql/00_initial_schema.sql:256)
-- for lookup speed, with no uniqueness anywhere. Three duplication patterns can
-- result:
--   1. a public food + a user's own food with the same barcode — intentional
--      (the user wants their own copy with custom portion sizes); the app's
--      `searchByBarcode` prefers the user's own row.
--   2. two public foods sharing a barcode — usually a data-quality issue in
--      the BLS/FDC import scripts, and occasionally legitimate (GTIN reuse).
--   3. one user with two own foods sharing a barcode — almost always
--      accidental; the app would then non-deterministically pick one of them
--      on a barcode scan.
--
-- This migration blocks (3) without touching (1) or (2). The partial WHERE
-- excludes NULL barcodes (most own foods have none) so we don't accidentally
-- block multiple own foods without barcodes.

CREATE UNIQUE INDEX IF NOT EXISTS idx_food_database_user_barcode_unique
  ON food_database(user_id, barcode)
  WHERE barcode IS NOT NULL;
