# Build, run & release scripts

One build path for every edition, backend and target.

```bash
./scripts/build.sh      <ce|cloud> <dev|prod> <web|linux|android> [options]
./scripts/release-all.sh [options]      # all 12 combinations
./scripts/run-android.sh <ce|cloud> <dev|prod> [options]   # hot-reload session
```

These replace the old untracked root `build.sh` and `build_and_release_all.sh`.

| | `ce` | `cloud` |
|---|---|---|
| applicationId | `de.dietry.community` | `de.dietry.app` |
| config | `config/ce-<env>.json` | `../dietry-cloud/config/cloud-<env>.json` |
| `dietry_cloud` | stub in `packages/` | the real package via `pubspec_overrides.yaml` |
| launcher label | Dietry CE / Dietry CE Dev | Dietry / Dietry Dev |
| keystore | `android/key-ce-<env>.properties` | `android/key-cloud-<env>.properties` |
| web host | ce.dietry.de / ce-dev.dietry.de | cloud.dietry.de / cloud-dev.dietry.de |

The two editions install side by side — different applicationIds — so a CE dev
build and a Cloud dev build can share a device.

## Examples

```bash
# CE dev APK, installed and launched on the connected phone
./scripts/build.sh ce dev android --run

# Cloud production, APK + Play Store bundle
./scripts/build.sh cloud prod android

# Build the web app and publish it (asks before touching production)
./scripts/build.sh cloud prod web --deploy

# Develop against the cloud dev backend with hot reload
./scripts/run-android.sh cloud dev

# Everything, without deploying anything
./scripts/release-all.sh

# Only the Android builds, production only
./scripts/release-all.sh --only android --env prod
```

Run any of them with `--help` for the full option list.

## Why these exist rather than bare `flutter build`

A correct build has to line up four things, and getting any of them wrong
produces an artifact that looks fine and is not:

- **the config** — `--dart-define-from-file`, and the cloud one is not in this
  repository at all;
- **`ORG_GRADLE_PROJECT_edition`** — `android/app/build.gradle` derives the
  applicationId from it, so forgetting it builds the community app with cloud
  code inside;
- **`ORG_GRADLE_PROJECT_appName`** — the launcher label, your only way to tell
  a dev build from a prod one on the device;
- **`pubspec_overrides.yaml`** — present for cloud, absent for CE.

They reproduce the Android job of `.github/workflows/build.yml` (CE) and its
counterpart in `dietry-cloud` (Cloud), so a local artifact is the artifact CI
makes.

## What they refuse to do

- **Build with a config that disagrees with the arguments.** A
  `cloud-prod.json` that says `"ENVIRONMENT": "development"` stops the build.
  That mismatch is how a "prod" build ends up talking to the dev database.
- **Silently fall back to the debug key.** A release build whose
  `android/key-<variant>-<env>.properties` is missing fails outright rather
  than producing an APK that looks shippable and is not. Override deliberately
  with `DIETRY_ALLOW_DEBUG_SIGNING=1`.
- **Leave `pubspec.lock` pointing at `../dietry-cloud`.** A cloud build
  necessarily rewrites it; it is restored on exit, including on Ctrl-C and on
  failure. See the `pubspec.lock` trap in `RELEASE.md` — that lock must never
  be committed to CE.
- **Leak a stale override into a CE build,** or leave `android/key.properties`
  (which holds passwords) lying around afterwards.
- **Deploy to production without being asked.** `--deploy` on a `prod` web
  build requires typing `deploy`; `release-all.sh --deploy` asks once up front.
  Without `--deploy`, nothing leaves the machine.
- **Pass `--build-number`.** The build number comes from `pubspec.yaml`; a
  hand-passed one desyncs the Play Store versionCode, which Play then rejects.

## Signing

Release builds select `android/key-<variant>-<env>.properties` into
`android/key.properties` for the duration of the build, because
`app/build.gradle` reads that one fixed name. Each properties file names its
own `.jks` in `android/app/`. All of them are gitignored, and
`key.properties` is removed again when the script exits.

If `adb install` reports a signature mismatch, the device holds a build of that
applicationId signed with a different key:

```bash
adb uninstall de.dietry.community   # or de.dietry.app — this deletes its data
```

## Web deploy configuration

`config/deploy.env` holds the server to publish to. It is **gitignored** — this
repository is public, so the host must never be committed. Copy the example and
fill it in:

```bash
cp config/deploy.env.example config/deploy.env
```

Every value can come from the environment instead, as `DIETRY_DEPLOY_HOST`,
`_USER`, `_PORT`, `_STAGE`, `_ROOT`. The public hostname itself is derived from
edition + environment and needs no configuration.

## Requirements

`flutter`, `jq` and `adb` on `PATH`, plus a JDK 21 for the Gradle build. Cloud
builds need the `dietry-cloud` checkout as a sibling directory, or
`DIETRY_CLOUD_DIR` pointing at it.

On a machine where Android Studio is installed, Flutter prefers Studio's
bundled JDK over `JAVA_HOME` and `PATH`. If Gradle rejects it as too new:

```bash
flutter config --jdk-dir=/usr/lib/jvm/java-21-openjdk-amd64
```

## Layout

```
scripts/
├── build.sh           one edition × environment × target
├── release-all.sh     all 12 combinations
├── run-android.sh     flutter run with hot reload
└── lib/build-env.sh   shared: argument resolution, signing, overrides, cleanup
```
