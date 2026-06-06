# ArcBench — AI Coding Agent Remote Control

Control a full Claude-powered coding agent from your phone. Desktop does the heavy lifting (Aider + FastAPI), mobile is a clean remote with voice input, streaming diffs, and per-hunk approve/reject.

## Architecture

```
┌─────────────────────┐         Tailscale VPN         ┌──────────────────────┐
│  Desktop Host       │◄──────────────────────────────►│  Mobile App (Flutter)│
│  (FastAPI + Aider)  │  WebSocket + REST over         │  Voice → Prompt      │
│  - Runs 24/7        │  WireGuard mesh network        │  Stream responses    │
│  - Git per session  │  (zero config, encrypted)      │  Approve/reject diffs│
│  - Claude API calls │                                │  Offline queue       │
└─────────────────────┘                                └──────────────────────┘
```

## Quick Start

### 1. Desktop Setup (5 min)

```bash
# Clone
git clone https://github.com/yourusername/arcbench.git
cd arcbench

# Install Tailscale (if not already)
# macOS: brew install tailscale
# Linux: curl -fsSL https://tailscale.com/install.sh | sh
# Sign in and enable MagicDNS in the Tailscale admin console

# Configure
cp .env.example .env
# Edit .env:
#   ANTHROPIC_API_KEY=sk-ant-your-key-here
#   ARCBENCH_API_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
#   REPO_PATH=~/your-project

# Launch (creates venv, installs deps, starts server)
./scripts/start.sh
```

Server runs at `http://localhost:8000`. Swagger docs at `/docs`.

### 2. Phone Setup (3 min)

```bash
# Install Tailscale on your phone, sign in with same account
# Note your desktop's MagicDNS name from `tailscale status`

# Build and install the Flutter app
cd arcbench_mobile
flutter create .          # Generate platform files (run once)
flutter pub get
flutter run               # Or: flutter build apk --release
```

In the app:
1. Enter your desktop's MagicDNS hostname (e.g., `owens-macbook.tail1234.ts.net`)
2. Enter port `8000`
3. Enter the ARCBENCH_API_KEY from your .env
4. Tap Connect

### 3. Start Coding From Anywhere

- **Voice**: Hold the mic button → dictate → release to send
- **Text**: Tap keyboard icon → type → send
- **Review**: Expand diffs, approve/reject per file or all at once
- **Undo**: Tap undo to soft-reset the last commit

## Features

| Feature | ArcBench | Cursor Mobile |
|---------|---------|---------------|
| Voice-first input | Hold mic button | No |
| Streaming diffs | Real-time + syntax highlighted | Limited |
| Per-hunk approve/reject | Per-file with expand/collapse | No |
| Offline queue | Auto-sends when reconnected | No |
| Cost tracking | Per-prompt + per-session | No |
| Zero-config remote | Tailscale (WireGuard mesh) | Cloud-dependent |
| Git branches per session | Automatic | Manual |
| Token budget warnings | Configurable | No |
| Open source | MIT | Proprietary |

## Project Structure

```
arcbench/
├── .env.example              # Config template
├── .gitignore
├── LICENSE                   # MIT
├── README.md
├── backend/
│   ├── main.py               # FastAPI server (WebSocket + REST + Aider)
│   ├── requirements.txt      # Python deps
│   ├── tray_app.py           # System tray launcher (optional)
│   └── test_client.py        # Backend test script
├── arcbench_mobile/
│   ├── pubspec.yaml          # Flutter deps
│   ├── analysis_options.yaml
│   ├── lib/
│   │   ├── main.dart         # App entry point
│   │   ├── config/
│   │   │   ├── constants.dart
│   │   │   └── theme.dart    # Dark theme
│   │   ├── models/
│   │   │   ├── session.dart  # API models
│   │   │   └── message.dart  # Chat UI models
│   │   ├── providers/
│   │   │   ├── connection_provider.dart
│   │   │   ├── session_provider.dart
│   │   │   └── settings_provider.dart
│   │   ├── services/
│   │   │   ├── api_service.dart       # REST client
│   │   │   ├── websocket_service.dart # WS with auto-reconnect
│   │   │   ├── voice_service.dart     # STT + TTS
│   │   │   ├── storage_service.dart   # Secure + prefs storage
│   │   │   └── offline_queue.dart     # Queued prompts
│   │   ├── screens/
│   │   │   ├── connect_screen.dart
│   │   │   ├── sessions_screen.dart
│   │   │   ├── chat_screen.dart
│   │   │   └── settings_screen.dart
│   │   └── widgets/
│   │       ├── diff_viewer.dart       # Syntax-highlighted diffs
│   │       ├── message_bubble.dart    # Chat bubbles + markdown
│   │       ├── voice_button.dart      # Pulsing mic button
│   │       └── token_usage_bar.dart   # Progress bar + cost
│   ├── ios_permissions.md
│   └── android_permissions.md
└── scripts/
    ├── start.sh              # One-command desktop launch
    ├── build_desktop.sh      # PyInstaller build
    ├── build_mobile.sh       # Flutter build (APK + iOS)
    ├── arcbench.plist          # macOS LaunchAgent
    └── arcbench.service        # Linux systemd service
```

