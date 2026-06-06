#!/usr/bin/env bash
# ============================================================
# Build desktop distributable via PyInstaller
# Output: dist/arcbench (single executable)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"
source .venv/bin/activate

pip install -q pyinstaller

echo "Building ArcBench desktop executable..."
pyinstaller \
  --name arcbench \
  --onefile \
  --add-data "backend/main.py:backend" \
  --add-data ".env.example:.env.example" \
  --hidden-import uvicorn.logging \
  --hidden-import uvicorn.protocols.http \
  --hidden-import uvicorn.protocols.websockets \
  --hidden-import uvicorn.lifespan.on \
  backend/main.py

echo ""
echo "Build complete: dist/arcbench"
echo "Run with: ./dist/arcbench"
