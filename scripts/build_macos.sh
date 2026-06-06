#!/usr/bin/env bash
# ============================================================
# Build ArcBench macOS desktop app (SwiftUI)
# Output: .build/release/ArcBenchDesktop
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DESKTOP_DIR="$PROJECT_DIR/arcbench_desktop"

echo "╔══════════════════════════════════════════╗"
echo "║     ArcBench macOS Desktop Build          ║"
echo "╚══════════════════════════════════════════╝"

cd "$DESKTOP_DIR"

echo "Building with Swift Package Manager..."
swift build -c release

echo ""
echo "Build complete!"
echo "Binary: $DESKTOP_DIR/.build/release/ArcBenchDesktop"
echo ""
echo "Run with: .build/release/ArcBenchDesktop"
echo ""
echo "To create a .app bundle, use:"
echo "  mkdir -p ArcBench.app/Contents/MacOS"
echo "  cp .build/release/ArcBenchDesktop ArcBench.app/Contents/MacOS/"
echo "  cp Info.plist ArcBench.app/Contents/"
echo "  open ArcBench.app"
