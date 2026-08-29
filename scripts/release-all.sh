#!/usr/bin/env bash
#
# Build every edition × environment × target combination.
#
# Replaces the old untracked build_and_release_all.sh, whose first line
# published to the live site with nothing said about it. Here the web deploy is
# opt-in (--deploy), production is confirmed once up front rather than per
# build, and a failure reports which combination broke instead of the chain
# simply stopping.
#
set -euo pipefail

# shellcheck source=lib/build-env.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/build-env.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/release-all.sh [options]

Builds ce and cloud, dev and prod, for web, linux and android — 12 builds.

Options:
      --deploy        also publish each web build to its host (asks once for
                      production). Without this, nothing leaves the machine.
      --only LIST     comma-separated targets, e.g. --only android,web
      --env LIST      comma-separated environments, e.g. --env prod
      --edition LIST  comma-separated editions, e.g. --edition cloud
      --clean         flutter clean before each build (the old script always
                      did; 12 clean builds take a long time)
      --keep-going    carry on after a failure and report them all at the end
  -h, --help          show this
EOF
}

do_deploy=0; do_clean=0; keep_going=0
editions=(ce cloud); envs=(prod dev); targets=(web linux android)

split() { printf '%s' "$1" | tr ',' ' '; }

while [ $# -gt 0 ]; do
  case "$1" in
    --deploy)     do_deploy=1 ;;
    --clean)      do_clean=1 ;;
    --keep-going) keep_going=1 ;;
    --only)       read -r -a targets  <<<"$(split "${2:-}")"; shift ;;
    --env)        read -r -a envs     <<<"$(split "${2:-}")"; shift ;;
    --edition)    read -r -a editions <<<"$(split "${2:-}")"; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

builder="$REPO_ROOT/scripts/build.sh"
[ -x "$builder" ] || die "not found or not executable: $builder"

# Confirm production once, here, rather than letting each web build ask.
if [ "$do_deploy" = 1 ]; then
  for e in ${envs+"${envs[@]}"}; do
    [ "$e" = prod ] || continue
    for ed in ${editions+"${editions[@]}"}; do
      printf '  will publish https://%s.dietry.de/\n' "$ed"
    done
    printf '%sThis publishes to PRODUCTION. Type "deploy" to continue: %s' \
      "$_C_YEL" "$_C_OFF"
    read -r reply
    [ "$reply" = deploy ] || die "aborted — nothing was uploaded"
    export DIETRY_DEPLOY_YES=1   # already confirmed; don't ask 2× per build
    break
  done
fi

opts=()
[ "$do_clean" = 1 ] && opts+=(--clean)

failures=()
total=0
for edition in "${editions[@]}"; do
  for environment in "${envs[@]}"; do
    for target in "${targets[@]}"; do
      total=$((total + 1))
      combo="$edition/$environment/$target"
      extra=()
      [ "$target" = web ] && [ "$do_deploy" = 1 ] && extra+=(--deploy)

      printf '\n%s══ %s ══%s\n' "$_C_CYA" "$combo" "$_C_OFF"
      if "$builder" "$edition" "$environment" "$target" \
           ${opts+"${opts[@]}"} ${extra+"${extra[@]}"}; then
        continue
      fi
      failures+=("$combo")
      [ "$keep_going" = 1 ] || die "$combo failed — stopping (use --keep-going to carry on)"
    done
  done
done

printf '\n'
if [ ${#failures[@]} -eq 0 ]; then
  info "All $total builds succeeded"
else
  warn "${#failures[@]} of $total failed: ${failures[*]}"
  exit 1
fi
