# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Food log**: name a new portion size straight from the amount dialog. The unit
  dropdown now ends in "+ New portion size …", which opens a two-field form with
  the weight pre-filled from the amount already entered — so after scanning a
  barcode you can record "1 bar = 30 g" on the spot instead of going to the food
  database screen for it. Available in the quick-add confirm dialog and in the
  full add-entry screen. For a public food owned by someone else, the portion is
  stored on a private copy of the food (micronutrients are not carried over to
  that copy).

### Changed
- 

### Fixed
- **Food log**: the quick-add amount dialog no longer crashes for a food that has
  two portions with the same name, or a portion named exactly "g"/"ml" — the unit
  list is deduplicated, and those names are now rejected when a portion is
  created from the amount dialog.

### Deprecated
- 

### Removed
- 

### Security
- 

---

## [1.6.0] — 2026-08-20

### Added
- **Turn what you already ate into a meal template** (Cloud Edition) — tap the bookmark on a meal's heading to tick that whole meal, adjust the selection, and the template editor opens already filled in with those foods and their weights. Name it, add a picture or tags, and it is ready to log with one tap tomorrow. Building a template used to mean typing every ingredient in again, even for the dinner you had just finished logging. Once it is saved, you are offered the swap: the entries it came from give way to a single portion of the template, leaving the day's nutrition exactly as it was.

### Fixed
- **A meal template is logged into the meal you added it from** — it always landed in lunch unless you noticed the meal dropdown in the dialog and corrected it.
- **A meal template can no longer end up empty** — if its ingredients could not be stored, the template itself was left behind: it appeared in the list and logged as zero calories, with nothing to say why. Saving is now all-or-nothing, and editing one can no longer lose its ingredient list.
- **A ride there and back is no longer merged into one** — when Google Fit records the whole outing as one session alongside the individual legs, the second leg was treated as a duplicate of the first and removed, then re-imported on the next sync, so deleting one copy brought both back. A session that only spans other workouts is now recognised for what it is and left out of the import, and no workout is ever resolved away in favour of one it does not overlap.
- **Equipment is attached to imported workouts more reliably** — if the gear list could not be loaded at the moment a workout arrived (a token being refreshed was enough), the workout stayed without gear for good. A later import now fills it in, the offline copy of the list is no longer overwritten with an empty one, and the gear chip also appears on activities that arrived without a distance — previously there was no way to assign a bike to those at all.
- **Saving a meal template no longer fails with an error** — a template whose ingredients did not all carry the same nutrients (one with a fibre value next to one without) was rejected when saved, with nothing to say why.
- **"Repeat yesterday's dinner" appears straight away** — the suggestions were fetched before the session was ready and then never retried, so on a fresh start they only turned up after visiting the previous day and coming back. They now retry, read from the offline copy when there is no connection, and work in guest mode too.

---

## [1.5.0] — 2026-08-07

### Added
- **Plan a holiday, not one cheat day at a time** — declare a date range and every day in it counts as a cheat day, future dates included. The overview names the holiday it belongs to, so it is obvious why a day is not counting towards your reports. Removing the holiday un-marks its days again, and you can still switch a single day back on by hand without disturbing the rest.
- **Turn a trip already in your calendar into a holiday** (Android/iOS) — pick one of your calendar's all-day entries and its dates and name are filled in for you. It reads whatever calendars your phone already syncs, so Google, Outlook and iCloud all work without connecting an account to Dietry. Nothing is written until you confirm the dates.
- **Export your nutrition history to your calendar** — from Reports, save the shown period as a calendar file with one all-day entry per day: calories at a glance, the full macro breakdown inside. Useful for seeing what you ate next to what you were doing. Re-exporting the same period updates those entries instead of creating a second set.
- **See which food you are actually picking** — the search results and the amount dialog now show brand and source, so two similarly named foods can be told apart before you log one.

