#!/bin/bash
# Run the app with credentials baked in.
#
# Usage:
#   ./run.sh                      # debug, auto-pick device
#   ./run.sh --profile            # profile mode
#   ./run.sh --release            # release mode
#   ./run.sh -d "iPhone 16"       # specific device, debug
#   ./run.sh --release -d "iPhone 16"
#   ./run.sh --mock-groups        # populated Groups tab for App Store screenshots
set -euo pipefail

source "$(dirname "$0")/.env"

MODE="--debug"
DEVICE=""
MOCK_GROUPS="false"

for arg in "$@"; do
  case "$arg" in
    --debug)   MODE="--debug"   ;;
    --profile) MODE="--profile" ;;
    --release) MODE="--release" ;;
    --mock-groups) MOCK_GROUPS="true" ;;
    -d)        ;;   # handled by shift below
    *)         DEVICE="$arg"   ;;
  esac
done

# Rebuild arg list cleanly
ARGS=("$MODE"
    "--dart-define=SUPABASE_URL=$SUPABASE_URL"
    "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
    "--dart-define=GOOGLE_SERVER_CLIENT_ID=${GOOGLE_SERVER_CLIENT_ID:-}"
    "--dart-define=IOS_REVERSED_CLIENT_ID=${IOS_REVERSED_CLIENT_ID:-}"
    "--dart-define=MOCK_GROUPS=$MOCK_GROUPS"
)
[ -n "$DEVICE" ] && ARGS+=(-d "$DEVICE")

flutter run "${ARGS[@]}"
