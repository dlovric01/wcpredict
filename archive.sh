#!/bin/bash
# Build a release iOS archive with all secrets baked in from .env.
#
# Output:
#   build/ios/ipa/wcpredict.ipa    — upload via Transporter / altool
#   build/ios/archive/Runner.xcarchive — open in Xcode Organizer
#
# Usage:
#   ./archive.sh              # build .ipa (App Store distribution)
#   ./archive.sh --no-codesign # archive without signing (CI/inspection)
set -euo pipefail

source "$(dirname "$0")/.env"

EXTRA=()
for arg in "$@"; do
  case "$arg" in
    --no-codesign) EXTRA+=(--no-codesign) ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

flutter build ipa --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_SERVER_CLIENT_ID="${GOOGLE_SERVER_CLIENT_ID:-}" \
  --dart-define=IOS_REVERSED_CLIENT_ID="${IOS_REVERSED_CLIENT_ID:-}" \
  ${EXTRA[@]+"${EXTRA[@]}"}

echo ""
echo "Archive: build/ios/archive/Runner.xcarchive"
echo "IPA:     build/ios/ipa/"
echo ""
echo "Upload via:"
echo "  - Xcode → Window → Organizer → select archive → Distribute App"
echo "  - or: open Transporter.app and drag the .ipa in"