### Fixed
- **Newly created gear is picked up straight away** — after adding a bike or a pair of shoes, an activity it was assigned to still showed "which gear?", and the picker offered only the equipment that existed beforehand. Gear you have retired also keeps its name on the workouts it was used for.
- **An imported workout no longer appears twice** — when Google Fit finalises an auto-detected activity it re-exports it with a corrected end time, which was stored as a second copy. Overlapping imports are now merged into one, the later import wins, and anything you added yourself — gear, notes — survives the merge. Copies that already got duplicated are folded back together on the next import.
- **Imported activities keep their proper name** — the same ride could come in as "Radfahren (normal)" one time and "Biking" the next, depending on whether the activity database could be reached. A failed lookup can no longer overwrite a name that was already correct.
- **The activity list is in a consistent order** — the day's workouts appeared in a different order depending on whether the data came from the local cache or the server, and freshly imported ones dropped to the bottom.

---

## [1.4.1] — 2026-07-27

### Fixed
- **Meal templates: searching for ingredients works again** — building a template was impossible because the ingredient search only ever answered "search not available". Both sources are now there: your own food database, and the online search across USDA and Open Food Facts. Ingredients found only online also save correctly, which previously failed outright.

---

## [1.4.0] — 2026-07-26

### Added
- **Log what you actually weigh** — pasta, rice and other foods are labelled raw or dry, but you weigh them cooked. You can now log the cooked weight directly and the app converts it back to the label basis, so a plate of pasta no longer counts as more than double what you ate.
- **Your own cooking factor** — the published raw→cooked ranges are wide because yield depends on how *you* cook. Weigh a batch once ("250 g dry became 560 g") and the app remembers your factor for that food and uses it from then on.
- **The user manual is a tap away** — the overflow menu now links straight to the online manual.

### Changed
- **A nudge toward cooked weight** — when you log a food whose label values are raw or dry, the app now points this out and offers the cooked-weight option, consistently in both the quick-add sheet and the full add screen.

### Fixed
- **Stuck on "offline" while online** — when a login could no longer be renewed, every request failed in a way the app mistook for a lost connection. It then sat behind the red offline bar for good: nothing synced, days could not be changed, pulling to refresh did nothing, and restarting made no difference. The app now tells a dead session apart from a dead connection, rechecks the connection on its own and when you return to the app, and says plainly when a session has expired so you can sign in again. A single unsendable change can no longer block everything queued behind it.
- **The status bar covered the date** — it now sits above the day view instead of on top of it, so stepping between days always works.
- **English mode really is English** — the food-logging and add-activity screens, the meal-template and micronutrient screens, and stray "Gesamt" / "Gemessen am" labels no longer fall back to German.
- **Reports came up empty for some sessions** — reports and the food search now use the same authenticated connection as the rest of the app, so a refreshed login no longer leaves them looking at stale credentials and returning nothing.
- **"How sure are you?" chips were unreachable** — with the keyboard open, the estimate chips could not be tapped.
- **Gear chips missing right after opening the app** — they now appear once your gear has loaded, instead of staying blank until the next visit.
- **Entries missing on a cached day** — days that already had a saved goal skipped fetching newer entries from the server; they now reconcile too.
- **Reports: inverted gear distance** — a gear's usage read as "1000 von 10 km" instead of the other way round.

### Notes for self-hosters
- This release adds migration `V8__user_food_prefs_cooked_factor.sql` (a per-user `cooked_factor` on `user_food_prefs`). Apply migrations before deploying the new app.

---

## [1.3.2] — 2026-07-18

### Changed
- **Faster startup** — the app now opens straight to your data from its on-device copy instead of waiting for the server to answer, so it's ready in a moment rather than after a long spinner. It also stays usable when you open it offline instead of dropping you back to the login screen.
- **Clearer food entries** — each logged food now shows its name in full across the top of its card, with a prominent calories bar and slimmer protein/fat/carbs bars underneath, each showing how much of that day's goal the entry uses.
- **Browse earlier days** — stepping back through days is now bounded by when you actually started tracking (your first goal, food entry or activity) rather than requiring a nutrition goal on each day, so you can review days that only have entries or activities.

