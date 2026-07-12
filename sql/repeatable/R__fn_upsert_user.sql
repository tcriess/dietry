-- Repeatable migration: public.upsert_user
-- Flyway re-applies this whenever the file's checksum changes, so it is the
-- SINGLE source of truth for this function. Edit here; never add another
-- CREATE OR REPLACE of it in a versioned migration (that is how the old
-- search_food_database ended up defined in six different files).

CREATE OR REPLACE FUNCTION public.upsert_user(p_id uuid, p_email text, p_name text DEFAULT NULL::text)
 RETURNS SETOF users
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Case 1: row already exists with the current id → update meta
  IF EXISTS (SELECT 1 FROM users WHERE id = p_id) THEN
    RETURN QUERY
      UPDATE users
      SET
        name           = COALESCE(p_name, name),
        last_login_at  = NOW(),
        updated_at     = NOW()
      WHERE id = p_id
      RETURNING *;
    RETURN;
  END IF;

  -- Case 2: email exists but with a different id
  --         (Neon Auth regenerated the user_id for the same account).
  --         Delete the stale row and fall through to INSERT.
  IF EXISTS (SELECT 1 FROM users WHERE email = p_email) THEN
    DELETE FROM users WHERE email = p_email;
  END IF;

  -- Case 1 & 2 (after cleanup): insert fresh row
  RETURN QUERY
    INSERT INTO users (id, email, name, last_login_at)
    VALUES (p_id, p_email, p_name, NOW())
    RETURNING *;
END;
$function$

;

GRANT ALL ON FUNCTION public.upsert_user(uuid,text,text) TO authenticated;
