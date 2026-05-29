#!/bin/bash
# Run the app with credentials baked in.
# Usage: ./run.sh [device-id]
set -euo pipefail

source "$(dirname "$0")/.env"

flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  ${1:+-d "$1"}
