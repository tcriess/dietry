# Database Migrations

Dietry's schema is managed with **Flyway Community** (free, Apache-2.0 engine),
run through Docker so no JVM is needed locally.

```bash
export DATABASE_URL='postgresql://user:pass@host/db?sslmode=require'
./flyway.sh info       # what's applied, what's pending
./flyway.sh migrate    # apply pending migrations
./flyway.sh validate   # checksum check, no writes
```

## Layout

```
sql/
  migrations/     V1__baseline.sql, V2__…   versioned, run once, in order
  repeatable/     R__fn_*.sql, R__seed_*    re-run whenever their checksum changes
  callbacks/      afterMigrate__*.sql       run after every successful migrate
  legacy/         the old 00..34 chain      HISTORY ONLY — never executed
flyway.conf       config (no credentials)
flyway.sh         Docker wrapper + lifecycle commands
```

### Where does a change go?

| Change | File |
|---|---|
| New table, column, index, policy, constraint | new `V{n}__description.sql` |
| Create or change a **function / RPC** | edit its `R__fn_<name>.sql` — *never* a versioned migration |
| Curated seed data | `R__seed_*.sql`, idempotent (`ON CONFLICT DO NOTHING`) |

**Functions live in exactly one file.** This is the rule that matters most: before
Flyway, `search_food_database` had been redefined by `CREATE OR REPLACE` in six
different migrations (19, 20, 24, 26, 31, 33), and reading its current shape meant
replaying all six in your head. Now it is one repeatable file that Flyway re-applies
whenever you edit it.

### Two rules that bite

1. **No `BEGIN;` / `COMMIT;` in a migration.** Flyway already runs each migration
   in its own transaction; an explicit `COMMIT` commits Flyway's transaction out
   from under it. (The old convention of wrapping every file in `BEGIN…COMMIT` is
   obsolete and must not be carried forward.)
2. **`GRANT` explicitly.** Production works partly because Neon has
   `ALTER DEFAULT PRIVILEGES … GRANT … TO authenticated` configured on the project,
   which is invisible in this repo. A self-hoster does not get it, and their
   PostgREST will 404 on any table you forget to grant.

## Lifecycle

Two one-off commands, because only a human knows whether a database already
contains the baseline objects. Guessing wrong would be silent in one direction, so
the choice is explicit:

```bash
./flyway.sh bootstrap   # database has NO Dietry schema yet  → baseline v0, then run V1..Vn
./flyway.sh adopt       # database ALREADY has the V1 objects → stamp V1 as applied, run V2..Vn
```

After that, everyday use is just `./flyway.sh migrate`.

Both fail loudly if you pick the wrong one: `bootstrap` on a populated database
dies on "already exists"; `adopt` on an empty one dies on the first migration that
references a missing table.

## Community Edition vs Cloud Edition

