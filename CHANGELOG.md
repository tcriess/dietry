# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- 

### Changed
- 

### Fixed
- 

### Deprecated
- 

### Removed
- 

### Security
- 

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
