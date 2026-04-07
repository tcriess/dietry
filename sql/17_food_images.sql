-- 17_food_images.sql — Add image support for food_database

-- Create food_images table
CREATE TABLE food_images (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  food_id     UUID NOT NULL REFERENCES food_database(id) ON DELETE CASCADE,
  image_data  TEXT NOT NULL,        -- base64-encoded JPEG
  content_type TEXT NOT NULL DEFAULT 'image/jpeg',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One image per food
CREATE UNIQUE INDEX food_images_food_id_idx ON food_images(food_id);

-- Add flag to food_database to indicate image presence
ALTER TABLE food_database ADD COLUMN has_image BOOLEAN NOT NULL DEFAULT FALSE;

-- Enable RLS
ALTER TABLE food_images ENABLE ROW LEVEL SECURITY;

-- SELECT: same rules as parent food (approved public OR owner)
CREATE POLICY food_images_select ON food_images FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM food_database fd
    WHERE fd.id = food_images.food_id
      AND (fd.is_approved = TRUE OR fd.user_id = auth.uid())
  )
);

-- INSERT/UPDATE/DELETE: only owner of food record
CREATE POLICY food_images_write ON food_images FOR ALL USING (
  EXISTS (
    SELECT 1 FROM food_database fd
    WHERE fd.id = food_images.food_id AND fd.user_id = auth.uid()
  )
);