### Fixed
- **Food search sometimes found nothing on the first try** — a search made right after opening the app, or while a sleeping server was waking up, could come back empty until you searched again; it now retries automatically and pre-warms the connection when the quick-add sheet opens.
- **Reports: gear past its wear budget** — a piece of gear that has passed its replacement budget now reads "budget used up" instead of a misleading remaining value.
- **Microphone is no longer a required feature** — the app only uses the microphone for optional voice meal entry, so it no longer declares it as required and installs on devices without one.

---

## [1.3.1] — 2026-07-14

### Fixed
- **Cloud Edition web app** — the on-device AI meal parser is a native runtime, and it was being compiled into the web build, which cannot load it. The web build failed, so 1.3.0 never reached the Cloud web app. On the web the AI parser is simply not offered now, and "describe your meal" uses the built-in parser instead.

The Community Edition is unaffected in every respect — it never bundled that runtime. The version bump only keeps both editions in lockstep.

---

## [1.3.0] — 2026-07-14

### Added
- **Gear tracking** — keep track of the shoes, bikes and other equipment you train with. Attach gear to an activity by hand or let it attach itself: give a pair of shoes a default activity type and every imported run picks them up automatically. Set a replacement budget ("replace at 700 km") and Dietry counts down to it, including any distance the item had before you started tracking.
- **Gear on the Reports page** — a new card showing what you actually trained on in the selected period, and how far each item is through its wear budget. Retired gear stays out of the way unless you used it.
- **Describe your meal** — log a meal by describing it in plain language ("a bowl of porridge with a banana and a coffee") instead of searching for each item in turn. Type it or dictate it; Dietry breaks the description into separate entries with portions, and you review them before anything is saved.
- **On-device AI meal parsing** (Pro, mobile) — an optional language model, downloaded once (~230 MB), takes over the descriptions the built-in parser cannot make sense of, and can add an unrecognised food to the database for you. It runs entirely on your phone: no part of what you eat is sent anywhere.
- **Nutrition uncertainty** — a logged entry now records how precisely it is known (a weighed portion is not a guessed one), and the Overview draws the resulting ± range as an error bar over the calorie and macro figures. An estimate now looks like an estimate instead of a hard number.

### Changed
- **Food search survives typos and accents** — "brokoli" finds broccoli, "jalapeno" finds jalapeño.
- **Search results are ranked by specificity** — searching for a plain ingredient no longer buries it under elaborate dishes that merely contain it ("brokoli" used to return a BBQ salmon meal).
- **Under the hood** — the database schema is now managed with Flyway instead of hand-numbered scripts, so a self-hosted instance can be brought up to date with one command and its state verified against the repo.

### Fixed
- **Guest mode was broken in production** — the anonymous role was missing its grants, so trying the app without an account failed instead of just working.
- **German portion words leaked into the food search** — describing "eine Scheibe Brot" searched for "Scheibe Brot" rather than for bread.

### Security
- **Four database views bypassed row-level security** — created without `security_invoker`, they ran as their owner rather than as the querying user, which allowed a logged-in user to read rows belonging to other users through those views. The views now run as the caller, and RLS applies to them as it always did to the underlying tables. Self-hosters should apply the pending migrations (`./flyway.sh migrate`) — this one is not optional.
- **Flyway's own history tables were writable by any logged-in user** — a user could have rewritten or deleted the migration history. They are now owned by the migration role and readable only where necessary.

---

## [1.2.0] — 2026-07-05

### Fixed
- **Guest mode is usable on phones again** — sign in to sync directly from the guest-mode banner (just tap it), the top-bar action icons no longer disappear on narrow screens (secondary actions moved into a "⋮" overflow menu), and the info/guest banners no longer cut off longer text.
- **"Cheat Day" chip no longer overflows** — the streak + Cheat Day row now wraps instead of running off the right edge on smaller screens.

