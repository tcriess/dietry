#!/usr/bin/env bash
#
# flyway.sh — run Flyway against a Dietry database, via Docker (no JVM needed).
#
#   export DATABASE_URL='postgresql://user:pass@host/db?sslmode=require'
#
# Two one-off lifecycle commands, then everyday use:
#
#   ./flyway.sh bootstrap   # FIRST run against a database with NO Dietry schema
#                           #   -> baselines this stream at v0, then applies V1..Vn
#   ./flyway.sh adopt       # FIRST run against a database that ALREADY has the
#                           #   V1 objects (production, or a branch of it)
#                           #   -> stamps V1 as applied WITHOUT running it, then Vn
#
#   ./flyway.sh info        # what is applied, what is pending
#   ./flyway.sh migrate     # everyday: apply pending migrations
#   ./flyway.sh validate    # checksum check, no writes
#
# Why two commands instead of one: only a human knows whether a given database
# already contains the baseline objects. Guessing wrong is silent data loss in
# one direction (stamping V1 on an empty DB skips creating every table), so the
# choice is made explicit. Both are safe to get wrong loudly: bootstrap against a
# populated DB fails on "table already exists"; adopt against an empty one fails
# on the first migration that references a missing table.
#
# NOTE for the Cloud edition: a Cloud database holds BOTH schemas and the CE
# stream must be migrated first (all cloud FKs point into CE tables). See the
# runbook in docs/database/MIGRATIONS.md.
#
set -euo pipefail

# Pinned exactly, not to a floating `12-alpine`: this tool rewrites the production
# schema, so CI and every developer must run the identical binary. Bump
# deliberately (and re-run the verification in docs/database/MIGRATIONS.md).
# Override ad hoc with FLYWAY_IMAGE=... if you need to test a new version.
FLYWAY_IMAGE="${FLYWAY_IMAGE:-flyway/flyway:12.11.0-alpine}"

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "error: DATABASE_URL is not set." >&2
  echo "  export DATABASE_URL='postgresql://user:pass@host/db?sslmode=require'" >&2
  exit 1
fi

# Split a libpq URL into the JDBC URL + user + password Flyway wants. Credentials
# are passed separately, never inside the JDBC URL, so they stay out of logs.
proto_stripped="${DATABASE_URL#*://}"
creds="${proto_stripped%%@*}"
hostpart="${proto_stripped#*@}"
DB_USER="${creds%%:*}"
DB_PASS="${creds#*:}"

# Neon requires sslmode=require. channel_binding is a libpq option the JDBC
# driver does not understand, so it is dropped along with the rest of the query.
JDBC_URL="jdbc:postgresql://${hostpart%%\?*}?sslmode=require"

flyway() {
  docker run --rm \
    -v "$(pwd)/sql:/flyway/sql" \
    -v "$(pwd)/flyway.conf:/flyway/conf/flyway.conf:ro" \
    -e FLYWAY_URL="$JDBC_URL" \
    -e FLYWAY_USER="$DB_USER" \
    -e FLYWAY_PASSWORD="$DB_PASS" \
    "$FLYWAY_IMAGE" \
    -locations=filesystem:/flyway/sql/migrations,filesystem:/flyway/sql/repeatable,filesystem:/flyway/sql/callbacks \
    "$@"
}

case "${1:-}" in
  bootstrap)
    # The schema may already be non-empty even for a "new" database: in the Cloud
    # edition the CE stream has already created its tables by the time the cloud
    # stream first runs. Baselining at v0 gives this stream its history table
    # without marking anything as applied, so V1 really runs.
    echo "==> bootstrap: baselining this stream at v0 (nothing applied yet)"
    flyway baseline -baselineVersion=0 -baselineDescription="bootstrap (nothing applied)"
    echo "==> applying all migrations"
    flyway migrate
    ;;
  adopt)
    echo "==> adopt: stamping V1 as already applied (NOT running it)"
    flyway baseline -baselineVersion=1
    echo "==> applying migrations after V1"
    flyway migrate
    ;;
  "")
    flyway info
    ;;
  *)
    flyway "$@"
    ;;
esac
