# Dietry — Open-Source Nutrition Diary

> Track food, macros, and body metrics. Self-host it yourself or use the managed Cloud Edition.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.0.2-blue?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Linux-lightgrey)](https://flutter.dev/multi-platform)

> **🚧 Work in progress — the source code will be published here soon.**

Dietry is a full-featured Flutter nutrition tracker backed by a PostgreSQL database (Neon) accessed via PostgREST. Authentication uses Google OAuth2 with JWT tokens. It runs on Android, iOS, Web (PWA), and Linux desktop from a single codebase.

---

## Features

- **Food diary** — log meals with a built-in food database, barcode scanning, or custom foods
- **Macros & calories** — daily/weekly breakdown of calories, protein, fat, carbs, fiber, and more
- **Personal goals** — nutrition targets based on BMR/TDEE (Mifflin-St Jeor), activity level, and body goals
- **Activity tracking** — log workouts; import from Health Connect (Android) and Apple Health (iOS)
- **Body measurements** — weight, BMI, and body data tracked over time with charts
- **Water tracking** — simple daily hydration log
- **Open Food Facts** — search millions of products, no API key needed
- **Offline-capable** — queues writes when offline and syncs on reconnect
- **Privacy-first** — Row Level Security on every table; each user only sees their own data

### Community Edition vs Cloud Edition

This repository is the **Community Edition** — fully open source, self-hosted.

The **Cloud Edition** adds managed hosting, meal templates, and micronutrient tracking (vitamins, minerals). Its additional features live in a separate private package (`dietry_cloud`) that slots in via `pubspec_overrides.yaml`. The app compiles fine without it; the community stub package provides no-op implementations.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter 3.x / Dart ≥ 3.0.2 |
| Database | PostgreSQL via [Neon](https://neon.tech) |
| API | PostgREST (REST → SQL translation) |
| Auth | Google OAuth2 + JWT (Neon Auth / Better Auth) |
| HTTP | Dio with JWT interceptor + auto-retry on 401 |
| Charts | fl_chart |
| Health data | `health` package (Health Connect / HealthKit) |
| Storage | FlutterSecureStorage (native) / localStorage (web) |

---

## Project Structure

```
dietry/
├── lib/
│   ├── main.dart                  # App entry point & routing
│   ├── app_config.dart            # Build-time config (dart-define)
│   ├── models/                    # Pure data classes
│   ├── services/                  # Business logic & backend communication
│   ├── screens/                   # 13 screens
│   ├── widgets/                   # Reusable UI components
│   └── l10n/                      # Localization strings (de, en, es)
├── packages/
│   └── dietry_cloud/              # Community stub (no-op cloud features)
├── sql/                           # PostgreSQL schema & migrations (00–22)
├── config/
│   ├── ce-dev.json                # Community Edition dev config
│   └── prod.json.example          # Production config template
├── web/
│   ├── index.html                 # Flutter web entry point
│   ├── landing.html               # Marketing landing page
│   └── auth_callback.html         # OAuth redirect handler
└── build.sh                       # Build & deploy script
```

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.x
- A [Neon](https://neon.tech) PostgreSQL project
- A Google OAuth 2.0 Client ID ([guide](https://developers.google.com/identity/protocols/oauth2))

### 1. Clone & install dependencies

```bash
git clone https://github.com/tcriess/dietry.git
cd dietry
flutter pub get
```

### 2. Configure

Copy the example config and fill in your values:

```bash
cp config/prod.json.example config/ce-dev.json
```

`config/ce-dev.json`:
```json
{
  "DATA_API_URL": "https://<your-neon-project>.neon.tech",
  "AUTH_BASE_URL": "https://<your-auth-endpoint>",
  "ENVIRONMENT": "dev"
}
```

### 3. Set up the database

Run the SQL migration files in `sql/` in order against your Neon project:

```bash
# In the Neon SQL editor or via psql:
\i sql/00_shared_functions.sql
\i sql/01_create_users_table.sql
\i sql/02_create_nutrition_goals_table.sql
# … continue through the numbered files in order
```

Each file is idempotent (`CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE`, etc.).

### 4. Run

```bash
flutter run -d chrome   --dart-define-from-file=config/ce-dev.json   # Web
flutter run -d linux    --dart-define-from-file=config/ce-dev.json   # Linux desktop
flutter run -d <device> --dart-define-from-file=config/ce-dev.json   # Android / iOS
```

---

## Building for Production

```bash
# Web
flutter build web --release --dart-define-from-file=config/prod.json

# Android APK
flutter build apk --release --dart-define-from-file=config/prod.json

# Linux
flutter build linux --release --dart-define-from-file=config/prod.json
```

The `build.sh` script builds, packages, and deploys the web build to a server in one step:

```bash
./build.sh ce prod   # Community Edition, production
./build.sh ce dev    # Community Edition, dev
```

---

## Authentication Flow

**Web**: `LoginScreen` → Google OAuth → `web/auth_callback.html` (handles redirect outside Flutter, stores JWT in `localStorage`) → Flutter reads JWT back.

**Native**: Flutter → platform OAuth browser → deep-link callback → JWT stored in `FlutterSecureStorage`.

JWT auto-refresh runs 5 minutes before expiry; retries on 401 up to 3 times.

---

## Localization

Strings live in `lib/l10n/intl_*.arb` (English, German, Spanish). To add a language, copy `intl_en.arb` and translate the values, then add the locale to `lib/app_localizations.dart`.

---

## Running Tests

```bash
flutter test                                          # all tests
flutter test test/services/jwt_helper_test.dart       # single file
flutter test --name "BMR"                             # filter by name
flutter test --coverage                               # with coverage
flutter analyze                                       # static analysis
flutter format lib/                                   # format
```

---

## Contributing

Contributions are welcome — bug reports, feature requests, translations, and pull requests.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Open a pull request

Please open an issue first for larger changes so we can discuss the approach.

---

## License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

The Cloud Edition's additional features (`dietry_cloud` package, excluding the community stub in `packages/dietry_cloud/`) are **not** open source and are not included in this repository.
