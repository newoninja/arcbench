"""Status and health endpoints."""

import socket
import time
import psutil
from fastapi import APIRouter, Request
from models import StatusResponse
import database

router = APIRouter()


@router.get("/status", response_model=StatusResponse)
async def get_status(request: Request):
    """Server health check — no auth required."""
    tm = request.app.state.terminal_manager
    start = request.app.state.start_time
    proc = psutil.Process()
    user_count = await database.count_users()
    # Connection stats from ConnectionManager
    conn_stats = {}
    conn_mgr = getattr(request.app.state, "connection_manager", None)
    if conn_mgr:
        conn_stats = conn_mgr.get_stats()

    return StatusResponse(
        hostname=socket.gethostname(),
        active_terminals=len(tm._terminals),
        total_users=user_count,
        uptime_seconds=round(time.monotonic() - start, 1),
        cpu_percent=proc.cpu_percent(),
        memory_mb=round(proc.memory_info().rss / 1024 / 1024, 1),
        **conn_stats,
    )


@router.get("/health")
async def health():
    """Simple health check."""
    return {"status": "ok"}
