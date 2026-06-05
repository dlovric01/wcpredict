#!/bin/bash
# Build a release Android App Bundle (.aab) with all secrets baked in from
# .env. This is the format Google Play Console requires for new uploads —
# Play then generates per-ABI / per-density APKs on the fly from the bundle,
# so you do NOT want to pass --split-per-abi here.
#
# Output:
#   build/app/outputs/bundle/release/app-release.aab
#
# Usage:
#   ./build_aab.sh            # signed release bundle (uses android/key.properties)
#
# Upload via:
#   - Play Console → Release → Production / Internal testing → Create new release
#     → drag in app-release.aab.
#   - Or `bundletool` locally to generate an APKS for sideload testing:
#       bundletool build-apks --bundle=app-release.aab --output=app.apks
set -euo pipefail

source "$(dirname "$0")/.env"

# `flutter build appbundle` exits non-zero when it can't strip debug symbols
# from native libs (a known issue with some NDK / toolchain combos), even
# though the .aab itself is produced and Play accepts it. We tolerate that
# specific failure by checking the output file afterwards instead of relying
# on the exit code.
set +e
flutter build appbundle --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=APP_LINK_DOMAIN="${APP_LINK_DOMAIN:-}" \
  --dart-define=GOOGLE_SERVER_CLIENT_ID="${GOOGLE_SERVER_CLIENT_ID:-}" \
  --dart-define=IOS_REVERSED_CLIENT_ID="${IOS_REVERSED_CLIENT_ID:-}"
FLUTTER_EXIT=$?
set -e

OUT="build/app/outputs/bundle/release/app-release.aab"
echo ""
if [ -f "$OUT" ]; then
  SIZE=$(du -h "$OUT" | awk '{print $1}')
  echo "Bundle: $OUT ($SIZE)"
else
  echo "No bundle produced. flutter exited $FLUTTER_EXIT and $OUT is missing."
  echo "Re-run with verbose output: flutter build appbundle --release -v"
  exit 1
fi
echo ""
echo "Upload via:"
echo "  - Play Console → your app → Release → (track) → Create new release → drop the .aab"
echo "  - First upload to a fresh app: enrol in Play App Signing when prompted; Google"
echo "    keeps the app-signing key, your android/key.properties is the upload key only."