## API Reference

### REST Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/status` | Health check + server info |
| GET | `/sessions` | List all sessions |
| POST | `/sessions` | Create new session (auto-branches git) |
| GET | `/sessions/{id}` | Session detail + message history |
| POST | `/sessions/{id}/apply` | Commit pending changes |
| POST | `/sessions/{id}/reject` | Revert pending changes |
| POST | `/sessions/{id}/undo` | Soft-reset last commit |
| GET | `/usage` | Token usage + cost breakdown |

All REST endpoints require `X-API-Key` header.

### WebSocket Protocol

Connect: `ws://host:8000/ws?api_key=YOUR_KEY`

```jsonc
// Client → Server
{"type": "prompt",  "session_id": "abc", "content": "Add auth"}
{"type": "apply",   "session_id": "abc", "file_paths": null}     // null = all
{"type": "reject",  "session_id": "abc", "file_paths": ["x.py"]}
{"type": "undo",    "session_id": "abc"}

// Server → Client
{"type": "stream",   "session_id": "abc", "content": "line..."}
{"type": "complete", "session_id": "abc", "pending_changes": [...], "token_usage": {...}}
{"type": "ack",      "action": "applied", "files": [...], "commit_sha": "abc123"}
{"type": "error",    "message": "Something went wrong"}
```

## Security

- **Network**: Tailscale WireGuard mesh VPN — traffic never touches the public internet
- **Auth**: App-level API key validated on every request (secure comparison)
- **Storage**: API keys stored in platform keychain (flutter_secure_storage)
- **Git**: Each session gets its own branch — main branch is never touched
- **No exposure**: Server binds to 0.0.0.0 but is only reachable via Tailscale

### Security Checklist

- [ ] Set strong ARCBENCH_API_KEY (use `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`)
- [ ] Enable Tailscale ACLs to restrict which devices can reach your desktop
- [ ] Never commit .env to git
- [ ] Enable biometric lock on your phone (flutter_secure_storage uses keychain)
- [ ] Set a token budget to prevent runaway costs

## Cost Tracking

Based on March 2026 Claude pricing:

| Model | Input | Output |
|-------|-------|--------|
| Sonnet | $3/M tokens | $15/M tokens |
| Opus | $15/M tokens | $75/M tokens |

Estimated cost shown per-prompt and per-session in the app.

## Running as a Background Service

### macOS (LaunchAgent)
```bash
cp scripts/arcbench.plist ~/Library/LaunchAgents/com.arcbench.host.plist
launchctl load ~/Library/LaunchAgents/com.arcbench.host.plist
# Logs: /tmp/arcbench.stdout.log
```

### Linux (systemd)
```bash
sudo cp scripts/arcbench.service /etc/systemd/system/arcbench.service
sudo systemctl daemon-reload
sudo systemctl enable --now arcbench
# Logs: journalctl -u arcbench -f
```

### Desktop Tray App
```bash
pip install pystray Pillow
python backend/tray_app.py
# Adds system tray icon — click to open dashboard, restart/stop server
```

## License

MIT — see [LICENSE](LICENSE).


## API keys / configuration

This repository ships with **placeholder credentials only** — no real keys are committed.
To run it, supply your own API key(s) by replacing the `YOUR_*_API_KEY` placeholders in the
source (or wiring them to the matching environment variable / Keychain). Never commit real keys.
