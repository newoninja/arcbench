#!/usr/bin/env bash
# ============================================================
# ArcBench — One-command launch script
# Systemd-ready: logs to stdout/stderr (journalctl compatible)
# Usage: ./scripts/start.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_DIR/backend"
VENV_DIR="$PROJECT_DIR/.venv"

# Systemd-friendly: no fancy box if running under systemd
if [ -z "${INVOCATION_ID:-}" ]; then
    echo "========================================"
    echo "  ArcBench Desktop Host"
    echo "========================================"
fi

# Ensure .env exists
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "ERROR: .env file not found. Copy .env.example to .env and fill in your keys." >&2
    echo "  cp $PROJECT_DIR/.env.example $PROJECT_DIR/.env" >&2
    exit 1
fi

# Create venv if missing
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# Activate and install deps
source "$VENV_DIR/bin/activate"
echo "Installing/updating dependencies..."
pip install -q -r "$BACKEND_DIR/requirements.txt"

# Check claude CLI is available
if ! command -v claude &>/dev/null; then
    echo "WARNING: 'claude' CLI not found in PATH. Terminals will fail to spawn." >&2
fi

# Check grok CLI for auto-review (optional)
if command -v grok &>/dev/null; then
    echo "Grok CLI found — auto-review enabled for spark builds"
else
    echo "NOTE: 'grok' CLI not found — Claude will handle spark reviews instead"
fi

# Create builds directory for spark agents
mkdir -p "$HOME/arcbench-builds"

# Launch — unbuffered output for journalctl
echo "Starting ArcBench server..."
echo "Swagger docs: http://localhost:${PORT:-8000}/docs"
echo ""

cd "$BACKEND_DIR"
exec python -u main.py
