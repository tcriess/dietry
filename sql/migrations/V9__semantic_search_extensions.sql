-- Extensions for semantic (vector) food search — see docs/semantic_food_search_plan.md
--
-- Installs, all in-database with no external backend:
--   * pgrag (rag + rag_bge_small_en_v15) — LOCAL embedding generation. The model
--     bge-small-en-v1.5 (33M params, vector(384)) runs on the Neon compute; no
--     OpenAI/Gemini call. Provides rag_bge_small_en_v15.embedding_for_passage()
--     (corpus) and .embedding_for_query() (search term).
--   * lakebase_vector — the lakebase_ann ANN index type. A drop-in companion to
--     pgvector (same vector type + distance operators); `cascade` pulls pgvector.
--   * lakebase_text — the lakebase_bm25 index type for BM25 full-text ranking.
--     Enables an optional hybrid: fuse BM25 keyword rank with vector rank via
--     RRF for the final ordering (a later step; installed now so we need no
--     second migration to try it).
--
-- This only ENABLES the tooling. The name_embedding column, backfill, ANN index
-- and the semantic_search_food RPC are separate, later steps, gated on the
-- Phase 0 spike proving the English-only model is good enough on our de/en/es
-- corpus (see the plan).
--
-- PREREQUISITE (satisfied on our projects 2026-07-23): "Lakebase Search" must be
-- enabled on the Neon project — including the preload libraries — before the
-- lakebase_* CREATE EXTENSION lines will run. It cannot be turned on from SQL;
-- self-hosters must enable it via the Neon console/API first, or these two lines
-- abort the migration.
--
-- NOTE: pgrag is flagged experimental; Neon recommends a dedicated project. We
-- accept it on the main DB because semantic search is only an augmenting
-- fallback (pg_trgm stays primary) and is trivially disabled by not shipping the
-- RPC.
--
-- ⚠️ CI: .github/workflows/db-migrations.yml builds CE against a stock empty
--    Postgres, which has neither pgrag nor lakebase_vector, so this migration
--    cannot run there. Per the locked decision (CE may depend on Neon), that job
--    must be adjusted/exempted before this merges — otherwise every PR fails.

-- pgrag lives behind the unstable-extensions flag. Session-scoped SET is enough
-- for the CREATE EXTENSION calls in this same migration transaction.
SET neon.allow_unstable_extensions = 'true';

-- In-database embeddings. `cascade` also installs pgvector (the vector type).
CREATE EXTENSION IF NOT EXISTS rag CASCADE;
CREATE EXTENSION IF NOT EXISTS rag_bge_small_en_v15 CASCADE;

-- lakebase_ann (ANN over pgvector) + lakebase_bm25 (BM25 full-text). `cascade`
-- installs pgvector if the lines above somehow did not.
CREATE EXTENSION IF NOT EXISTS lakebase_vector CASCADE;
CREATE EXTENSION IF NOT EXISTS lakebase_text CASCADE;

-- The semantic search RPC will be SECURITY INVOKER (to keep food_database RLS),
-- so the calling `authenticated` role must be able to embed the query. These
-- functions live in a non-public schema, so PostgREST does not expose them
-- directly — they are only reachable through our own public RPC.
GRANT USAGE ON SCHEMA rag_bge_small_en_v15 TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA rag_bge_small_en_v15 TO authenticated;