### Changed
- **Version number** on the Info screen now shows just the release version (e.g. `1.2.0`), without the internal build suffix.
- **Under the hood** — dependency and toolchain modernization: upgraded the sharing, notifications, timezone, on-device storage, secure-storage and device-info libraries; moved to Flutter 3.44.4; and raised the Android build to Java 17. No intended change to how the app behaves.

---

## [1.1.7] — 2026-07-02

### Added
- **Create food from an unknown barcode** — when a barcode scan matches neither your food database nor Open Food Facts, you can now create a new food carrying that barcode instead of hitting a dead end. Enter the nutrition manually or, on Pro/mobile, scan it straight off the nutrition label; the food is saved with its barcode and logged in one flow.
- **Repeat a meal even when the section already has entries** — the "Repeat yesterday's …" chips in the Entries overview now also appear under meal sections that already contain items, not just empty ones.

### Changed
- **"Kalorienbilanz" is now a true energy balance** — the report's calorie-balance chart compares intake against your maintenance (BMR/TDEE derived from your body data and tracking method) instead of just intake minus exercise. A green bar now means a real deficit (below maintenance), orange a surplus.

### Fixed
- **Health Connect no longer double-counts a workout** — the same training exported by two apps (e.g. your watch plus Google Fit re-exporting it) is de-duplicated by overlapping time and activity type, so it shows only once.
- **Food entries load right after logging in from guest mode** — previously they stayed empty (and newly added entries were written to the discarded guest database) until the app was restarted.

---

## [1.1.6] — 2026-06-21

### Added
- **Protein-only mode** — a focused variant of macro-only tracking where only protein has a target; calories and the other macros stay hidden.

### Changed
- **"Repeat meal" item picker** — repeating a meal that has more than one entry now opens a checklist so you can choose exactly which items to copy; single-item meals still repeat in one tap. Available both on the Entries-list "Repeat …" chips and in the quick-add Recent tab.

### Fixed
- **Reminders on cheat days** — food and water nudges are now suppressed on cheat days, evaluated per calendar day.
- **Quick-add no longer shifts the list** — logging a food from the quick-add toast no longer makes the list jump, and "Repeat yesterday's meal" is now reachable on a fully empty day.

---

## [1.1.5] — 2026-06-02

### Added
- **Onboarding tutorial** — new users (guest or logged-in) get a one-time spotlight tour right after creating their first nutrition goal, highlighting the main areas of the app. It can be replayed any time from the profile screen.

### Fixed
- **"Repeat meal"** now logs the copied entries under the meal you tapped. Repeating yesterday's dinner into an empty lunch slot (or today's lunch into dinner) previously kept the original meal type; the copies now adopt the target meal.

---

## [1.1.4] — 2026-05-30

### Added
- **Tag management screen** — review the tags you've created and delete them; deleting a tag removes it from every food it was applied to.
- **Meal-log reminder (opt-in)** — an optional daily nudge at 15:00 when you haven't logged any food yet that day. Enable it in the profile screen, next to the water reminder.

### Changed
- **Quick-add sheet** — now defaults to a food's primary (named) portion instead of a raw gram serving size, and hides calories when macro-only mode is on.
- **Reminder notifications are localized** (German, English, Spanish) instead of always German.

### Fixed
- **Reminders fire at the correct local time** — the scheduler used UTC, so water reminders could arrive in the middle of the night; it now uses the device's timezone.
- **Guest → account migration no longer loses data** — water-intake history and cheat days were silently dropped when converting a guest account to a real one; they now migrate correctly.

---

## [1.1.3] — 2026-05-25

### Added
- **Add-food FAB on the Overview tab** — log a meal without first switching to the Entries tab.
- **One-tap "Repeat yesterday's meal"** — compact bar at the top of the Recent tab in the quick-add sheet, plus a chip on empty meal groups in the Entries list. Falls back to a leftover-pattern hint (lunch ← yesterday's dinner, dinner ← today's lunch) when the same meal-type has nothing from yesterday.
- **Favorite toggle in the quick-add sheet** — star icon on search-results and favorites rows to add/remove favorites without leaving the sheet.
- **Per-food portion memory** — the quick-add sheet now pre-fills your last amount and unit for each food instead of the generic serving size. New `user_food_prefs` table (per-user, per-food) so it also works for public/shared foods.
- **Meal templates (Cloud) remember the last portion count** — the Portions input in the log dialog defaults to your typical multiplier (e.g. always 1.5 ×) instead of always 1.

