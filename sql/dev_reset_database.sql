-- ============================================================
-- DEV RESET — Community Edition (Migrations 00–16)
-- ============================================================
-- Löscht alle Community-Tabellen, Funktionen und Objekte.
-- Cloud-Edition-Tabellen (Migrations 17–19): zuerst
-- dev_reset_cloud.sql aus dem dietry-cloud-Repository ausführen.
--
-- ⚠️  ACHTUNG: Dieses Skript löscht ALLE Daten unwiderruflich!
-- ⚠️  NUR in der Entwicklungsumgebung verwenden!
-- ⚠️  NIEMALS gegen die Produktionsdatenbank ausführen!
-- ============================================================

\echo '⚠️  WARNING: This will DELETE ALL DATA!'
\echo 'Press Ctrl+C to cancel.'
\prompt 'Type YES to confirm deletion: ' confirmation

-- ============================================================
-- Schritt 1: Tabellen löschen (umgekehrte Abhängigkeitsreihenfolge)
-- ============================================================
\echo 'Dropping tables...'

-- Abhängige Tabellen zuerst
DROP TABLE IF EXISTS water_intake CASCADE;
DROP TABLE IF EXISTS food_entries CASCADE;
DROP TABLE IF EXISTS food_database CASCADE;
DROP TABLE IF EXISTS physical_activities CASCADE;
DROP TABLE IF EXISTS activity_database CASCADE;
DROP TABLE IF EXISTS user_body_measurements CASCADE;
DROP TABLE IF EXISTS user_profiles CASCADE;
DROP TABLE IF EXISTS user_body_data CASCADE;
DROP TABLE IF EXISTS nutrition_goals CASCADE;
-- Basis-Tabelle zuletzt
DROP TABLE IF EXISTS users CASCADE;

\echo '✓ Tables dropped'

-- ============================================================
-- Schritt 2: Funktionen und Views löschen
-- ============================================================
\echo 'Dropping functions and views...'

DROP FUNCTION IF EXISTS update_updated_at_column() CASCADE;
DROP FUNCTION IF EXISTS calculate_nutrition_from_food_database() CASCADE;
DROP FUNCTION IF EXISTS upsert_user(TEXT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS get_daily_active_minutes(UUID, DATE) CASCADE;
DROP FUNCTION IF EXISTS get_weekly_active_minutes(UUID, DATE) CASCADE;

DROP VIEW IF EXISTS food_entries_detailed CASCADE;
DROP VIEW IF EXISTS daily_nutrition_summary CASCADE;
DROP VIEW IF EXISTS daily_activity_summary CASCADE;
DROP VIEW IF EXISTS weekly_activity_summary CASCADE;

\echo '✓ Functions and views dropped'

-- ============================================================
-- Verifikation
-- ============================================================
\echo ''
\echo '=== Verification ==='

\echo 'Remaining tables:'
SELECT schemaname, tablename
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

\echo 'Remaining functions:'
SELECT proname AS function_name
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND prokind = 'f';

\echo 'Remaining views:'
SELECT schemaname, viewname
FROM pg_views
WHERE schemaname = 'public';

\echo ''
\echo '=== Reset complete. All rows above should be empty. ==='
