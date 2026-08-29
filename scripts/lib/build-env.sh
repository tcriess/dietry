# shellcheck shell=bash
#
# Shared setup for the Android scripts. Source it; do not execute it.
#
# Resolves the two things that differ between builds — which edition and which
# backend — into the exact set of flags .github/workflows/build.yml passes, so
# a local build is the same build CI makes:
#
#   config/<variant>.json          --dart-define-from-file
#   ORG_GRADLE_PROJECT_edition     picks the applicationId in app/build.gradle
#   ORG_GRADLE_PROJECT_appName     the visible launcher label
#
# It also guards the pubspec trap described in RELEASE.md: with
# pubspec_overrides.yaml present, any flutter command rewrites pubspec.lock to
# resolve dietry_cloud to ../dietry-cloud, and that lock must never be
# committed to CE. Both files are restored on exit, however the script ends.

set -uo pipefail

# ── Output ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  _C_RED=$'\033[31m'; _C_YEL=$'\033[33m'; _C_CYA=$'\033[36m'
  _C_DIM=$'\033[2m';  _C_OFF=$'\033[0m'
else
  _C_RED=''; _C_YEL=''; _C_CYA=''; _C_DIM=''; _C_OFF=''
fi

info() { printf '%s==>%s %s\n' "$_C_CYA" "$_C_OFF" "$*"; }
warn() { printf '%swarning:%s %s\n' "$_C_YEL" "$_C_OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n'   "$_C_RED" "$_C_OFF" "$*" >&2; exit 1; }
run()  { printf '%s$ %s%s\n' "$_C_DIM" "$*" "$_C_OFF"; "$@"; }

# ── Locations ────────────────────────────────────────────────────────────────
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# The cloud package is expected as a sibling checkout, matching the path in
# dietry.pubspec_overrides.yaml.cloud. Override for a checkout kept elsewhere.
CLOUD_DIR=${DIETRY_CLOUD_DIR:-$(dirname -- "$REPO_ROOT")/dietry-cloud}

# ── Restoration ──────────────────────────────────────────────────────────────
_lock_backup=''
_overrides_backup=''
_overrides_existed=0
_keyprops_backup=''
_keyprops_existed=0
_restored=0

dietry_restore() {
  [ "$_restored" = 1 ] && return 0
  _restored=1

  if [ -n "$_lock_backup" ] && [ -f "$_lock_backup" ]; then
    if ! cmp -s "$_lock_backup" "$REPO_ROOT/pubspec.lock"; then
      cp -- "$_lock_backup" "$REPO_ROOT/pubspec.lock"
      info "Restored pubspec.lock (the build had rewritten it)"
    fi
    rm -f -- "$_lock_backup"
  fi

  if [ "$_overrides_existed" = 1 ]; then
    [ -n "$_overrides_backup" ] && [ -f "$_overrides_backup" ] &&
      mv -f -- "$_overrides_backup" "$REPO_ROOT/pubspec_overrides.yaml"
  else
    rm -f -- "$REPO_ROOT/pubspec_overrides.yaml"
  fi

  # key.properties holds passwords and names one variant's keystore. Leaving it
  # behind would both scatter a secret and silently sign an IDE build of a
  # different variant with the wrong key.
  if [ "$_keyprops_existed" = 1 ]; then
    [ -n "$_keyprops_backup" ] && [ -f "$_keyprops_backup" ] &&
      mv -f -- "$_keyprops_backup" "$REPO_ROOT/android/key.properties"
  else
    rm -f -- "$REPO_ROOT/android/key.properties"
  fi
}
trap dietry_restore EXIT INT TERM

# ── Argument parsing ─────────────────────────────────────────────────────────
# dietry_resolve <ce|cloud> <dev|prod>
#
# Exports VARIANT, BUILD_ENV, EDITION, APP_ID, APP_NAME, CONFIG_FILE, GIT_HASH,
# BUILD_DATE and copies the right config into place.
dietry_resolve() {
  VARIANT=${1:-}
  BUILD_ENV=${2:-}

  case "$VARIANT" in
    ce|cloud) ;;
    *) die "variant must be 'ce' or 'cloud' (got '${VARIANT:-nothing}')" ;;
  esac
  case "$BUILD_ENV" in
    dev|prod) ;;
    *) die "environment must be 'dev' or 'prod' (got '${BUILD_ENV:-nothing}')" ;;
  esac

  command -v flutter >/dev/null 2>&1 ||
    die "flutter is not on PATH — install the Flutter SDK first"
  [ -f "$REPO_ROOT/pubspec.yaml" ] ||
    die "$REPO_ROOT does not look like the dietry checkout (no pubspec.yaml)"

  local src
  if [ "$VARIANT" = cloud ]; then
    EDITION=cloud
    APP_ID=de.dietry.app
    [ "$BUILD_ENV" = prod ] && APP_NAME='Dietry' || APP_NAME='Dietry Dev'
    # Cloud configs live in the private repo; they are not in this checkout.
    src="$CLOUD_DIR/config/cloud-$BUILD_ENV.json"
    CONFIG_FILE='config/cloud.json'
    [ -d "$CLOUD_DIR" ] || die "cloud checkout not found at $CLOUD_DIR
  Clone dietry-cloud as a sibling of this repo, or set DIETRY_CLOUD_DIR."
  else
    EDITION=community
    APP_ID=de.dietry.community
    [ "$BUILD_ENV" = prod ] && APP_NAME='Dietry CE' || APP_NAME='Dietry CE Dev'
    src="$REPO_ROOT/config/ce-$BUILD_ENV.json"
    CONFIG_FILE='config/ce.json'
  fi

  [ -f "$src" ] || die "config not found: $src
  config/*.json is gitignored — copy it from the .example and fill it in."

  cp -- "$src" "$REPO_ROOT/$CONFIG_FILE"

  # A config whose EDITION disagrees with the variant would silently build the
  # other app: build.gradle derives the applicationId from -Pedition, so the
  # result installs alongside (or over) the wrong one.
  local cfg_edition cfg_env
  cfg_edition=$(jq -r '.EDITION // empty' "$REPO_ROOT/$CONFIG_FILE")
  cfg_env=$(jq -r '.ENVIRONMENT // empty' "$REPO_ROOT/$CONFIG_FILE")
  [ "$cfg_edition" = "$EDITION" ] ||
    die "$src declares EDITION='$cfg_edition' but variant '$VARIANT' needs '$EDITION'"

  local want_env
  [ "$BUILD_ENV" = prod ] && want_env=production || want_env=development
  [ "$cfg_env" = "$want_env" ] ||
    die "$src declares ENVIRONMENT='$cfg_env' but '$BUILD_ENV' needs '$want_env'
  Refusing to build: this is how a 'prod' build ends up pointing at the dev database."

  # Mirrors CI: the hash identifies the repo the edition's code came from.
  if [ "$VARIANT" = cloud ]; then
    GIT_HASH=$(git -C "$CLOUD_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
  else
    GIT_HASH=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
  fi
  BUILD_DATE=$(date -u +%Y-%m-%d)

  export VARIANT BUILD_ENV EDITION APP_ID APP_NAME CONFIG_FILE GIT_HASH BUILD_DATE
}

# ── Package override ─────────────────────────────────────────────────────────
# Points dietry_cloud at ../dietry-cloud for a cloud build, and makes sure a
# leftover override cannot leak the private package into a CE build.
dietry_activate_overrides() {
  cd -- "$REPO_ROOT" || die "cannot cd to $REPO_ROOT"

  if [ -f pubspec.lock ]; then
    _lock_backup=$(mktemp -t dietry-pubspec-lock.XXXXXX)
    cp -- pubspec.lock "$_lock_backup"
  fi

  if [ -f pubspec_overrides.yaml ]; then
    _overrides_existed=1
    _overrides_backup=$(mktemp -t dietry-overrides.XXXXXX)
    cp -- pubspec_overrides.yaml "$_overrides_backup"
  fi

  if [ "$VARIANT" = cloud ]; then
    local tmpl="$CLOUD_DIR/dietry.pubspec_overrides.yaml.cloud"
    [ -f "$tmpl" ] || die "cloud override template not found: $tmpl"
    cp -- "$tmpl" pubspec_overrides.yaml
    info "Cloud package linked from $CLOUD_DIR"
  else
    # Without this a stale override from a previous cloud build would compile
    # the private package into a community build.
    rm -f -- pubspec_overrides.yaml
    info "Community build — using the stub at packages/dietry_cloud"
  fi
}

# ── Signing ──────────────────────────────────────────────────────────────────
# app/build.gradle reads one fixed file, rootProject.file('key.properties'), so
# the per-variant keystores have to be selected into that name for the build.
# Each android/key-<variant>-<env>.properties names its own .jks in android/app.
# Restored (removed) on exit — see dietry_restore.
#
# Without a match, build.gradle falls back to the debug signing config: still
# installable on your own device, but not shippable, and it cannot replace an
# install signed with the release key.
# Pass "required" for a release build: a missing keystore then fails the build
# rather than quietly producing a debug-signed APK that looks releasable.
dietry_activate_signing() {
  local required=${1:-optional}
  local src="$REPO_ROOT/android/key-$VARIANT-$BUILD_ENV.properties"
  local dest="$REPO_ROOT/android/key.properties"

  if [ -f "$dest" ]; then
    _keyprops_existed=1
    _keyprops_backup=$(mktemp -t dietry-keyprops.XXXXXX)
    cp -- "$dest" "$_keyprops_backup"
  fi

  if [ ! -f "$src" ]; then
    if [ "$required" = required ]; then
      die "missing $src
  A release build must not fall back to the debug key: the APK would look
  shippable, would not be, and could not replace a release-signed install.
  Set DIETRY_ALLOW_DEBUG_SIGNING=1 to build one deliberately anyway."
    fi
    warn "no $(basename "$src") — signing with the debug key."
    rm -f -- "$dest"
    return 0
  fi

  local store
  store=$(sed -n 's/^storeFile=//p' "$src" | head -1)
  [ -n "$store" ] || die "$src has no storeFile= line"
  [ -f "$REPO_ROOT/android/app/$store" ] ||
    die "$src names a keystore that is not there: android/app/$store"

  cp -- "$src" "$dest"
  chmod 600 -- "$dest"
  info "Signing with $(basename "$src") (keystore $store)"
}

# ── Artifact naming ──────────────────────────────────────────────────────────
# The tag artifacts are named after. Versions are kept in lockstep across the
# two repos (RELEASE.md), so this repo's tag describes a cloud build too.
dietry_tag() {
  git -C "$REPO_ROOT" describe --tags --abbrev=1 2>/dev/null || echo 0.0.1
}

# ── Web deploy target ────────────────────────────────────────────────────────
# The public hostname is derived here; the server behind it is not. Those
# details live in config/deploy.env (gitignored) or the environment, so this
# tracked script carries no infrastructure of yours.
#
# Sets DEPLOY_DOMAIN, plus SSH_HOST/SSH_USER/SSH_PORT/REMOTE_STAGE/REMOTE_ROOT.
dietry_load_deploy() {
  [ "$BUILD_ENV" = prod ] &&
    DEPLOY_DOMAIN="$VARIANT.dietry.de" ||
    DEPLOY_DOMAIN="$VARIANT-$BUILD_ENV.dietry.de"

  local env_file="$REPO_ROOT/config/deploy.env"
  # shellcheck disable=SC1090
  [ -f "$env_file" ] && source "$env_file"

  SSH_HOST=${DIETRY_DEPLOY_HOST:-${SSH_HOST:-}}
  SSH_USER=${DIETRY_DEPLOY_USER:-${SSH_USER:-}}
  SSH_PORT=${DIETRY_DEPLOY_PORT:-${SSH_PORT:-22}}
  REMOTE_STAGE=${DIETRY_DEPLOY_STAGE:-${REMOTE_STAGE:-}}
  REMOTE_ROOT=${DIETRY_DEPLOY_ROOT:-${REMOTE_ROOT:-}}

  local missing=()
  [ -n "$SSH_HOST" ]     || missing+=(SSH_HOST)
  [ -n "$SSH_USER" ]     || missing+=(SSH_USER)
  [ -n "$REMOTE_STAGE" ] || missing+=(REMOTE_STAGE)
  [ -n "$REMOTE_ROOT" ]  || missing+=(REMOTE_ROOT)
  if [ ${#missing[@]} -gt 0 ]; then
    die "deploy is not configured — missing: ${missing[*]}
  Copy config/deploy.env.example to config/deploy.env and fill it in.
  That file is gitignored; this repository is public, so the server it names
  must never be committed."
  fi

  export DEPLOY_DOMAIN SSH_HOST SSH_USER SSH_PORT REMOTE_STAGE REMOTE_ROOT
}

# ── Devices ──────────────────────────────────────────────────────────────────
# Echoes the serial to use, or dies with the list when the choice is ambiguous.
dietry_pick_device() {
  local requested=${1:-}
  command -v adb >/dev/null 2>&1 ||
    die "adb is not on PATH — install the Android platform tools"

  adb start-server >/dev/null 2>&1 || true

  local devices=()
  while IFS=$'\t' read -r serial state; do
    [ "$state" = device ] && devices+=("$serial")
  done < <(adb devices | tail -n +2 | tr -d '\r' | grep -v '^$')

  if [ -n "$requested" ]; then
    local d
    for d in ${devices+"${devices[@]}"}; do
      [ "$d" = "$requested" ] && { printf '%s\n' "$requested"; return 0; }
    done
    die "device '$requested' is not connected (adb devices: ${devices[*]:-none})"
  fi

  case ${#devices[@]} in
    0) die "no Android device connected. Plug one in, enable USB debugging, and
  accept the authorisation prompt on the device (check with: adb devices)." ;;
    1) printf '%s\n' "${devices[0]}"; return 0 ;;
    *) die "several devices connected — pick one with --device:
  ${devices[*]}" ;;
  esac
}