A **Cloud** database contains *both* schemas. They live in separate repos, version
independently, and each keeps its **own history table** — so their version numbers
never collide (this is why the old cloud chain had to jump `07 → 16` to stay in
step with CE's global numbering; it no longer does).

| | repo | history table |
|---|---|---|
| Community Edition | `dietry` | `flyway_history_ce` |
| Cloud Edition | `dietry-cloud` | `flyway_history_cloud` |

**The dependency arrow points one way: cloud → CE, never CE → cloud.** Every cloud
foreign key points into a CE table (`users`, `food_entries`, `food_database`,
`tags`). Nothing in CE may reference anything the cloud repo creates. That is what
lets the open-source edition run standalone, and `.github/workflows/db-migrations.yml`
enforces it by building CE alone against an empty database on every PR.

> It was broken for a long time: `sql/legacy/18_meal_template_id_in_food_entries.sql`
> added a foreign key from `food_entries` to `meal_templates`, a cloud-only table.
> A fresh CE database could not be built at all. That `ALTER` now lives in the cloud
> repo's baseline, where it belongs.

### Deploy order for a Cloud database — always CE first

```bash
export DATABASE_URL='postgresql://…'
cd dietry       && ./flyway.sh migrate    # CE stream
cd ../dietry-cloud && ./flyway.sh migrate # cloud stream
```

## Bringing up a new database

**A new Community Edition database:**

```bash
export DATABASE_URL='postgresql://…'
cd dietry && ./flyway.sh bootstrap
```

Prerequisites Flyway does **not** create (they are cluster-level): the roles
`authenticated`, `anonymous`, `authenticator`. The extensions `pg_trgm` and
`unaccent` *are* created by `V1__baseline.sql`.

**CE has no Neon-specific dependency.** `water_intake` used to be the last thing in
the open-source schema calling `auth.user_id()` — a function from Neon's
`pg_session_jwt` extension — which meant CE could not be self-hosted on stock
PostgreSQL. `V5__water_intake_align.sql` replaced it with the standard
`current_setting('request.jwt.claims')` policies (and, while there, fixed the two
other ways that table had drifted: a `text` `user_id` where every other table uses
`uuid`, and a missing foreign key to `users`). A fresh CE database now installs only
`pg_trgm`, `unaccent` and `plpgsql`.

The Cloud edition still needs `pg_session_jwt` — `meal_images` uses `auth.uid()` —
so its own baseline declares it.

The 449k BLS/FDC food rows are **not** a migration — load them with
`tmp/import_bls_to_postgres.py` / `tmp/import_fdc_to_postgres.py`. Only the 39
curated public activities are seeded (`R__seed_activity_database.sql`), because
the add-activity screen's picker is empty without them.

**A new Cloud database:** bootstrap CE first, then the cloud repo.

## Why the old `sql/00..34` chain is in `legacy/`

It no longer rebuilt the database, and hadn't for some time. Replaying it against
an empty database fails twice:

- `16_change_user_id_to_uuid.sql` → `ERROR: default for column "user_id" cannot be
  cast automatically to type uuid` (inconsistent with the reconstructed `00_initial_schema`)
- `18_meal_template_id_in_food_entries.sql` → `ERROR: relation "meal_templates" does not exist`

`V1__baseline.sql` is therefore generated from the **live production schema**, not
from replaying history. It was verified: CE baseline + cloud baseline reproduces
production statement-for-statement, and a fresh install converges byte-for-byte with
a migrated production database.

The legacy files are kept for archaeology. They are not in `flyway.locations` and
will never run again.

## Drift that V2–V5 clean up

Production had accumulated schema that no migration file described. Each of these is
fixed by a versioned migration, so a fresh build and production converge:

- **`search_food_database` had two overloads** (`(text,int)` and `(text,text[],int)`).
  This is not cosmetic: a call naming only `query` and `max_results` fails on
  production *today* with `function search_food_database(...) is not unique`. `V2`
  drops the dead 2-arg version, which **fixes** that call rather than breaking it.
- **`update_physical_activities_updated_at()`** — an orphan function; the trigger
  actually uses the shared `update_updated_at_column()`. Dropped by `V2`.
- **Four of five views bypassed RLS** (`V4`). A view without `security_invoker` runs
  as its owner, and the tables do not `FORCE ROW LEVEL SECURITY` — so any
  authenticated user could read every user's rows through them.
- **Three tables never got the `uuid` conversion** that `16_change_user_id_to_uuid.sql`
  was supposed to do: `water_intake` (`V5`), `feedback` (`V6`), and — in the cloud
  repo — `user_streaks` (`V2`). All three carried a `text` `user_id` and **no foreign
  key to `users`**, so orphan rows were possible and deleting a user left their data
  behind. All three now match every other user-owned table: `uuid` +
  `REFERENCES users(id) ON DELETE CASCADE` + the standard
  `current_setting('request.jwt.claims')` policies.

### Why legacy migration 16 actually fails

Worth writing down, because it took a while to find. `feedback.user_id` is the only
`user_id` in the schema with a **column default**:

```sql
DEFAULT (current_setting('request.jwt.claims', true)::json ->> 'sub')   -- a TEXT expression
```

PostgreSQL will not retype a column whose default cannot be cast to the new type:

```
ERROR: default for column "user_id" cannot be cast automatically to type uuid
```

`16_change_user_id_to_uuid.sql` never drops that default, so it dies there — and
because it was wrapped in one transaction, *nothing* in it applied. That is why three
tables were left on `text` while the rest converted. `V6` does it properly: drop the
default, retype the column, re-add the default cast to `uuid`.

A policy referencing the column is the same class of problem
(`cannot alter type of a column used in a policy definition`), which is why `V5`, `V6`
and cloud `V2` all drop their policies before converting and recreate them after.
