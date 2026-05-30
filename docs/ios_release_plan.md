# iOS release plan (Cloud edition)

Long-running effort to ship the **Cloud edition** to iOS. macOS is a possible
nice-to-have but explicitly **not** a goal. The iOS build is the Cloud edition
(private repo `../dietry-cloud`); the open-source CE repo holds the shared code.

## Why a native app at all

Almost everything works in the web app already. The native iOS app exists for
three things, which are therefore **required at parity from day one**:

1. **Native notifications** (water reminders, etc.)
2. **Label scanner** (camera / `mobile_scanner`)
3. **HealthKit** (the iOS counterpart to Android Health Connect)

## Constraints

- **No Mac access.** CI is both the build machine and the test harness.
  Renting a cloud Mac is a fallback only — the project earns nothing yet, so
  free-first.
- **Devices can be borrowed** but only for short windows, not extended periods.

## The hard blocker (resolve before App Store submission)

**Neon Auth supports neither Apple nor custom OAuth providers.** App Store
Review **Guideline 4.8** requires "Sign in with Apple" *only because the app
offers Google sign-in*. Since we can't add Apple via Neon Auth, the realistic
unblock is:

> **Drop the Google button on the iOS build and offer email-only**
> (Neon Auth's own email/password). That qualifies for the 4.8 exemption
> ("app exclusively uses your company's own account setup and sign-in
> systems") and ships. Google sign-in remains available on the web app.

Alternatives (worse): implement Apple sign-in *outside* Neon Auth (large
backend effort), or wait for Neon Auth to add Apple support. **Decision
deferred** — it gates the App Store submission, not the Phase 1–2 prep below.

## Cost floor (unavoidable, at the very end)

- **$99/year Apple Developer Program** — required for signing, TestFlight, App
  Store. No free substitute.
- **~1 focused day with a borrowed iPhone** — the Simulator has no camera and
  only stub Health data, so the **label scanner and HealthKit can only be
  validated on a real device**. Everything else is free.

## Free, no-Mac dev loop

- **Codemagic free tier** (~500 macOS build-min/month, ignores repo
  visibility) is the primary build workhorse for the private Cloud repo.
  GitHub Actions has an iOS job already, but private-repo macOS minutes count
  10× against quota — use it as backup.
- Build `flutter build ios --simulator --no-codesign` (no account, no signing)
  and run an `integration_test` driver on a booted Simulator that uploads
  **screenshots + logs as build artifacts** — that's how we "see" the app and
  catch regressions without a Mac in front of us.

## Key code facts (from a repo audit, 2026-05-30)

- **OAuth uses an embedded WebView on iOS today** (`main.dart`
  `NeonAuthWebViewDialog`, intercepts the `neon_auth_session_verifier` query
  param around `main.dart:143-148`) — **not** a deep link. So
  associated-domains / `apple-app-site-association` work is **off** the
  critical path. **But Google blocks embedded WebViews** (`disallowed_useragent`).
  Email login works in the WebView; Google would need
  **`flutter_web_auth_2`** (already a `pubspec` dep but unused →
  `ASWebAuthenticationSession`, which Google allows). This only matters if we
  keep Google on iOS (see blocker).
- **`google_sign_in` is NOT a dependency** — login is pure browser OAuth, so
  no `GoogleService-Info.plist` / reversed-client-id needed.
- **Cloud iOS bundle id** defaults to the Flutter template
  `com.example.dietrycloud`; it must become **`de.dietry.app`** (mirror the
  Android `edition`→`appId` logic).
- `ios/` and `macos/` scaffolds exist but are vanilla `flutter create`. (If
  macOS is ever pursued: its `Release.entitlements` is missing
  `com.apple.security.network.client`, which would block all backend calls.)
- iOS-sensitive plugins needing Info.plist usage strings: `image_picker` +
  `mobile_scanner` (camera, photo library), `health` (HealthKit share/update).
  `flutter_secure_storage` (Keychain) and `sqflite` are automatic.
- **Local notifications are an iOS no-op today** (`water_reminder_service.dart`
  returns `isSupported == false` on iOS). Enabling needs
  `DarwinInitializationSettings` + a permission request — no APNs, no paid
  account, **fully testable in the Simulator**.

## Phases

### Phase 1 — free Simulator build
- Set Cloud bundle id `de.dietry.app` (xcconfig, mirror Android edition logic).
- Add iOS `Info.plist` usage strings (camera, photo library, HealthKit).
- Add `codemagic.yaml`: `flutter build ios --simulator --no-codesign` for the
  Cloud config + an `integration_test` smoke run uploading screenshots.
- **Exit:** Cloud app boots in the Simulator; email login + core tracking work.

### Phase 2 — free, auth-agnostic prep (test later where possible)
- **Enable iOS local notifications** in `water_reminder_service.dart`
  (`DarwinInitializationSettings` + permission). Validate in the Simulator.
- **HealthKit wiring** via the existing `health` package conditional import +
  entitlement (device validation deferred to Phase 3).
- Camera/scanner plist already covered by Phase 1 usage strings.
- **Contingent:** Google via `flutter_web_auth_2` — only if we keep Google on
  iOS. Skip if going email-only.
- **Dropped:** Sign in with Apple scaffold (blocked — not buildable via Neon
  Auth).

### Phase 3 — paid + borrowed-device release (gated on the 4.8 decision)
- Enroll Apple Developer Program ($99), create App ID `de.dietry.app` with
  capabilities (HealthKit; Sign in with Apple only if the blocker is somehow
  resolved), set up signing (Codemagic automatic).
- In one focused borrowed-iPhone session, validate device-only features:
  login, HealthKit, barcode camera, notifications.
- TestFlight → App Store submission.