### Changed
- Pinned repeat-meal bar in the quick sheet uses theme-aware Material 3 colors and a compact single-line layout so the Recent list keeps most of the vertical space.

---

## [1.0.0] — 2026-04-04

### First Public Release ✨

Dietry v1.0.0 marks the first stable public release of the open-source Community Edition.

#### Added

**Core Features**
- 🍽️ **Food Diary** — Log meals with portion tracking
- 📊 **Nutrition Breakdown** — Daily/weekly macros (protein, carbs, fat), calories, fiber, and micronutrients
- 🎯 **Personalized Goals** — Based on BMR/TDEE calculations (Mifflin-St Jeor formula), activity level, and body goals
- 🏃 **Activity Tracking** — Log workouts and exercises
- 📈 **Health Integrations** — Import steps and activities from Health Connect (Android) and Apple Health (iOS)
- 💪 **Body Measurements** — Track weight, BMI, body composition with charts
- 💧 **Water Tracking** — Simple daily hydration logging
- 🔒 **Privacy-First** — Row Level Security on every table; users can only see their own data
- 🔍 **Open Food Facts Integration** — Search millions of food products with nutrition data (no API key required)
- 📱 **Offline Capable** — Queue writes when offline, sync automatically on reconnect
- 🌍 **Multi-Platform** — Native web (PWA), Android, iOS, and Linux desktop from single codebase
- 🌐 **Multi-Language** — English, German, Spanish localization

**Architecture**
- PostgreSQL database backend (Neon) with PostgREST API
- Google OAuth2 authentication with JWT tokens
- Flutter 3.x framework with Material Design
- Conditional imports for platform-specific code (web, Android, iOS, Linux)
- Cloud Edition support via `pubspec_overrides.yaml` for managed hosting features

#### Community Edition Features

This repository is the **Community Edition** — fully open source and self-hosted.

- ✅ Complete nutrition tracking functionality
- ✅ All food database features
- ✅ Activity logging and health integrations
- ✅ Full source code and database schema
- ✅ Row-level security for privacy
- ✅ Deployable on any PostgreSQL-compatible database

**Not included in Community Edition:**
- ❌ Managed hosting (self-host required)
- ❌ Meal templates and recipe system
- ❌ Advanced micronutrient tracking
- ❌ Multiple user profiles
- ❌ Advanced analytics and reporting

These features are available in the **Cloud Edition** (separate private package).

#### Known Limitations

- iOS app submission to App Store pending (testable via TestFlight or dev build)
- Android app submission to Google Play pending (testable via direct APK or Play Store internal testing)
- Meal templates and micronutrient tracking available in Cloud Edition only
- Health data import requires Health Connect (API 29+) on Android or HealthKit on iOS

#### Tech Stack

| Component | Technology |
|---|---|
| **Frontend** | Flutter 3.x, Dart ≥ 3.0.2 |
| **Database** | PostgreSQL via Neon |
| **API** | PostgREST |
| **Auth** | Google OAuth2 + JWT (Neon Auth) |
| **HTTP Client** | Dio with JWT interceptor, auto-retry |
| **Charts** | fl_chart |
| **Health Data** | `health` package (Health Connect / HealthKit) |
| **Food Data** | Open Food Facts REST API |
| **Storage** | FlutterSecureStorage (native) / localStorage (web) |

#### Breaking Changes

N/A — first release

#### Migration Guide

N/A — first release

#### Contributors

- Thorsten Rieß ([@tcriess](https://github.com/tcriess))

---

## Versioning

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** — breaking API/schema changes
- **MINOR** — new features, backward compatible
- **PATCH** — bug fixes, backward compatible

---

## License

Licensed under the [MIT License](LICENSE) — see LICENSE file for details.
