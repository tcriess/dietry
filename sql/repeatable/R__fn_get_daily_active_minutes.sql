-- Repeatable migration: public.get_daily_active_minutes
-- Flyway re-applies this whenever the file's checksum changes, so it is the
-- SINGLE source of truth for this function. Edit here; never add another
-- CREATE OR REPLACE of it in a versioned migration (that is how the old
-- search_food_database ended up defined in six different files).

CREATE OR REPLACE FUNCTION public.get_daily_active_minutes(p_user_id uuid, p_date date)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT COALESCE(SUM(duration_minutes), 0)::INTEGER
  FROM physical_activities
  WHERE user_id = p_user_id
    AND DATE(start_time) = p_date;
$function$

;

GRANT ALL ON FUNCTION public.get_daily_active_minutes(uuid,date) TO authenticated;
