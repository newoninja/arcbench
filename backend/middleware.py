"""
Rate limiting and connection throttling middleware for ArcBench.
In-memory only — no external dependencies.
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections import defaultdict, deque
from typing import Callable

from fastapi import Request, Response
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

logger = logging.getLogger("arcbench.middleware")

# ── Rate Limiter ──

class RateLimiter:
    """Simple in-memory sliding-window rate limiter keyed by IP."""

    def __init__(self, max_requests: int = 60, window_seconds: int = 60):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._last_cleanup = time.monotonic()
        self._cleanup_interval = 300  # purge stale entries every 5 min

    def is_allowed(self, key: str) -> bool:
        """Return True if the request is within the rate limit."""
        now = time.monotonic()
        self._maybe_cleanup(now)

        window = self._hits[key]
        # Drop timestamps outside the current window
        cutoff = now - self.window_seconds
        while window and window[0] <= cutoff:
            window.popleft()

        if len(window) >= self.max_requests:
            return False

        window.append(now)
        return True

    def _maybe_cleanup(self, now: float):
        """Periodically remove IPs with no recent activity."""
        if now - self._last_cleanup < self._cleanup_interval:
            return
        self._last_cleanup = now
        cutoff = now - self.window_seconds
        stale_keys = [
            k for k, dq in self._hits.items()
            if not dq or dq[-1] <= cutoff
        ]
        for k in stale_keys:
            del self._hits[k]
        if stale_keys:
            logger.debug(f"Rate limiter cleanup: removed {len(stale_keys)} stale entries")


class RateLimitMiddleware(BaseHTTPMiddleware):
    """FastAPI middleware that enforces per-IP rate limits on REST endpoints."""

    def __init__(self, app: ASGIApp, max_requests: int = 60, window_seconds: int = 60):
        super().__init__(app)
        self.limiter = RateLimiter(max_requests=max_requests, window_seconds=window_seconds)

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Skip rate limiting for WebSocket upgrade requests
        if request.headers.get("upgrade", "").lower() == "websocket":
            return await call_next(request)

        client_ip = request.client.host if request.client else "unknown"

        if not self.limiter.is_allowed(client_ip):
            logger.warning(f"Rate limit exceeded for {client_ip}")
            return JSONResponse(
                status_code=429,
                content={"detail": "Too many requests. Try again later."},
            )

        return await call_next(request)


# ── WebSocket Connection Throttle ──

class ConnectionThrottle:
    """Limits concurrent WebSocket connections per user."""

    def __init__(self, max_connections: int = 5):
        self.max_connections = max_connections
        self._counts: dict[str, int] = defaultdict(int)
        self._lock = asyncio.Lock()

    async def acquire(self, user_id: str) -> bool:
        """Try to acquire a connection slot. Returns True if allowed."""
        async with self._lock:
            if self._counts[user_id] >= self.max_connections:
                logger.warning(
                    f"WebSocket throttle: user {user_id} at max "
                    f"({self.max_connections} connections)"
                )
                return False
            self._counts[user_id] += 1
            return True

    async def release(self, user_id: str) -> None:
        """Release a connection slot."""
        async with self._lock:
            self._counts[user_id] = max(0, self._counts[user_id] - 1)
            if self._counts[user_id] == 0:
                del self._counts[user_id]
