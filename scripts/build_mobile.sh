#!/usr/bin/env bash
# ============================================================
# Build Flutter mobile app for Android and iOS
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MOBILE_DIR="$PROJECT_DIR/arcbench_mobile"

cd "$MOBILE_DIR"

echo "╔══════════════════════════════════════════╗"
echo "║       ArcBench Mobile Build               ║"
echo "╚══════════════════════════════════════════╝"

echo ""
echo "Getting dependencies..."
flutter pub get

echo ""
echo "=== Android APK ==="
flutter build apk --release
echo "APK: build/app/outputs/flutter-apk/app-release.apk"

echo ""
echo "=== Android App Bundle (Play Store) ==="
flutter build appbundle --release
echo "AAB: build/app/outputs/bundle/release/app-release.aab"

# iOS only on macOS
if [[ "$(uname)" == "Darwin" ]]; then
  echo ""
  echo "=== iOS ==="
  flutter build ios --release --no-codesign
  echo "To upload to TestFlight, open ios/Runner.xcworkspace in Xcode"
fi

echo ""
echo "Build complete!"
