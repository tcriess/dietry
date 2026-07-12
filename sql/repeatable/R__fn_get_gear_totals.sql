-- Repeatable migration: public.get_gear_totals
-- Flyway re-applies this whenever the file's checksum changes, so it is the
-- SINGLE source of truth for this function. Edit here; never add another
-- CREATE OR REPLACE of it in a versioned migration.
--
-- A FUNCTION, not a VIEW: functions default to SECURITY INVOKER, so the RLS
-- policies on gear/physical_activities apply to the caller and each user only
-- ever aggregates their own rows. A plain view would run as its owner and
-- bypass RLS — exactly the bug V4__view_security_invoker.sql exists to fix.
--
-- Server-side rather than summed in the client, because the app's local SQLite
-- mirror only backfills ~30 days of activities; a client-side sum would silently
-- under-report a shoe's lifetime mileage.

CREATE OR REPLACE FUNCTION public.get_gear_totals()
RETURNS TABLE (
  gear_id           UUID,
  total_distance_km NUMERIC,
  total_minutes     BIGINT,
  activity_count    BIGINT,
  last_used         TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $function$
  SELECT
    g.id,
    g.initial_distance_km + COALESCE(SUM(a.distance_km), 0),
    COALESCE(SUM(a.duration_minutes), 0)::BIGINT,
    COUNT(a.id),
    MAX(a.start_time)
  FROM gear g
  LEFT JOIN physical_activities a
    ON a.gear_id = g.id AND a.user_id = g.user_id
  GROUP BY g.id, g.initial_distance_km;
$function$;

GRANT ALL ON FUNCTION public.get_gear_totals() TO authenticated;
