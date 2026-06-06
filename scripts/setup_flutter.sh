#!/usr/bin/env bash
# ============================================================
# ArcBench — Flutter project setup
# Run this ONCE to generate platform files (android/, ios/, etc.)
# Then the lib/ and pubspec.yaml we already wrote will be used.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MOBILE_DIR="$PROJECT_DIR/arcbench_mobile"

echo "╔══════════════════════════════════════════╗"
echo "║     ArcBench Flutter Project Setup        ║"
echo "╚══════════════════════════════════════════╝"

# Check Flutter is available
if ! command -v flutter &>/dev/null; then
    echo ""
    echo "Flutter not found! Install it first:"
    echo "  macOS:   brew install --cask flutter"
    echo "  Manual:  https://docs.flutter.dev/get-started/install"
    echo ""
    echo "After installing, run this script again."
    exit 1
fi

echo "Flutter version:"
flutter --version
echo ""

cd "$MOBILE_DIR"

# Back up our custom files
echo "Backing up custom lib/ and pubspec.yaml..."
cp -r lib lib_backup
cp pubspec.yaml pubspec_backup.yaml
cp analysis_options.yaml analysis_options_backup.yaml

# Create Flutter project (generates android/, ios/, web/, test/, etc.)
echo "Running flutter create..."
flutter create --project-name arcbench_mobile --org com.arcbench .

# Restore our custom files (overwrite the generated ones)
echo "Restoring custom code..."
rm -rf lib
mv lib_backup lib
mv pubspec_backup.yaml pubspec.yaml
mv analysis_options_backup.yaml analysis_options.yaml

# Apply Android permissions
MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ]; then
    # Add RECORD_AUDIO permission if not present
    if ! grep -q "RECORD_AUDIO" "$MANIFEST"; then
        sed -i '' 's|<manifest|<manifest xmlns:tools="http://schemas.android.com/tools"|' "$MANIFEST" 2>/dev/null || true
        sed -i '' '/<application/i\
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\
    <uses-permission android:name="android.permission.INTERNET"/>\
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
' "$MANIFEST"
        echo "Added Android permissions to AndroidManifest.xml"
    fi
fi

# Set Android minSdkVersion to 21
BUILD_GRADLE="android/app/build.gradle"
if [ -f "$BUILD_GRADLE" ]; then
    sed -i '' 's/minSdkVersion .*/minSdkVersion 21/' "$BUILD_GRADLE" 2>/dev/null || true
    echo "Set Android minSdkVersion to 21"
fi

# Apply iOS permissions
INFO_PLIST="ios/Runner/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    if ! grep -q "NSSpeechRecognitionUsageDescription" "$INFO_PLIST"; then
        # Insert before closing </dict>
        sed -i '' '/<\/dict>/i\
	<key>NSSpeechRecognitionUsageDescription</key>\
	<string>ArcBench uses speech recognition to let you dictate coding prompts.</string>\
	<key>NSMicrophoneUsageDescription</key>\
	<string>ArcBench needs microphone access for voice input.</string>\
	<key>NSLocalNetworkUsageDescription</key>\
	<string>ArcBench connects to your desktop over Tailscale VPN.</string>
' "$INFO_PLIST"
        echo "Added iOS permissions to Info.plist"
    fi
fi

# Get dependencies
echo ""
echo "Getting Flutter dependencies..."
flutter pub get

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Setup complete!                         ║"
echo "║                                          ║"
echo "║  Run the app:                            ║"
echo "║    cd arcbench_mobile                     ║"
echo "║    flutter run                           ║"
echo "║                                          ║"
echo "║  Build release:                          ║"
echo "║    flutter build apk --release           ║"
echo "║    flutter build ios --release           ║"
echo "╚══════════════════════════════════════════╝"
