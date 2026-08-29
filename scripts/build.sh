#!/usr/bin/env bash
#
# Build Dietry for one edition, one backend and one target.
#
#   ./scripts/build.sh <ce|cloud> <dev|prod> <web|linux|android> [options]
#
# Replaces the old untracked root build.sh. Everything that made a build
# correct there is preserved — the config file, the gradle properties that pick
# the applicationId and launcher label, the GIT_HASH-from-the-right-repo rule —
# plus the guards that script lacked: a missing keystore now fails a release
# build instead of silently signing with the debug key, pubspec.lock is always
# restored, and deploying to production asks first.
#
set -euo pipefail

# shellcheck source=lib/build-env.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/build-env.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/build.sh <ce|cloud> <dev|prod> <web|linux|android> [options]

  ce      Community Edition   → de.dietry.community, config/ce-<env>.json
  cloud   Cloud Edition       → de.dietry.app,       ../dietry-cloud/config/cloud-<env>.json

  dev     development backend, "Dev" launcher label
  prod    production backend

Targets:
  web       release WASM build, tarred; add --deploy to publish it
  linux     release x64 bundle, tarred next to the repo
  android   release APK (+ .aab unless --no-bundle)

Options:
      --deploy          web only: upload and unpack on the server (asks first
                        for prod). Server details come from config/deploy.env.
  -r, --run             android only: install on a device and launch it
  -d, --device SERIAL   android only: which adb device (default: the only one)
      --no-bundle       android only: skip the Play Store .aab
      --debug           android only: debug build instead of release
      --clean           flutter clean first (the old build.sh always did this)
      --no-pub-get      skip flutter pub get
      --logs            after --run, tail the app's logcat
  -h, --help            show this

Notes:
  • Cloud builds need the dietry-cloud checkout as a sibling (or DIETRY_CLOUD_DIR).
  • Never pass --build-number: it comes from pubspec.yaml, and desyncing it
    from the Play Store's high-water mark breaks uploads. See RELEASE.md.
EOF
}

do_deploy=0; do_run=0; do_bundle=1; do_clean=0; do_pub_get=1; do_logs=0
build_mode=release
device=''

[ $# -lt 3 ] && { usage; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
variant=$1; environment=$2; target=$3; shift 3

while [ $# -gt 0 ]; do
  case "$1" in
    --deploy)      do_deploy=1 ;;
    -r|--run)      do_run=1 ;;
    -d|--device)   device=${2:-}; [ -n "$device" ] || die "--device needs a serial"; shift ;;
    --no-bundle)   do_bundle=0 ;;
    --debug)       build_mode=debug ;;
    --clean)       do_clean=1 ;;
    --no-pub-get)  do_pub_get=0 ;;
    --logs)        do_logs=1 ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

case "$target" in
  web|linux|android) ;;
  *) die "target must be web, linux or android (got '$target')" ;;
esac
if [ "$target" != android ] && { [ "$do_run" = 1 ] || [ "$build_mode" = debug ]; }; then
  die "--run and --debug apply to the android target only"
fi
[ "$do_deploy" = 1 ] && [ "$target" != web ] && die "--deploy applies to the web target only"

dietry_resolve "$variant" "$environment"

info "Building $APP_NAME — $VARIANT/$BUILD_ENV, target $target"
info "  config   $CONFIG_FILE"
info "  commit   $GIT_HASH"

# Ask before touching production. The old build_and_release_all.sh published to
# the live site on its first line with nothing said about it.
if [ "$do_deploy" = 1 ]; then
  dietry_load_deploy
  info "  deploy   https://$DEPLOY_DOMAIN/"
  if [ "$BUILD_ENV" = prod ] && [ "${DIETRY_DEPLOY_YES:-0}" != 1 ]; then
    printf '%sThis publishes to PRODUCTION (%s). Type "deploy" to continue: %s' \
      "$_C_YEL" "$DEPLOY_DOMAIN" "$_C_OFF"
    read -r reply
    [ "$reply" = deploy ] || die "aborted — nothing was uploaded"
  fi
fi

