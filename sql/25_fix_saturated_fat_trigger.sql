-- sql/25_fix_saturated_fat_trigger.sql
-- The auto-calculation trigger for food_entries was added before saturated_fat
-- existed (sql/15) and never updated to include it. Recreate the function so
-- entries linked to a food_database row also get a scaled saturated_fat value.

CREATE OR REPLACE FUNCTION calculate_nutrition_from_food_database()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.food_id IS NOT NULL
    AND NEW.unit IN ('g', 'ml')
    AND (
      OLD IS NULL OR
      (OLD.calories = NEW.calories AND OLD.protein = NEW.protein)
    ) THEN
    SELECT
      (NEW.amount / 100.0) * f.calories,
      (NEW.amount / 100.0) * f.protein,
      (NEW.amount / 100.0) * f.fat,
      (NEW.amount / 100.0) * f.carbs,
      (NEW.amount / 100.0) * f.fiber,
      (NEW.amount / 100.0) * f.sugar,
      (NEW.amount / 100.0) * f.sodium,
      (NEW.amount / 100.0) * f.saturated_fat
    INTO
      NEW.calories, NEW.protein, NEW.fat, NEW.carbs,
      NEW.fiber, NEW.sugar, NEW.sodium, NEW.saturated_fat
    FROM food_database f
    WHERE f.id = NEW.food_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
