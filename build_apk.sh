#!/bin/bash
# Build APK with credentials baked in.
#
# Usage:
#   ./build_apk.sh                  # debug APK
#   ./build_apk.sh --release        # release APK
#   ./build_apk.sh --profile        # profile APK
set -euo pipefail

source "$(dirname "$0")/.env"

MODE="--debug"

for arg in "$@"; do
  case "$arg" in
    --debug)   MODE="--debug"   ;;
    --profile) MODE="--profile" ;;
    --release) MODE="--release" ;;
  esac
done

ARGS=("$MODE"
    "--dart-define=SUPABASE_URL=$SUPABASE_URL"
    "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
    "--dart-define=GOOGLE_SERVER_CLIENT_ID=${GOOGLE_SERVER_CLIENT_ID:-}"
)

flutter build apk "${ARGS[@]}"
