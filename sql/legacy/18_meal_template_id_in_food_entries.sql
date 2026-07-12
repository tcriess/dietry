-- 18_meal_template_id_in_food_entries.sql — Link food entries to meal templates

-- Add meal_template_id to food_entries (nullable foreign key to meal_templates in cloud edition)
ALTER TABLE food_entries ADD COLUMN meal_template_id UUID REFERENCES meal_templates(id) ON DELETE SET NULL;

-- Index for queries filtering by meal_template_id
CREATE INDEX IF NOT EXISTS idx_food_entries_meal_template_id ON food_entries(meal_template_id) WHERE meal_template_id IS NOT NULL;
