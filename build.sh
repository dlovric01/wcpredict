#!/bin/bash
# Build a release Android APK with all secrets baked in from .env.
#
# Direct-distribution build (not for Play Store). Splits per ABI so each
# user downloads only the slice they need (~18-22 MB vs. ~52 MB fat APK).
#
# Output:
#   build/app/outputs/flutter-apk/app-arm64-v8a-release.apk     ← real phones
#   build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk   ← old 32-bit
#   build/app/outputs/flutter-apk/app-x86_64-release.apk        ← emulators
#
# Usage:
#   ./build.sh              # split per ABI (recommended)
#   ./build.sh --universal  # single fat APK that runs everywhere (~52 MB)
#   ./build.sh --arm64      # arm64-only single APK (~22 MB, no emulators/old phones)
set -euo pipefail

source "$(dirname "$0")/.env"

MODE="--split-per-abi"
for arg in "$@"; do
  case "$arg" in
    --universal) MODE="" ;;
    --arm64)     MODE="--target-platform=android-arm64" ;;
    --split-per-abi) MODE="--split-per-abi" ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

flutter build apk --release $MODE \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_SERVER_CLIENT_ID="${GOOGLE_SERVER_CLIENT_ID:-}" \
  --dart-define=IOS_REVERSED_CLIENT_ID="${IOS_REVERSED_CLIENT_ID:-}"

echo ""
echo "APKs:"
ls -lh build/app/outputs/flutter-apk/*.apk 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'
echo ""
echo "Send users the arm64-v8a APK — that covers every phone made since 2017."
echo "Host it anywhere (Vercel, Cloudflare R2, plain HTTP) and share the link."
