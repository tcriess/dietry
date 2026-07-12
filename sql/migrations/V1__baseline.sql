--
-- V1__baseline.sql — Dietry Community Edition schema baseline.
--
-- Generated from the live production schema on 2026-07-12, NOT by replaying the
-- old sql/00..34 chain. That chain can no longer rebuild the database:
--   * 16_change_user_id_to_uuid.sql fails ("default for column user_id cannot be
--     cast automatically to type uuid") against the reconstructed 00_initial_schema
--   * 18_meal_template_id_in_food_entries.sql references meal_templates, a
--     CLOUD-ONLY table — the open-source schema could not be built standalone
-- The old files are kept in sql/legacy/ for history and are never executed.
--
-- One deliberate difference from the production snapshot: water_intake is built
-- here in its CORRECTED shape (uuid user_id, FK to users, the standard four RLS
-- policies). Production still carries the old shape; V5__water_intake_align.sql
-- fixes it there and is a no-op here. Verified: a fresh build and a migrated
-- production database converge on an identical schema.
--
-- NOTE: no pg_session_jwt. After V5 nothing in the Community Edition calls
-- auth.uid() / auth.user_id(), so CE has no dependency on Neon-specific
-- extensions and can be self-hosted on stock PostgreSQL. (The Cloud edition
-- still needs it — meal_images uses auth.uid() — so its baseline creates it.)
--
-- Cluster-level prerequisites, NOT created here:
--   * roles: authenticated, anonymous, authenticator
--
-- RPC functions are NOT in this file — they are repeatable migrations under
-- sql/repeatable/. Only the three functions that triggers and indexes depend on
-- (update_updated_at_column, calculate_nutrition_from_food_database, f_unaccent)
-- are created here, because the DDL below needs them to already exist.
--

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

--
-- PostgreSQL database dump
--


-- Dumped from database version 17.10 (986efc8)
-- Dumped by pg_dump version 17.9 (Ubuntu 17.9-0ubuntu0.25.10.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--



--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--



--
-- Name: food_tag; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.food_tag AS (
	id uuid,
	name text,
	slug text
);


--
-- Name: calculate_nutrition_from_food_database(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_nutrition_from_food_database() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: f_unaccent(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.f_unaccent(text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    AS $_$
  SELECT public.unaccent('public.unaccent', $1)
$_$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION update_updated_at_column(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_updated_at_column() IS 'Gemeinsame Trigger-Funktion zum automatischen Update von updated_at bei jeder Änderung';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activity_database; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity_database (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    name text NOT NULL,
    met_value numeric(4,2) NOT NULL,
    category text,
    intensity text,
    description text,
    avg_speed_kmh numeric(5,2),
    is_public boolean DEFAULT false NOT NULL,
    source text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_approved boolean DEFAULT false NOT NULL,
    is_favourite boolean DEFAULT false NOT NULL,
    CONSTRAINT activity_database_avg_speed_kmh_check CHECK ((avg_speed_kmh >= (0)::numeric)),
    CONSTRAINT activity_database_check CHECK ((((is_public = false) AND (user_id IS NOT NULL) AND (is_approved = false)) OR (is_public = true))),
    CONSTRAINT activity_database_intensity_check CHECK ((intensity = ANY (ARRAY['low'::text, 'moderate'::text, 'high'::text, 'very_high'::text]))),
    CONSTRAINT activity_database_met_value_check CHECK (((met_value >= (0)::numeric) AND (met_value <= (20)::numeric))),
    CONSTRAINT activity_database_name_check CHECK ((length(TRIM(BOTH FROM name)) >= 2))
);


--
-- Name: TABLE activity_database; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.activity_database IS 'Datenbank für Aktivitäten mit MET-Werten (public + user-spezifisch)';


--
-- Name: COLUMN activity_database.met_value; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activity_database.met_value IS 'MET-Wert (Metabolic Equivalent): Vielfaches des Ruheenergieverbrauchs';


--
-- Name: COLUMN activity_database.intensity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activity_database.intensity IS 'Intensitätsstufe: low, moderate, high, very_high';


--
-- Name: COLUMN activity_database.avg_speed_kmh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activity_database.avg_speed_kmh IS 'Durchschnittliche Geschwindigkeit in km/h (optional, für Distanz-basierte Aktivitäten)';


--
-- Name: COLUMN activity_database.is_public; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activity_database.is_public IS 'TRUE = für alle sichtbar (user_id muss NULL sein), FALSE = nur für User';


--
-- Name: cheat_days; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cheat_days (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    cheat_date date NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: physical_activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.physical_activities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    activity_type text NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone NOT NULL,
    duration_minutes integer NOT NULL,
    calories_burned numeric(7,2),
    distance_km numeric(6,2),
    steps integer,
    avg_heart_rate numeric(5,2),
    notes text,
    source text DEFAULT 'manual'::text NOT NULL,
    health_connect_record_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    activity_id uuid,
    activity_name text,
    CONSTRAINT physical_activities_activity_type_check CHECK ((activity_type = ANY (ARRAY['walking'::text, 'running'::text, 'cycling'::text, 'swimming'::text, 'weightTraining'::text, 'bodyweight'::text, 'football'::text, 'basketball'::text, 'tennis'::text, 'yoga'::text, 'pilates'::text, 'dancing'::text, 'hiking'::text, 'other'::text]))),
    CONSTRAINT physical_activities_avg_heart_rate_check CHECK (((avg_heart_rate >= (30)::numeric) AND (avg_heart_rate <= (220)::numeric))),
    CONSTRAINT physical_activities_calories_burned_check CHECK (((calories_burned >= (0)::numeric) AND (calories_burned <= (10000)::numeric))),
    CONSTRAINT physical_activities_check CHECK ((end_time > start_time)),
    CONSTRAINT physical_activities_distance_km_check CHECK (((distance_km >= (0)::numeric) AND (distance_km <= (500)::numeric))),
    CONSTRAINT physical_activities_duration_minutes_check CHECK (((duration_minutes > 0) AND (duration_minutes <= 1440))),
    CONSTRAINT physical_activities_source_check CHECK ((source = ANY (ARRAY['manual'::text, 'healthConnect'::text, 'imported'::text]))),
    CONSTRAINT physical_activities_steps_check CHECK (((steps >= 0) AND (steps <= 100000)))
);


--
-- Name: COLUMN physical_activities.activity_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.physical_activities.activity_id IS 'Referenz zu activity_database (optional, für Custom Activities)';


--
-- Name: COLUMN physical_activities.activity_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.physical_activities.activity_name IS 'Name der Aktivität (wird von activity_database kopiert oder manuell gesetzt)';


--
-- Name: daily_activity_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.daily_activity_summary AS
 SELECT user_id,
    date(start_time) AS activity_date,
    count(*) AS activity_count,
    sum(duration_minutes) AS total_minutes,
    sum(calories_burned) AS total_calories,
    sum(distance_km) AS total_distance_km,
    sum(steps) AS total_steps,
    array_agg(DISTINCT activity_type) AS activity_types
   FROM public.physical_activities
  GROUP BY user_id, (date(start_time));


--
-- Name: food_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.food_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    food_id uuid,
    entry_date date DEFAULT CURRENT_DATE NOT NULL,
    meal_type text NOT NULL,
    name text NOT NULL,
    amount numeric(8,2) NOT NULL,
    unit text NOT NULL,
    calories numeric(8,2) NOT NULL,
    protein numeric(8,2) NOT NULL,
    fat numeric(8,2) NOT NULL,
    carbs numeric(8,2) NOT NULL,
    fiber numeric(8,2),
    sugar numeric(8,2),
    sodium numeric(8,2),
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_liquid boolean DEFAULT false NOT NULL,
    amount_ml numeric,
    is_liquid_portion_ml boolean DEFAULT false NOT NULL,
    is_meal boolean DEFAULT false NOT NULL,
    saturated_fat numeric(8,2),
    estimate_level text DEFAULT 'none'::text NOT NULL,
    CONSTRAINT food_entries_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT food_entries_calories_check CHECK ((calories >= (0)::numeric)),
    CONSTRAINT food_entries_carbs_check CHECK ((carbs >= (0)::numeric)),
    CONSTRAINT food_entries_estimate_level_check CHECK ((estimate_level = ANY (ARRAY['none'::text, 'low'::text, 'medium'::text, 'high'::text]))),
    CONSTRAINT food_entries_fat_check CHECK ((fat >= (0)::numeric)),
    CONSTRAINT food_entries_fiber_check CHECK ((fiber >= (0)::numeric)),
    CONSTRAINT food_entries_meal_type_check CHECK ((meal_type = ANY (ARRAY['breakfast'::text, 'lunch'::text, 'dinner'::text, 'snack'::text]))),
    CONSTRAINT food_entries_name_check CHECK ((length(TRIM(BOTH FROM name)) >= 2)),
    CONSTRAINT food_entries_protein_check CHECK ((protein >= (0)::numeric)),
    CONSTRAINT food_entries_saturated_fat_check CHECK ((saturated_fat >= (0)::numeric)),
    CONSTRAINT food_entries_sodium_check CHECK ((sodium >= (0)::numeric)),
    CONSTRAINT food_entries_sugar_check CHECK ((sugar >= (0)::numeric))
);


--
-- Name: daily_nutrition_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.daily_nutrition_summary AS
 SELECT user_id,
    entry_date,
    count(*) AS total_entries,
    sum(calories) AS total_calories,
    sum(protein) AS total_protein,
    sum(fat) AS total_fat,
    sum(carbs) AS total_carbs,
    sum(fiber) AS total_fiber,
    sum(sugar) AS total_sugar,
    sum(sodium) AS total_sodium
   FROM public.food_entries
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.cheat_days
          WHERE ((cheat_days.user_id = food_entries.user_id) AND (cheat_days.cheat_date = food_entries.entry_date)))))
  GROUP BY user_id, entry_date;


--
-- Name: feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feedback (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id text DEFAULT ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text) NOT NULL,
    type text NOT NULL,
    rating smallint,
    message text NOT NULL,
    app_version text,
    user_role text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT feedback_rating_check CHECK (((rating >= 1) AND (rating <= 5))),
    CONSTRAINT feedback_type_check CHECK ((type = ANY (ARRAY['bug'::text, 'feature'::text, 'general'::text])))
);


--
-- Name: food_database; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.food_database (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    name text NOT NULL,
    calories numeric(8,2) NOT NULL,
    protein numeric(8,2) NOT NULL,
    fat numeric(8,2) NOT NULL,
    carbs numeric(8,2) NOT NULL,
    fiber numeric(8,2),
    sugar numeric(8,2),
    sodium numeric(8,2),
    serving_size numeric(8,2),
    serving_unit text,
    category text,
    brand text,
    barcode text,
    is_public boolean DEFAULT false NOT NULL,
    source text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_approved boolean DEFAULT false NOT NULL,
    portions jsonb DEFAULT '[]'::jsonb NOT NULL,
    is_favourite boolean DEFAULT false NOT NULL,
    is_liquid boolean DEFAULT false NOT NULL,
    saturated_fat numeric(8,2),
    has_image boolean DEFAULT false NOT NULL,
    name_unaccent text GENERATED ALWAYS AS (public.f_unaccent(name)) STORED,
    brand_unaccent text GENERATED ALWAYS AS (public.f_unaccent(brand)) STORED,
    category_unaccent text GENERATED ALWAYS AS (public.f_unaccent(category)) STORED,
    estimate_level text DEFAULT 'none'::text NOT NULL,
    CONSTRAINT food_database_calories_check CHECK ((calories >= (0)::numeric)),
    CONSTRAINT food_database_carbs_check CHECK ((carbs >= (0)::numeric)),
    CONSTRAINT food_database_check CHECK ((((is_public = false) AND (user_id IS NOT NULL) AND (is_approved = false)) OR (is_public = true))),
    CONSTRAINT food_database_estimate_level_check CHECK ((estimate_level = ANY (ARRAY['none'::text, 'low'::text, 'medium'::text, 'high'::text]))),
    CONSTRAINT food_database_fat_check CHECK ((fat >= (0)::numeric)),
    CONSTRAINT food_database_fiber_check CHECK ((fiber >= (0)::numeric)),
    CONSTRAINT food_database_name_check CHECK ((length(TRIM(BOTH FROM name)) >= 2)),
    CONSTRAINT food_database_protein_check CHECK ((protein >= (0)::numeric)),
    CONSTRAINT food_database_saturated_fat_check CHECK ((saturated_fat >= (0)::numeric)),
    CONSTRAINT food_database_sodium_check CHECK ((sodium >= (0)::numeric)),
    CONSTRAINT food_database_sugar_check CHECK ((sugar >= (0)::numeric))
);


--
-- Name: food_entries_detailed; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.food_entries_detailed AS
 SELECT e.id,
    e.user_id,
    e.entry_date,
    e.meal_type,
    e.name,
    e.amount,
    e.unit,
    e.calories,
    e.protein,
    e.fat,
    e.carbs,
    e.fiber,
    e.sugar,
    e.sodium,
    e.notes,
    e.created_at,
    e.updated_at,
    f.id AS food_db_id,
    f.name AS food_db_name,
    f.category,
    f.brand,
    f.is_public AS is_public_food
   FROM (public.food_entries e
     LEFT JOIN public.food_database f ON ((e.food_id = f.id)));


--
-- Name: food_images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.food_images (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    food_id uuid NOT NULL,
    image_data text NOT NULL,
    content_type text DEFAULT 'image/jpeg'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: nutrition_goals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nutrition_goals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    calories numeric(8,2) NOT NULL,
    protein numeric(8,2) NOT NULL,
    fat numeric(8,2) NOT NULL,
    carbs numeric(8,2) NOT NULL,
    valid_from date DEFAULT CURRENT_DATE NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    tracking_method text,
    water_goal_ml integer,
    macro_only boolean DEFAULT false NOT NULL,
    protein_only boolean DEFAULT false NOT NULL,
    CONSTRAINT nutrition_goals_calories_check CHECK ((calories > (0)::numeric)),
    CONSTRAINT nutrition_goals_carbs_check CHECK ((carbs >= (0)::numeric)),
    CONSTRAINT nutrition_goals_fat_check CHECK ((fat >= (0)::numeric)),
    CONSTRAINT nutrition_goals_protein_check CHECK ((protein >= (0)::numeric))
);


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    created_by uuid,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: user_body_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_body_data (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    weight numeric(5,1) NOT NULL,
    height numeric(5,1) NOT NULL,
    age integer NOT NULL,
    gender text NOT NULL,
    activity_level text NOT NULL,
    weight_goal text NOT NULL,
    bmr numeric(7,2),
    tdee numeric(7,2),
    target_calories numeric(7,2),
    measured_at date DEFAULT CURRENT_DATE NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT user_body_data_activity_level_check CHECK ((activity_level = ANY (ARRAY['sedentary'::text, 'light'::text, 'moderate'::text, 'active'::text, 'veryActive'::text]))),
    CONSTRAINT user_body_data_age_check CHECK (((age >= 15) AND (age <= 100))),
    CONSTRAINT user_body_data_gender_check CHECK ((gender = ANY (ARRAY['male'::text, 'female'::text]))),
    CONSTRAINT user_body_data_height_check CHECK (((height >= (100)::numeric) AND (height <= (250)::numeric))),
    CONSTRAINT user_body_data_weight_check CHECK (((weight >= (30)::numeric) AND (weight <= (300)::numeric))),
    CONSTRAINT user_body_data_weight_goal_check CHECK ((weight_goal = ANY (ARRAY['lose'::text, 'maintain'::text, 'gain'::text])))
);


--
-- Name: user_body_measurements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_body_measurements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    weight numeric(5,1) NOT NULL,
    body_fat_percentage numeric(4,1),
    muscle_mass_kg numeric(5,1),
    waist_cm numeric(5,1),
    measured_at date DEFAULT CURRENT_DATE NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT user_body_measurements_body_fat_percentage_check CHECK (((body_fat_percentage >= (0)::numeric) AND (body_fat_percentage <= (50)::numeric))),
    CONSTRAINT user_body_measurements_weight_check CHECK (((weight >= (30)::numeric) AND (weight <= (300)::numeric)))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    email text NOT NULL,
    name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_login_at timestamp with time zone,
    birthdate date,
    height numeric(5,1),
    gender text,
    activity_level text,
    weight_goal text,
    CONSTRAINT users_activity_level_check CHECK ((activity_level = ANY (ARRAY['sedentary'::text, 'light'::text, 'moderate'::text, 'active'::text, 'veryActive'::text]))),
    CONSTRAINT users_gender_check CHECK ((gender = ANY (ARRAY['male'::text, 'female'::text]))),
    CONSTRAINT users_height_check CHECK (((height >= (100)::numeric) AND (height <= (250)::numeric))),
    CONSTRAINT users_weight_goal_check CHECK ((weight_goal = ANY (ARRAY['lose'::text, 'maintain'::text, 'gain'::text])))
);


