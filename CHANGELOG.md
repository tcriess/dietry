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
