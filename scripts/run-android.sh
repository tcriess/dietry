#!/usr/bin/env bash
#
# Run the app on a connected device with hot reload, for one edition and one
# backend.
#
# The development-loop counterpart to build-android.sh: same config, same
# applicationId, same launcher label, but it hands you a live `flutter run`
# session instead of an artifact. Use build-android.sh when you want the APK
# CI would produce.
#
#   ./scripts/run-android.sh ce dev
#   ./scripts/run-android.sh cloud dev --release
#
set -euo pipefail

# shellcheck source=lib/build-env.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/build-env.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/run-android.sh <ce|cloud> <dev|prod> [options]

  ce      Community Edition   → de.dietry.community, config/ce-<env>.json
  cloud   Cloud Edition       → de.dietry.app,       ../dietry-cloud/config/cloud-<env>.json

  dev     development backend, "Dev" launcher label
  prod    production backend

Options:
  -d, --device SERIAL   which adb device to use (default: the only one connected)
      --release         run a release build (no hot reload)
      --profile         run a profile build (for performance work)
      --no-pub-get      skip flutter pub get
  -h, --help            show this

Anything after `--` is passed straight to `flutter run`, e.g.
  ./scripts/run-android.sh ce dev -- --verbose
EOF
}

build_mode=debug
device=''
do_pub_get=1
passthrough=()

[ $# -lt 2 ] && { usage; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
variant=$1; environment=$2; shift 2

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--device)   device=${2:-}; [ -n "$device" ] || die "--device needs a serial"; shift ;;
    --release)     build_mode=release ;;
    --profile)     build_mode=profile ;;
    --no-pub-get)  do_pub_get=0 ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; passthrough=("$@"); break ;;
    *)             die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

dietry_resolve "$variant" "$environment"
serial=$(dietry_pick_device "$device")

info "Running $APP_NAME ($VARIANT/$BUILD_ENV, $build_mode) on $serial"
info "  applicationId  $APP_ID"
info "  config         $CONFIG_FILE"

dietry_activate_signing

dietry_activate_overrides

[ "$do_pub_get" = 1 ] && run flutter pub get

export ORG_GRADLE_PROJECT_edition="$EDITION"
export ORG_GRADLE_PROJECT_appName="$APP_NAME"

# `flutter run` holds the terminal; the EXIT trap in build-env.sh restores
# pubspec.lock and pubspec_overrides.yaml when the session ends, including on
# Ctrl-C.
run flutter run \
  "--$build_mode" \
  -d "$serial" \
  "--dart-define-from-file=$CONFIG_FILE" \
  "--dart-define=GIT_HASH=$GIT_HASH" \
  "--dart-define=BUILD_DATE=$BUILD_DATE" \
  ${passthrough+"${passthrough[@]}"}