--
-- Name: TABLE users; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.users IS 'Zentrale User-Tabelle für OAuth-authentifizierte Nutzer';


--
-- Name: COLUMN users.id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.id IS 'UUID von Neon Auth JWT (sub-Claim)';


--
-- Name: COLUMN users.email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.email IS 'Email-Adresse vom OAuth-Provider';


--
-- Name: COLUMN users.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.name IS 'Display-Name des Users';


--
-- Name: COLUMN users.last_login_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.last_login_at IS 'Letzter Login-Zeitpunkt';


--
-- Name: COLUMN users.birthdate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.birthdate IS 'Geburtsdatum (statisch, ändert sich nie)';


--
-- Name: COLUMN users.height; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.height IS 'Körpergröße in cm (statisch, ändert sich nach Erwachsenenalter kaum)';


--
-- Name: COLUMN users.gender; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.gender IS 'Geschlecht (statisch)';


--
-- Name: COLUMN users.activity_level; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.activity_level IS 'Durchschnittliches Aktivitätslevel (änderbar aber selten)';


--
-- Name: COLUMN users.weight_goal; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.weight_goal IS 'Gewichtsziel (änderbar aber selten)';


--
-- Name: user_current_data; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.user_current_data WITH (security_invoker='true') AS
 SELECT u.id AS user_id,
    u.email,
    u.name,
    u.birthdate,
    u.height,
    u.gender,
    u.activity_level,
    u.weight_goal,
    (EXTRACT(year FROM age((CURRENT_DATE)::timestamp with time zone, (u.birthdate)::timestamp with time zone)))::integer AS age,
    m.id AS measurement_id,
    m.weight,
    m.body_fat_percentage,
    m.muscle_mass_kg,
    m.waist_cm,
    m.measured_at,
    m.notes
   FROM (public.users u
     LEFT JOIN LATERAL ( SELECT user_body_measurements.id,
            user_body_measurements.user_id,
            user_body_measurements.weight,
            user_body_measurements.body_fat_percentage,
            user_body_measurements.muscle_mass_kg,
            user_body_measurements.waist_cm,
            user_body_measurements.measured_at,
            user_body_measurements.notes,
            user_body_measurements.created_at,
            user_body_measurements.updated_at
           FROM public.user_body_measurements
          WHERE (user_body_measurements.user_id = u.id)
          ORDER BY user_body_measurements.measured_at DESC
         LIMIT 1) m ON (true));


