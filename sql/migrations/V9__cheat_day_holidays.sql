-- Holidays: a named, contiguous run of cheat days declared in one go.
--
-- A holiday is stored as one ordinary cheat_days row per date, all sharing a
-- holiday_id, rather than as a separate (start_date, end_date) range table.
-- That keeps every existing consumer working untouched — the
-- daily_nutrition_summary report exclusion, the streak union, the water and
-- food-log reminder suppression, the offline SQLite mirror and guest mode all
-- already understand "this date is a cheat day" and nothing else.
--
-- The cost is N rows per holiday, which is trivial at this cardinality, and the
-- benefit is that a single day inside a holiday can still be un-cheated by the
-- existing per-day toggle without any special cases.
--
-- holiday_id is NULL for a day the user toggled by hand. The label lives in the
-- existing `note` column, repeated on every row of the holiday.

ALTER TABLE public.cheat_days
  ADD COLUMN IF NOT EXISTS holiday_id uuid;

-- Serves both "list my holidays" (grouping by holiday_id) and the delete of a
-- whole holiday. Partial, because hand-toggled days are the common case and
-- carry no holiday_id.
CREATE INDEX IF NOT EXISTS idx_cheat_days_user_holiday
  ON public.cheat_days (user_id, holiday_id)
  WHERE holiday_id IS NOT NULL;

-- Explicit grants: production only works without them because Neon has
-- ALTER DEFAULT PRIVILEGES configured at project level, which is invisible here
-- and absent for self-hosters.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cheat_days TO authenticated;

COMMENT ON COLUMN public.cheat_days.holiday_id IS
  'Groups the days of one declared holiday. NULL = day was toggled individually.';

COMMENT ON COLUMN public.cheat_days.note IS
  'Free-text note; for a holiday, the holiday label repeated on each of its days.';
