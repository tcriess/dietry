--
-- V4__view_security_invoker.sql — SECURITY FIX. Read the note before deploying.
--
-- Four of the five views in production are plain (non-security_invoker) views
-- over RLS-protected tables, and all of them are GRANTed to `authenticated`:
--
--     daily_activity_summary    security_invoker NOT set   <- app uses it
--     weekly_activity_summary   security_invoker NOT set   <- app uses it
--     daily_nutrition_summary   security_invoker NOT set   <- app uses it
--     food_entries_detailed     security_invoker NOT set   <- unused by the app
--     user_current_data         security_invoker = true    <- already correct
--
-- A view without security_invoker executes as its OWNER. The owner here is also
-- the table owner, and the tables do not FORCE row level security — so RLS is
-- bypassed entirely. Any authenticated user can read EVERY user's rows through
-- these views simply by not filtering, or by filtering on someone else's user_id:
--
--     SELECT * FROM food_entries_detailed;   -- every user's food log
--
-- Someone already set security_invoker on user_current_data and missed the other
-- four. This migration finishes the job.
--
-- Why this is safe for the three views the app uses: every call site already
-- filters explicitly (`.eq('user_id', userId)` in physical_activity_service.dart
-- and reports_service.dart). Turning on security_invoker restricts the rows to
-- the caller's own — which those queries were already selecting. Same results,
-- no longer optional.
--
-- food_entries_detailed and user_current_data have zero references in the Dart
-- code (CE or cloud). Dropping them would be defensible; this migration only
-- secures them, to keep the change reversible and non-destructive.
--

ALTER VIEW public.daily_activity_summary  SET (security_invoker = true);
ALTER VIEW public.weekly_activity_summary SET (security_invoker = true);
ALTER VIEW public.daily_nutrition_summary SET (security_invoker = true);
ALTER VIEW public.food_entries_detailed   SET (security_invoker = true);