--
-- Name: VIEW user_current_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.user_current_data IS 'Kombiniert statische Profildaten mit aktuellsten Messdaten';


--
-- Name: user_food_prefs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_food_prefs (
    user_id uuid NOT NULL,
    food_id uuid NOT NULL,
    last_amount numeric(10,2) NOT NULL,
    last_unit text NOT NULL,
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: user_food_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_food_tags (
    user_id uuid NOT NULL,
    food_id uuid NOT NULL,
    tag_id uuid NOT NULL
);


--
-- Name: water_intake; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.water_intake (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    date date NOT NULL,
    amount_ml integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: weekly_activity_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.weekly_activity_summary AS
 SELECT user_id,
    date_trunc('week'::text, start_time) AS week_start,
    count(*) AS activity_count,
    sum(duration_minutes) AS total_minutes,
    sum(calories_burned) AS total_calories,
    sum(distance_km) AS total_distance_km
   FROM public.physical_activities
  GROUP BY user_id, (date_trunc('week'::text, start_time));


--
-- Name: activity_database activity_database_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_database
    ADD CONSTRAINT activity_database_pkey PRIMARY KEY (id);


--
-- Name: cheat_days cheat_days_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cheat_days
    ADD CONSTRAINT cheat_days_pkey PRIMARY KEY (id);


--
-- Name: cheat_days cheat_days_user_id_cheat_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cheat_days
    ADD CONSTRAINT cheat_days_user_id_cheat_date_key UNIQUE (user_id, cheat_date);


--
-- Name: feedback feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_pkey PRIMARY KEY (id);


--
-- Name: food_database food_database_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_database
    ADD CONSTRAINT food_database_pkey PRIMARY KEY (id);


--
-- Name: food_entries food_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_entries
    ADD CONSTRAINT food_entries_pkey PRIMARY KEY (id);


--
-- Name: food_images food_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_images
    ADD CONSTRAINT food_images_pkey PRIMARY KEY (id);


--
-- Name: nutrition_goals nutrition_goals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nutrition_goals
    ADD CONSTRAINT nutrition_goals_pkey PRIMARY KEY (id);


--
-- Name: nutrition_goals nutrition_goals_user_id_valid_from_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nutrition_goals
    ADD CONSTRAINT nutrition_goals_user_id_valid_from_key UNIQUE (user_id, valid_from);


--
-- Name: physical_activities physical_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.physical_activities
    ADD CONSTRAINT physical_activities_pkey PRIMARY KEY (id);


--
-- Name: physical_activities physical_activities_user_id_health_connect_record_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.physical_activities
    ADD CONSTRAINT physical_activities_user_id_health_connect_record_id_key UNIQUE (user_id, health_connect_record_id);


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: tags tags_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_slug_key UNIQUE (slug);


--
-- Name: user_body_data user_body_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_body_data
    ADD CONSTRAINT user_body_data_pkey PRIMARY KEY (id);


--
-- Name: user_body_measurements user_body_measurements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_body_measurements
    ADD CONSTRAINT user_body_measurements_pkey PRIMARY KEY (id);


--
-- Name: user_body_measurements user_body_measurements_user_id_measured_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_body_measurements
    ADD CONSTRAINT user_body_measurements_user_id_measured_at_key UNIQUE (user_id, measured_at);


--
-- Name: user_food_prefs user_food_prefs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_food_prefs
    ADD CONSTRAINT user_food_prefs_pkey PRIMARY KEY (user_id, food_id);


--
-- Name: user_food_tags user_food_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_food_tags
    ADD CONSTRAINT user_food_tags_pkey PRIMARY KEY (user_id, food_id, tag_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: water_intake water_intake_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.water_intake
    ADD CONSTRAINT water_intake_pkey PRIMARY KEY (id);


--
-- Name: water_intake water_intake_user_id_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.water_intake
    ADD CONSTRAINT water_intake_user_id_date_key UNIQUE (user_id, date);


--
-- Name: food_images_food_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX food_images_food_id_idx ON public.food_images USING btree (food_id);


--
-- Name: idx_activity_database_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_database_category ON public.activity_database USING btree (category) WHERE (category IS NOT NULL);


--
-- Name: idx_activity_database_is_public; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_database_is_public ON public.activity_database USING btree (is_public) WHERE (is_public = true);


--
-- Name: idx_activity_database_met_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_database_met_value ON public.activity_database USING btree (met_value);


--
-- Name: idx_activity_database_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_database_name ON public.activity_database USING btree (lower(name));


--
-- Name: idx_activity_database_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_database_user_id ON public.activity_database USING btree (user_id) WHERE (user_id IS NOT NULL);


--
-- Name: idx_food_database_barcode; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_database_barcode ON public.food_database USING btree (barcode) WHERE (barcode IS NOT NULL);


--
-- Name: idx_food_database_brand_ua_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_database_brand_ua_trgm ON public.food_database USING gin (brand_unaccent public.gin_trgm_ops);


--
-- Name: idx_food_database_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_database_category ON public.food_database USING btree (category) WHERE (category IS NOT NULL);


--
-- Name: idx_food_database_category_ua_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_database_category_ua_trgm ON public.food_database USING gin (category_unaccent public.gin_trgm_ops);


--
-- Name: idx_food_database_is_public; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_database_is_public ON public.food_database USING btree (is_public) WHERE (is_public = true);


--
-- Name: idx_food_database_name_ua_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_database_name_ua_trgm ON public.food_database USING gin (name_unaccent public.gin_trgm_ops);


--
-- Name: idx_food_database_portions; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_database_portions ON public.food_database USING gin (portions) WHERE (portions <> '[]'::jsonb);


--
-- Name: idx_food_database_public_approved; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_database_public_approved ON public.food_database USING btree (created_at DESC) WHERE ((is_public = true) AND (is_approved = true));


--
-- Name: idx_food_database_user_barcode_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_food_database_user_barcode_unique ON public.food_database USING btree (user_id, barcode) WHERE (barcode IS NOT NULL);


--
-- Name: idx_food_database_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_database_user_id ON public.food_database USING btree (user_id) WHERE (user_id IS NOT NULL);


--
-- Name: idx_food_entries_entry_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_entries_entry_date ON public.food_entries USING btree (entry_date);


--
-- Name: idx_food_entries_food_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_entries_food_id ON public.food_entries USING btree (food_id) WHERE (food_id IS NOT NULL);


--
-- Name: idx_food_entries_meal_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_entries_meal_type ON public.food_entries USING btree (meal_type);


--
-- Name: idx_food_entries_user_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_entries_user_date ON public.food_entries USING btree (user_id, entry_date);


--
-- Name: idx_food_entries_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_food_entries_user_id ON public.food_entries USING btree (user_id);


--
-- Name: idx_nutrition_goals_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_nutrition_goals_user_id ON public.nutrition_goals USING btree (user_id);


--
-- Name: idx_nutrition_goals_valid_from; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_nutrition_goals_valid_from ON public.nutrition_goals USING btree (valid_from);


--
-- Name: idx_physical_activities_activity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_physical_activities_activity_id ON public.physical_activities USING btree (activity_id) WHERE (activity_id IS NOT NULL);


--
-- Name: idx_physical_activities_activity_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_physical_activities_activity_type ON public.physical_activities USING btree (user_id, activity_type);


--
-- Name: idx_physical_activities_health_connect; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_physical_activities_health_connect ON public.physical_activities USING btree (user_id, health_connect_record_id) WHERE (health_connect_record_id IS NOT NULL);


--
-- Name: idx_physical_activities_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_physical_activities_source ON public.physical_activities USING btree (user_id, source);


--
-- Name: idx_physical_activities_start_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_physical_activities_start_time ON public.physical_activities USING btree (user_id, start_time DESC);


--
-- Name: idx_physical_activities_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_physical_activities_user_id ON public.physical_activities USING btree (user_id);


--
-- Name: idx_tags_name_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tags_name_trgm ON public.tags USING gin (name public.gin_trgm_ops);


--
-- Name: idx_tags_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tags_slug ON public.tags USING btree (slug);


--
-- Name: idx_user_body_data_measured_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_body_data_measured_at ON public.user_body_data USING btree (user_id, measured_at DESC);


--
-- Name: idx_user_body_data_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_body_data_user_id ON public.user_body_data USING btree (user_id);


--
-- Name: idx_user_body_measurements_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_body_measurements_date ON public.user_body_measurements USING btree (user_id, measured_at DESC);


--
-- Name: idx_user_body_measurements_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_body_measurements_user_id ON public.user_body_measurements USING btree (user_id);


--
-- Name: idx_user_food_tags_tag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_food_tags_tag ON public.user_food_tags USING btree (tag_id);


--
-- Name: idx_user_food_tags_user_food; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_food_tags_user_food ON public.user_food_tags USING btree (user_id, food_id);


--
-- Name: idx_users_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_created_at ON public.users USING btree (created_at DESC);


--
-- Name: idx_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_email ON public.users USING btree (email);


--
-- Name: food_entries calculate_nutrition_before_insert_or_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER calculate_nutrition_before_insert_or_update BEFORE INSERT OR UPDATE ON public.food_entries FOR EACH ROW EXECUTE FUNCTION public.calculate_nutrition_from_food_database();


--
-- Name: physical_activities physical_activities_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER physical_activities_updated_at BEFORE UPDATE ON public.physical_activities FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: activity_database update_activity_database_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_activity_database_updated_at BEFORE UPDATE ON public.activity_database FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: food_database update_food_database_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_food_database_updated_at BEFORE UPDATE ON public.food_database FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: food_entries update_food_entries_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_food_entries_updated_at BEFORE UPDATE ON public.food_entries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: nutrition_goals update_nutrition_goals_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_nutrition_goals_updated_at BEFORE UPDATE ON public.nutrition_goals FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: user_body_data user_body_data_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER user_body_data_updated_at BEFORE UPDATE ON public.user_body_data FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: user_body_measurements user_body_measurements_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER user_body_measurements_updated_at BEFORE UPDATE ON public.user_body_measurements FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: users users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: activity_database activity_database_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_database
    ADD CONSTRAINT activity_database_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: cheat_days cheat_days_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cheat_days
    ADD CONSTRAINT cheat_days_user_id_fk FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: food_database food_database_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_database
    ADD CONSTRAINT food_database_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: food_entries food_entries_food_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_entries
    ADD CONSTRAINT food_entries_food_id_fkey FOREIGN KEY (food_id) REFERENCES public.food_database(id) ON DELETE SET NULL;


--
-- Name: food_entries food_entries_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_entries
    ADD CONSTRAINT food_entries_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: food_images food_images_food_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.food_images
    ADD CONSTRAINT food_images_food_id_fkey FOREIGN KEY (food_id) REFERENCES public.food_database(id) ON DELETE CASCADE;


--
-- Name: nutrition_goals nutrition_goals_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nutrition_goals
    ADD CONSTRAINT nutrition_goals_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: physical_activities physical_activities_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.physical_activities
    ADD CONSTRAINT physical_activities_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activity_database(id) ON DELETE SET NULL;


--
-- Name: physical_activities physical_activities_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.physical_activities
    ADD CONSTRAINT physical_activities_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: tags tags_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: user_body_data user_body_data_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_body_data
    ADD CONSTRAINT user_body_data_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_body_measurements user_body_measurements_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_body_measurements
    ADD CONSTRAINT user_body_measurements_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_food_prefs user_food_prefs_food_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_food_prefs
    ADD CONSTRAINT user_food_prefs_food_id_fkey FOREIGN KEY (food_id) REFERENCES public.food_database(id) ON DELETE CASCADE;


--
-- Name: user_food_prefs user_food_prefs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_food_prefs
    ADD CONSTRAINT user_food_prefs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_food_tags user_food_tags_food_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_food_tags
    ADD CONSTRAINT user_food_tags_food_id_fkey FOREIGN KEY (food_id) REFERENCES public.food_database(id) ON DELETE CASCADE;


--
-- Name: user_food_tags user_food_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_food_tags
    ADD CONSTRAINT user_food_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;


--
-- Name: user_food_tags user_food_tags_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_food_tags
    ADD CONSTRAINT user_food_tags_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: water_intake water_intake_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.water_intake
    ADD CONSTRAINT water_intake_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: activity_database; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.activity_database ENABLE ROW LEVEL SECURITY;

--
-- Name: activity_database activity_database_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY activity_database_delete_own ON public.activity_database FOR DELETE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: activity_database activity_database_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY activity_database_insert_own ON public.activity_database FOR INSERT TO authenticated WITH CHECK ((((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)) AND (is_approved = false)));


--
-- Name: activity_database activity_database_select_own_and_public; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY activity_database_select_own_and_public ON public.activity_database FOR SELECT TO authenticated USING ((((is_public = true) AND (is_approved = true)) OR ((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))));


--
-- Name: activity_database activity_database_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY activity_database_update_own ON public.activity_database FOR UPDATE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))) WITH CHECK ((((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)) AND (is_approved = false)));


