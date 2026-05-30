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
