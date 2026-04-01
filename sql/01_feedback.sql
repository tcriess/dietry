-- Migration 01: Feedback table for early-access user feedback
-- Run after 00_initial_schema.sql

CREATE TABLE IF NOT EXISTS feedback (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     TEXT        NOT NULL
                DEFAULT (current_setting('request.jwt.claims', true)::json->>'sub'),
  type        TEXT        NOT NULL CHECK (type IN ('bug', 'feature', 'general')),
  rating      SMALLINT    CHECK (rating BETWEEN 1 AND 5),
  message     TEXT        NOT NULL,
  app_version TEXT,
  user_role   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;

-- Users can submit feedback
CREATE POLICY "users insert own feedback"
  ON feedback FOR INSERT
  WITH CHECK (
    user_id = (current_setting('request.jwt.claims', true)::json->>'sub')
  );

-- Users can read their own submissions (nice to have, not strictly required)
CREATE POLICY "users read own feedback"
  ON feedback FOR SELECT
  USING (
    user_id = (current_setting('request.jwt.claims', true)::json->>'sub')
  );