--
-- Name: cheat_days; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cheat_days ENABLE ROW LEVEL SECURITY;

--
-- Name: cheat_days cheat_days_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cheat_days_delete_own ON public.cheat_days FOR DELETE USING ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: cheat_days cheat_days_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cheat_days_insert_own ON public.cheat_days FOR INSERT WITH CHECK ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: cheat_days cheat_days_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cheat_days_select_own ON public.cheat_days FOR SELECT USING ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: cheat_days cheat_days_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cheat_days_update_own ON public.cheat_days FOR UPDATE USING ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid)) WITH CHECK ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: feedback; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

--
-- Name: food_database; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.food_database ENABLE ROW LEVEL SECURITY;

--
-- Name: food_database food_database_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY food_database_delete_own ON public.food_database FOR DELETE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: food_database food_database_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY food_database_insert_own ON public.food_database FOR INSERT TO authenticated WITH CHECK ((((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)) AND (is_approved = false)));


--
-- Name: food_database food_database_select_own_and_public; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY food_database_select_own_and_public ON public.food_database FOR SELECT TO authenticated USING ((((is_public = true) AND (is_approved = true)) OR ((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))));


--
-- Name: food_database food_database_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY food_database_update_own ON public.food_database FOR UPDATE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))) WITH CHECK ((((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)) AND (is_approved = false)));