dietry_activate_overrides
[ "$target" = android ] && {
  [ "$build_mode" = release ] && dietry_activate_signing required || dietry_activate_signing
}

[ "$do_pub_get" = 1 ] && run flutter pub get
[ "$do_clean" = 1 ] && run flutter clean

defines=(
  "--dart-define-from-file=$CONFIG_FILE"
  "--dart-define=GIT_HASH=$GIT_HASH"
  "--dart-define=BUILD_DATE=$BUILD_DATE"
)
tag=$(dietry_tag)
stem="dietry-$VARIANT-$BUILD_ENV-$tag"

case "$target" in

  web)
    run flutter build web --release --wasm "${defines[@]}"
    tarball="$REPO_ROOT/$stem.tar.bz2"
    rm -f -- "$tarball"
    run tar -C "$REPO_ROOT/build/web" -cjf "$tarball" .
    info "Web  $tarball"

    if [ "$do_deploy" = 1 ]; then
      remote_tmp="$REMOTE_STAGE/$(basename "$tarball")"
      run scp -P "$SSH_PORT" "$tarball" "$SSH_USER@$SSH_HOST:$REMOTE_STAGE/"
      run ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" \
        "mkdir -p '$REMOTE_ROOT/$DEPLOY_DOMAIN/' && \
         tar -C '$REMOTE_ROOT/$DEPLOY_DOMAIN/' -xjf '$remote_tmp' && \
         rm -f '$remote_tmp'"
      rm -f -- "$tarball"
      info "Deployed to https://$DEPLOY_DOMAIN/"
    fi
    ;;

  linux)
    run flutter build linux --release "${defines[@]}"
    tarball="$(dirname -- "$REPO_ROOT")/$stem-linux-x64.tar.gz"
    run tar -C "$REPO_ROOT/build/linux/x64/release/bundle" -czf "$tarball" .
    info "Linux  $tarball"
    ;;

  android)
    export ORG_GRADLE_PROJECT_edition="$EDITION"
    export ORG_GRADLE_PROJECT_appName="$APP_NAME"

    run flutter build apk "--$build_mode" "${defines[@]}"
    apk="build/app/outputs/flutter-apk/app-$build_mode.apk"
    [ -f "$REPO_ROOT/$apk" ] || die "expected APK not found at $apk"
    out_apk="$REPO_ROOT/$stem.apk"
    cp -- "$REPO_ROOT/$apk" "$out_apk"
    info "APK  $out_apk"

    if [ "$do_bundle" = 1 ] && [ "$build_mode" = release ]; then
      run flutter build appbundle --release "${defines[@]}"
      aab='build/app/outputs/bundle/release/app-release.aab'
      [ -f "$REPO_ROOT/$aab" ] || die "expected App Bundle not found at $aab"
      out_aab="$REPO_ROOT/$stem.aab"
      cp -- "$REPO_ROOT/$aab" "$out_aab"
      info "AAB  $out_aab"
    fi

    [ "$do_run" = 1 ] || exit 0

    serial=$(dietry_pick_device "$device")
    info "Installing on $serial"

    # Captured so the signature hint shows only when it actually applies.
    install_ok=1
    install_log=$(adb -s "$serial" install -r "$out_apk" 2>&1) || install_ok=0
    printf '%s\n' "$install_log"

    if [ "$install_ok" = 0 ]; then
      if printf '%s' "$install_log" |
           grep -qE 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match'; then
        die "the device already has $APP_ID signed with a different key.
  They cannot replace each other. Uninstall it first (this deletes that app's
  data on the device):
      adb -s $serial uninstall $APP_ID"
      fi
      die "adb install failed — see its output above."
    fi

    info "Launching $APP_ID"
    adb -s "$serial" shell am start -n "$APP_ID/com.sws.dietry.MainActivity" >/dev/null

    if [ "$do_logs" = 1 ]; then
      info "Tailing logs (Ctrl-C to stop)"
      adb -s "$serial" logcat --pid="$(adb -s "$serial" shell pidof -s "$APP_ID")" \
        2>/dev/null || warn "could not attach logcat (is the app still running?)"
    fi
    ;;
esac
