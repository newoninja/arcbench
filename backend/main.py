"""
ArcBench v2 — Multi-user AI terminal remote control.
=====================================================
Spawns real PTY terminals running Claude Code CLI.
Tailscale-only transport. No public ports ever.
"""

from __future__ import annotations

import asyncio
import logging
import os
import signal
import time
from contextlib import asynccontextmanager
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from database import init_db, close_db
from terminal_manager import TerminalManager
from ws_handler import websocket_terminal
from middleware import RateLimitMiddleware, ConnectionThrottle
from connection_manager import ConnectionManager
from routes.auth_routes import router as auth_router
from routes.terminal_routes import router as terminal_router
from routes.status_routes import router as status_router
from routes.browse_routes import router as browse_router
from routes.spark_routes import router as spark_router
from routes.device_routes import router as device_router
from routes.computer_routes import router as computer_router

# -- Config --
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8000"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
TAILSCALE_ONLY = os.getenv("TAILSCALE_ONLY", "true").lower() == "true"

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("arcbench")

# -- Tailscale CGNAT range detection --
_TAILSCALE_PREFIXES = tuple(f"100.{i}." for i in range(64, 128)) + ("fd7a:115c:a1e0:",)
_LOCALHOST = ("127.0.0.1", "::1", "localhost")


def _is_tailscale_or_local(ip: str) -> bool:
    if ip in _LOCALHOST:
        return True
    return any(ip.startswith(p) for p in _TAILSCALE_PREFIXES)


# -- Terminal manager (global) --
terminal_manager = TerminalManager()
_start_time = time.monotonic()


def _asyncio_exception_handler(loop, context):
    """Catch unhandled exceptions in background tasks instead of crashing."""
    exc = context.get("exception")
    msg = context.get("message", "")
    logger.error(f"Unhandled async exception: {msg} — {exc}")


# -- Lifespan --
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("ArcBench v2 starting...")
    await init_db()
    app.state.terminal_manager = terminal_manager
    throttle = ConnectionThrottle(max_connections=5)
    app.state.connection_throttle = throttle
    app.state.start_time = _start_time

    # ConnectionManager — the multiplexing brain
    conn_mgr = ConnectionManager(terminal_manager, throttle)
    app.state.connection_manager = conn_mgr
    await conn_mgr.start()

    if TAILSCALE_ONLY:
        logger.info("Tailscale-only mode ENABLED")
    else:
        logger.warning("Tailscale-only mode DISABLED — accepting all connections")

    # Start the dead-PTY reaper background task
    await terminal_manager.start_reaper(interval=30)
    logger.info("Dead-PTY reaper started (every 30s)")

    # Catch unhandled exceptions in fire-and-forget tasks
    loop = asyncio.get_running_loop()
    loop.set_exception_handler(_asyncio_exception_handler)

    logger.info(f"Listening on {HOST}:{PORT}")
    yield
    logger.info("Shutting down — stopping reaper, killing all terminals...")
    await conn_mgr.stop()
    await terminal_manager.stop_reaper()
    await terminal_manager.shutdown_all()
    await close_db()


# -- App --
app = FastAPI(
    title="ArcBench",
    version="2.1.0",
    description="Multi-user AI terminal remote control — Tailscale only",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Rate limiting — 60 requests/minute per IP (skips WebSocket upgrades)
app.add_middleware(RateLimitMiddleware, max_requests=60, window_seconds=60)


# -- Tailscale gate middleware --
@app.middleware("http")
async def tailscale_gate(request: Request, call_next):
    if TAILSCALE_ONLY:
        client_ip = request.client.host if request.client else "unknown"
        if not _is_tailscale_or_local(client_ip):
            logger.warning(f"Blocked non-Tailscale connection from {client_ip}")
            return JSONResponse(
                status_code=403,
                content={"detail": "ArcBench requires Tailscale. Connect via your Tailscale IP."},
            )
    response: Response = await call_next(request)
    return response


def _check_tailscale_ws(websocket: WebSocket) -> bool:
    """Returns True if the WebSocket client should be allowed."""
    if not TAILSCALE_ONLY:
        return True
    client_ip = websocket.client.host if websocket.client else "unknown"
    return _is_tailscale_or_local(client_ip)


# -- Routes --
app.include_router(auth_router, prefix="/auth", tags=["auth"])
app.include_router(terminal_router, prefix="/terminals", tags=["terminals"])
app.include_router(status_router, tags=["status"])
app.include_router(browse_router, prefix="/browse", tags=["browse"])
app.include_router(spark_router, prefix="/sparks", tags=["sparks"])
app.include_router(device_router, prefix="/devices", tags=["devices"])
app.include_router(computer_router, prefix="/computer", tags=["computer"])


# -- Per-terminal WebSocket --
@app.websocket("/ws/{terminal_id}")
async def ws_terminal(websocket: WebSocket, terminal_id: str, token: str = Query("")):
    if not _check_tailscale_ws(websocket):
        await websocket.close(code=4003, reason="Tailscale required")
        return
    await websocket_terminal(websocket, terminal_id, token, terminal_manager)


# -- Multiplexed WebSocket (ConnectionManager-driven) --
@app.websocket("/ws")
async def ws_multiplex(websocket: WebSocket, token: str = Query("")):
    if not _check_tailscale_ws(websocket):
        await websocket.close(code=4003, reason="Tailscale required")
        return
    conn_mgr: ConnectionManager = websocket.app.state.connection_manager
    await conn_mgr.handle_multiplex(websocket, token)


# -- Web dashboard --
_static_dir = Path(__file__).parent / "static"


@app.get("/", include_in_schema=False)
async def serve_dashboard():
    index = _static_dir / "index.html"
    if index.exists():
        return FileResponse(index)
    return JSONResponse({"name": "ArcBench", "version": "2.1.0", "docs": "/docs"})


if _static_dir.exists():
    app.mount("/static", StaticFiles(directory=str(_static_dir)), name="static")


# -- Entry point --
if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=HOST,
        port=PORT,
        reload=False,
        log_level=LOG_LEVEL.lower(),
        ws_ping_interval=20,
        ws_ping_timeout=30,
    )