--
-- Name: food_entries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.food_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: food_entries food_entries_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY food_entries_delete_own ON public.food_entries FOR DELETE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: food_entries food_entries_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY food_entries_insert_own ON public.food_entries FOR INSERT TO authenticated WITH CHECK (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: food_entries food_entries_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY food_entries_select_own ON public.food_entries FOR SELECT TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: food_entries food_entries_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY food_entries_update_own ON public.food_entries FOR UPDATE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))) WITH CHECK (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: food_images; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.food_images ENABLE ROW LEVEL SECURITY;

--
-- Name: food_images food_images_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY food_images_select ON public.food_images FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.food_database fd
  WHERE ((fd.id = food_images.food_id) AND ((fd.is_approved = true) OR ((fd.user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)))))));


--
-- Name: food_images food_images_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY food_images_write ON public.food_images USING ((EXISTS ( SELECT 1
   FROM public.food_database fd
  WHERE ((fd.id = food_images.food_id) AND ((fd.user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))))));


--
-- Name: nutrition_goals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.nutrition_goals ENABLE ROW LEVEL SECURITY;

--
-- Name: nutrition_goals nutrition_goals_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nutrition_goals_delete_own ON public.nutrition_goals FOR DELETE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: nutrition_goals nutrition_goals_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nutrition_goals_insert_own ON public.nutrition_goals FOR INSERT TO authenticated WITH CHECK (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: nutrition_goals nutrition_goals_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nutrition_goals_select_own ON public.nutrition_goals FOR SELECT TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: nutrition_goals nutrition_goals_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY nutrition_goals_update_own ON public.nutrition_goals FOR UPDATE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))) WITH CHECK (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: physical_activities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.physical_activities ENABLE ROW LEVEL SECURITY;

--
-- Name: physical_activities physical_activities_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY physical_activities_delete_own ON public.physical_activities FOR DELETE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: physical_activities physical_activities_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY physical_activities_insert_own ON public.physical_activities FOR INSERT TO authenticated WITH CHECK (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: physical_activities physical_activities_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY physical_activities_select_own ON public.physical_activities FOR SELECT TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: physical_activities physical_activities_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY physical_activities_update_own ON public.physical_activities FOR UPDATE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))) WITH CHECK (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: tags; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;

--
-- Name: tags tags_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tags_delete ON public.tags FOR DELETE USING (((created_by)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: tags tags_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tags_insert ON public.tags FOR INSERT WITH CHECK (((created_by)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: tags tags_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tags_select ON public.tags FOR SELECT USING (true);


--
-- Name: tags tags_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tags_update ON public.tags FOR UPDATE USING (((created_by)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: user_food_tags uft_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY uft_delete ON public.user_food_tags FOR DELETE USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: user_food_tags uft_modify; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY uft_modify ON public.user_food_tags FOR INSERT WITH CHECK (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: user_food_tags uft_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY uft_select ON public.user_food_tags FOR SELECT USING ((((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)) OR (EXISTS ( SELECT 1
   FROM public.food_database fd
  WHERE ((fd.id = user_food_tags.food_id) AND ((fd.user_id)::text = (fd.user_id)::text))))));


--
-- Name: user_body_data; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_body_data ENABLE ROW LEVEL SECURITY;

--
-- Name: user_body_data user_body_data_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_body_data_delete_own ON public.user_body_data FOR DELETE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: user_body_data user_body_data_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_body_data_insert_own ON public.user_body_data FOR INSERT TO authenticated WITH CHECK (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: user_body_data user_body_data_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_body_data_select_own ON public.user_body_data FOR SELECT TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: user_body_data user_body_data_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_body_data_update_own ON public.user_body_data FOR UPDATE TO authenticated USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))) WITH CHECK (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: user_body_measurements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_body_measurements ENABLE ROW LEVEL SECURITY;

--
-- Name: user_body_measurements user_body_measurements_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_body_measurements_delete_own ON public.user_body_measurements FOR DELETE USING ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: user_body_measurements user_body_measurements_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_body_measurements_insert_own ON public.user_body_measurements FOR INSERT WITH CHECK ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: user_body_measurements user_body_measurements_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_body_measurements_select_own ON public.user_body_measurements FOR SELECT USING ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: user_body_measurements user_body_measurements_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_body_measurements_update_own ON public.user_body_measurements FOR UPDATE USING ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: user_food_prefs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_food_prefs ENABLE ROW LEVEL SECURITY;

--
-- Name: user_food_prefs user_food_prefs_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_food_prefs_delete ON public.user_food_prefs FOR DELETE USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: user_food_prefs user_food_prefs_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_food_prefs_insert ON public.user_food_prefs FOR INSERT WITH CHECK (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: user_food_prefs user_food_prefs_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_food_prefs_select ON public.user_food_prefs FOR SELECT USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: user_food_prefs user_food_prefs_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_food_prefs_update ON public.user_food_prefs FOR UPDATE USING (((user_id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: user_food_tags; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_food_tags ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: feedback users insert own feedback; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "users insert own feedback" ON public.feedback FOR INSERT WITH CHECK ((user_id = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: feedback users read own feedback; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "users read own feedback" ON public.feedback FOR SELECT USING ((user_id = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: users users_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_delete_own ON public.users FOR DELETE TO authenticated USING (((id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: users users_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_insert_own ON public.users FOR INSERT TO authenticated WITH CHECK (((id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: users users_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_select_own ON public.users FOR SELECT TO authenticated USING (((id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: users users_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_update_own ON public.users FOR UPDATE TO authenticated USING (((id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))) WITH CHECK (((id)::text = ((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text)));


--
-- Name: water_intake; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.water_intake ENABLE ROW LEVEL SECURITY;

--
-- Name: water_intake water_intake_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY water_intake_delete_own ON public.water_intake FOR DELETE USING ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: water_intake water_intake_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY water_intake_insert_own ON public.water_intake FOR INSERT WITH CHECK ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: water_intake water_intake_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY water_intake_select_own ON public.water_intake FOR SELECT USING ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: water_intake water_intake_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY water_intake_update_own ON public.water_intake FOR UPDATE USING ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid)) WITH CHECK ((user_id = (((current_setting('request.jwt.claims'::text, true))::json ->> 'sub'::text))::uuid));


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO authenticated;


--
-- Name: FUNCTION calculate_nutrition_from_food_database(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.calculate_nutrition_from_food_database() TO authenticated;


--
-- Name: FUNCTION f_unaccent(text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.f_unaccent(text) TO authenticated;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.update_updated_at_column() TO authenticated;


--
-- Name: TABLE activity_database; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.activity_database TO authenticated;


--
-- Name: TABLE cheat_days; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.cheat_days TO authenticated;


--
-- Name: TABLE physical_activities; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.physical_activities TO authenticated;


--
-- Name: TABLE daily_activity_summary; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.daily_activity_summary TO authenticated;


--
-- Name: TABLE food_entries; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.food_entries TO authenticated;


--
-- Name: TABLE daily_nutrition_summary; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.daily_nutrition_summary TO authenticated;


--
-- Name: TABLE feedback; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.feedback TO authenticated;


--
-- Name: TABLE food_database; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.food_database TO authenticated;


--
-- Name: TABLE food_entries_detailed; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.food_entries_detailed TO authenticated;


--
-- Name: TABLE food_images; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.food_images TO authenticated;


--
-- Name: TABLE nutrition_goals; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.nutrition_goals TO authenticated;


--
-- Name: TABLE tags; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.tags TO authenticated;


--
-- Name: TABLE user_body_data; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_body_data TO authenticated;


--
-- Name: TABLE user_body_measurements; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_body_measurements TO authenticated;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.users TO authenticated;


--
-- Name: TABLE user_current_data; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_current_data TO authenticated;


--
-- Name: TABLE user_food_prefs; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_food_prefs TO authenticated;


--
-- Name: TABLE user_food_tags; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_food_tags TO authenticated;


--
-- Name: TABLE water_intake; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.water_intake TO authenticated;


--
-- Name: TABLE weekly_activity_summary; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.weekly_activity_summary TO authenticated;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE dietry IN SCHEMA public GRANT USAGE ON SEQUENCES TO authenticated;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE dietry IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE dietry IN SCHEMA public GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO authenticated;


--
-- PostgreSQL database dump complete
--


