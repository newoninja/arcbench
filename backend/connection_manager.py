"""
ConnectionManager — WebSocket multiplexing brain for ArcBench.

One ConnectionManager per server. Tracks:
  - Every authenticated WebSocket (per-user, per-device)
  - Which terminals each socket is subscribed to
  - Heartbeat/keepalive per connection
  - Connection throttle enforcement (max 5 WS per user)
  - Broadcast routing: terminal output -> only subscribed sockets

The multiplex protocol lets a single WebSocket drive N terminals.
On reconnect, the client gets a full terminal list + replay buffers
so the UI can resume exactly where it left off.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import time
from dataclasses import dataclass, field
from typing import Optional

from fastapi import WebSocket, WebSocketDisconnect

from auth import get_ws_user
from middleware import ConnectionThrottle
from terminal_manager import TerminalManager
from agents.dispatcher import dispatch_spark, get_user_sparks, cancel_spark

logger = logging.getLogger("arcbench.connection")

# Heartbeat: server sends ping, expects pong within this window
HEARTBEAT_INTERVAL = 25  # seconds (under Tailscale's 30s idle timeout)
HEARTBEAT_TIMEOUT = 10   # seconds to wait for pong before disconnect


@dataclass
class ClientConnection:
    """Tracks a single authenticated WebSocket connection."""

    ws: WebSocket
    user_id: str
    username: str
    connected_at: float = field(default_factory=time.monotonic)
    last_pong: float = field(default_factory=time.monotonic)
    attached_terminals: set[str] = field(default_factory=set)

    @property
    def age_seconds(self) -> float:
        return time.monotonic() - self.connected_at


class ConnectionManager:
    """
    Central hub for all WebSocket connections.

    Responsibilities:
      1. Auth gate — validate JWT before accept
      2. Throttle — max N connections per user
      3. Heartbeat — detect dead sockets, clean up
      4. Multiplex dispatch — route client messages to TerminalManager
      5. Reconnect — on attach, ship the 100KB replay buffer
      6. Broadcast — terminal output fans out to all subscribed sockets
    """

    def __init__(
        self,
        terminal_manager: TerminalManager,
        throttle: ConnectionThrottle,
    ):
        self.tm = terminal_manager
        self.throttle = throttle

        # connection_id -> ClientConnection
        self._connections: dict[int, ClientConnection] = {}

        # Heartbeat background task
        self._heartbeat_task: Optional[asyncio.Task] = None
        self._running = False

    # -- Lifecycle --

    async def start(self):
        """Start the heartbeat background loop."""
        self._running = True
        self._heartbeat_task = asyncio.create_task(self._heartbeat_loop())
        logger.info("ConnectionManager started (heartbeat every %ds)", HEARTBEAT_INTERVAL)

    async def stop(self):
        """Stop heartbeat and close all connections."""
        self._running = False
        if self._heartbeat_task:
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                pass

        # Close all sockets
        for conn in list(self._connections.values()):
            try:
                await conn.ws.close(code=1001, reason="Server shutting down")
            except Exception:
                pass
        self._connections.clear()
        logger.info("ConnectionManager stopped, all connections closed")

    # -- Stats --

    @property
    def total_connections(self) -> int:
        return len(self._connections)

    def connections_for_user(self, user_id: str) -> list[ClientConnection]:
        return [c for c in self._connections.values() if c.user_id == user_id]

    def get_stats(self) -> dict:
        """Return connection stats for the /status endpoint."""
        users = set()
        terminal_subs = 0
        for conn in self._connections.values():
            users.add(conn.user_id)
            terminal_subs += len(conn.attached_terminals)
        return {
            "websocket_connections": self.total_connections,
            "unique_users_connected": len(users),
            "terminal_subscriptions": terminal_subs,
        }

    # -- Main handler (called from main.py WebSocket endpoint) --

    async def handle_multiplex(self, websocket: WebSocket, token: str):
        """
        Full lifecycle for a multiplexed WebSocket connection.

        1. Authenticate
        2. Throttle check
        3. Accept
        4. Send session_start (user info + terminal list)
        5. Message loop (dispatch to handlers)
        6. Cleanup on disconnect
        """
        # 1. Authenticate
        user = await get_ws_user(token)
        if not user:
            await websocket.close(code=4001, reason="Invalid token")
            return

        user_id = user["id"]
        username = user["username"]

        # 2. Throttle
        if not await self.throttle.acquire(user_id):
            await websocket.close(
                code=4029, reason="Too many connections (max 5)"
            )
            return

        # 3. Accept
        await websocket.accept()
        conn_id = id(websocket)
        conn = ClientConnection(ws=websocket, user_id=user_id, username=username)
        self._connections[conn_id] = conn

        logger.info(
            f"[{conn_id}] Connected: {username} "
            f"({self.total_connections} total, "
            f"{len(self.connections_for_user(user_id))} for this user)"
        )

        try:
            # 4. Send session_start with current terminal list
            terminals = self.tm.list_terminals(user_id)
            await _send(websocket, {
                "type": "session_start",
                "user_id": user_id,
                "username": username,
                "terminals": [t.to_info_dict() for t in terminals],
            })

            # 5. Message loop
            while True:
                raw = await websocket.receive_text()

                # Handle pong from client heartbeat
                if raw == "pong":
                    conn.last_pong = time.monotonic()
                    continue

                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    await _send(websocket, {"type": "error", "message": "Invalid JSON"})
                    continue

                await self._dispatch(conn, msg)

        except WebSocketDisconnect:
            logger.info(f"[{conn_id}] Disconnected: {username}")
        except Exception:
            logger.exception(f"[{conn_id}] Error for {username}")
        finally:
            # 6. Cleanup
            await self._cleanup(conn_id)

    # -- Message dispatch --

    async def _dispatch(self, conn: ClientConnection, msg: dict):
        """Route a client message to the appropriate handler."""
        msg_type = msg.get("type", "")

        try:
            handler = self._handlers.get(msg_type)
            if handler:
                await handler(self, conn, msg)
            else:
                await _send(conn.ws, {
                    "type": "error",
                    "message": f"Unknown message type: {msg_type}",
                })
        except Exception as e:
            logger.exception(f"Error handling '{msg_type}' for {conn.username}")
            await _send(conn.ws, {"type": "error", "message": str(e)})

    # -- Handlers --

    async def _on_create(self, conn: ClientConnection, msg: dict):
        terminal = await self.tm.create_terminal(
            user_id=conn.user_id,
            working_dir=msg.get("working_dir", "~"),
            cols=msg.get("cols", 120),
            rows=msg.get("rows", 40),
            command=msg.get("command", "claude"),
            shell_path=msg.get("shell_path"),
        )
        # Auto-attach creator
        terminal.subscribers.add(conn.ws)
        conn.attached_terminals.add(terminal.id)

        await _send(conn.ws, {
            "type": "created",
            "terminal_id": terminal.id,
            "working_dir": terminal.working_dir,
            "mode": terminal.mode.value,
            "command": terminal.command,
        })

    async def _on_attach(self, conn: ClientConnection, msg: dict):
        tid = msg.get("terminal_id", "")
        replay_data = self.tm.subscribe(tid, conn.user_id, conn.ws)

        if replay_data is None:
            await _send(conn.ws, {"type": "error", "message": f"Terminal {tid} not found"})
            return

        conn.attached_terminals.add(tid)
        terminal = self.tm.get_terminal(tid, conn.user_id)
        mode = terminal.mode.value if terminal else "unknown"

        encoded = base64.b64encode(replay_data).decode("ascii") if replay_data else ""
        await _send(conn.ws, {
            "type": "attached",
            "terminal_id": tid,
            "replay": encoded,
            "mode": mode,
            "buffer_bytes": len(replay_data) if replay_data else 0,
        })

    async def _on_detach(self, conn: ClientConnection, msg: dict):
        tid = msg.get("terminal_id", "")
        self.tm.unsubscribe(tid, conn.user_id, conn.ws)
        conn.attached_terminals.discard(tid)
        await _send(conn.ws, {"type": "detached", "terminal_id": tid})

    async def _on_input(self, conn: ClientConnection, msg: dict):
        tid = msg.get("terminal_id", "")
        data_b64 = msg.get("data", "")
        if not data_b64:
            return
        try:
            data = base64.b64decode(data_b64)
        except Exception:
            return
        self.tm.write_input(tid, conn.user_id, data)

    async def _on_resize(self, conn: ClientConnection, msg: dict):
        tid = msg.get("terminal_id", "")
        self.tm.resize_terminal(
            tid, conn.user_id, msg.get("cols", 120), msg.get("rows", 40)
        )

    async def _on_destroy(self, conn: ClientConnection, msg: dict):
        tid = msg.get("terminal_id", "")
        conn.attached_terminals.discard(tid)
        await self.tm.destroy_terminal(tid, conn.user_id)

    async def _on_list(self, conn: ClientConnection, msg: dict):
        terminals = self.tm.list_terminals(conn.user_id)
        await _send(conn.ws, {
            "type": "terminals",
            "list": [t.to_info_dict() for t in terminals],
        })

    async def _on_run_command(self, conn: ClientConnection, msg: dict):
        tid = msg.get("terminal_id", "")
        command = msg.get("command", "")
        if not command:
            await _send(conn.ws, {"type": "error", "message": "No command provided"})
            return
        ok = await self.tm.run_command(tid, conn.user_id, command)
        if ok:
            await _send(conn.ws, {
                "type": "command_sent",
                "terminal_id": tid,
                "command": command,
            })
        else:
            await _send(conn.ws, {"type": "error", "message": f"Failed to run command on {tid}"})

    async def _on_switch_mode(self, conn: ClientConnection, msg: dict):
        tid = msg.get("terminal_id", "")
        new_mode = msg.get("mode", "shell")
        if new_mode not in ("claude", "shell"):
            await _send(conn.ws, {"type": "error", "message": f"Invalid mode: {new_mode}"})
            return

        new_terminal = await self.tm.switch_mode(
            terminal_id=tid,
            user_id=conn.user_id,
            new_mode=new_mode,
            cols=msg.get("cols", 120),
            rows=msg.get("rows", 40),
            shell_path=msg.get("shell_path"),
        )
        if new_terminal:
            new_terminal.subscribers.add(conn.ws)
            conn.attached_terminals.discard(tid)
            conn.attached_terminals.add(new_terminal.id)
            await _send(conn.ws, {
                "type": "switched",
                "old_terminal_id": tid,
                "new_terminal_id": new_terminal.id,
                "mode": new_terminal.mode.value,
                "working_dir": new_terminal.working_dir,
            })
        else:
            await _send(conn.ws, {"type": "error", "message": f"Terminal {tid} not found"})

    async def _on_attach_all(self, conn: ClientConnection, msg: dict):
        """Attach to ALL of the user's terminals at once (reconnect shortcut)."""
        terminals = self.tm.list_terminals(conn.user_id)
        results = []
        for t in terminals:
            if not t.is_alive:
                continue
            replay = self.tm.subscribe(t.id, conn.user_id, conn.ws)
            conn.attached_terminals.add(t.id)
            results.append({
                "terminal_id": t.id,
                "mode": t.mode.value,
                "working_dir": t.working_dir,
                "replay": base64.b64encode(replay).decode("ascii") if replay else "",
                "buffer_bytes": len(replay) if replay else 0,
            })
        await _send(conn.ws, {"type": "attached_all", "terminals": results})

    async def _on_status(self, conn: ClientConnection, msg: dict):
        """Return connection-level stats."""
        await _send(conn.ws, {
            "type": "connection_status",
            "connection_age": round(conn.age_seconds, 1),
            "attached_terminals": list(conn.attached_terminals),
            **self.get_stats(),
        })

    async def _on_spark_idea(self, conn: ClientConnection, msg: dict):
        """Handle a spark idea submission from the mobile app."""
        idea = {
            "idea_id": msg.get("idea_id", ""),
            "content": msg.get("content", ""),
            "chip_label": msg.get("chip_label"),
        }
        if not idea["content"]:
            await _send(conn.ws, {"type": "error", "message": "Empty spark idea"})
            return

        async def notify_user(user_id: str, message: dict):
            """Push a message to all of this user's connected sockets."""
            for c in self._connections.values():
                if c.user_id == user_id:
                    await _send(c.ws, message)

        result = await dispatch_spark(
            idea=idea,
            user_id=conn.user_id,
            terminal_manager=self.tm,
            notify_callback=notify_user,
        )

        await _send(conn.ws, {
            "type": "spark_dispatched",
            **result,
        })

    async def _on_list_sparks(self, conn: ClientConnection, msg: dict):
        """Return all spark ideas for the user."""
        sparks = await get_user_sparks(conn.user_id)
        await _send(conn.ws, {
            "type": "spark_list",
            "sparks": sparks,
        })

    async def _on_spark_attach(self, conn: ClientConnection, msg: dict):
        """Attach to a spark's build terminal to watch live output."""
        spark_id = msg.get("spark_id", "")
        if not spark_id:
            await _send(conn.ws, {"type": "error", "message": "Missing spark_id"})
            return

        import database
        spark = await database.get_spark_by_id(spark_id)
        if not spark or spark["user_id"] != conn.user_id:
            await _send(conn.ws, {"type": "error", "message": "Spark not found"})
            return

        terminal_id = spark.get("terminal_id")
        if not terminal_id:
            await _send(conn.ws, {"type": "error", "message": "No terminal for this spark"})
            return

        # Reuse existing attach logic
        replay_data = self.tm.subscribe(terminal_id, conn.user_id, conn.ws)
        if replay_data is None:
            await _send(conn.ws, {"type": "error", "message": f"Terminal {terminal_id} not found"})
            return

        conn.attached_terminals.add(terminal_id)
        terminal = self.tm.get_terminal(terminal_id, conn.user_id)
        mode = terminal.mode.value if terminal else "unknown"

        encoded = base64.b64encode(replay_data).decode("ascii") if replay_data else ""
        await _send(conn.ws, {
            "type": "spark_attached",
            "spark_id": spark_id,
            "terminal_id": terminal_id,
            "replay": encoded,
            "mode": mode,
            "buffer_bytes": len(replay_data) if replay_data else 0,
        })

    async def _on_spark_cancel(self, conn: ClientConnection, msg: dict):
        """Cancel a running spark — kills its terminal."""
        spark_id = msg.get("spark_id", "")
        if not spark_id:
            await _send(conn.ws, {"type": "error", "message": "Missing spark_id"})
            return

        ok = await cancel_spark(spark_id, self.tm)
        if ok:
            await _send(conn.ws, {
                "type": "spark_status",
                "idea_id": spark_id,
                "status": "cancelled",
            })
            # Notify all connections for this user
            for c in self._connections.values():
                if c.user_id == conn.user_id and c is not conn:
                    await _send(c.ws, {
                        "type": "spark_status",
                        "idea_id": spark_id,
                        "status": "cancelled",
                    })
        else:
            await _send(conn.ws, {"type": "error", "message": "Spark not found"})

    # Handler dispatch table
    _handlers = {
        "create": _on_create,
        "attach": _on_attach,
        "attach_all": _on_attach_all,
        "detach": _on_detach,
        "input": _on_input,
        "resize": _on_resize,
        "destroy": _on_destroy,
        "list": _on_list,
        "run_command": _on_run_command,
        "switch_mode": _on_switch_mode,
        "status": _on_status,
        "spark_idea": _on_spark_idea,
        "list_sparks": _on_list_sparks,
        "spark_attach": _on_spark_attach,
        "spark_cancel": _on_spark_cancel,
    }

    # -- Heartbeat --

    async def _heartbeat_loop(self):
        """Send pings, disconnect clients that don't pong in time."""
        while self._running:
            try:
                await asyncio.sleep(HEARTBEAT_INTERVAL)
                now = time.monotonic()
                dead = []

                for conn_id, conn in self._connections.items():
                    # Check if last pong is too old
                    if now - conn.last_pong > HEARTBEAT_INTERVAL + HEARTBEAT_TIMEOUT:
                        logger.warning(
                            f"[{conn_id}] Heartbeat timeout for {conn.username}, disconnecting"
                        )
                        dead.append(conn_id)
                        continue

                    # Send ping
                    try:
                        await conn.ws.send_text("ping")
                    except Exception:
                        dead.append(conn_id)

                for conn_id in dead:
                    await self._cleanup(conn_id)

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Heartbeat loop error: {e}")

    # -- Cleanup --

    async def _cleanup(self, conn_id: int):
        """Remove a connection and release all its resources."""
        conn = self._connections.pop(conn_id, None)
        if not conn:
            return

        # Unsubscribe from all terminals
        self.tm.unsubscribe_all(conn.ws)

        # Release throttle slot
        await self.throttle.release(conn.user_id)

        # Close socket if still open
        try:
            await conn.ws.close()
        except Exception:
            pass

        logger.info(
            f"[{conn_id}] Cleaned up: {conn.username} "
            f"(was attached to {len(conn.attached_terminals)} terminals, "
            f"{self.total_connections} connections remain)"
        )

    # -- Broadcast helper (called from TerminalManager if needed) --

    async def broadcast_to_terminal(self, terminal_id: str, message: dict):
        """Send a message to all connections subscribed to a terminal."""
        for conn in self._connections.values():
            if terminal_id in conn.attached_terminals:
                await _send(conn.ws, message)


async def _send(ws: WebSocket, data: dict):
    """Safe WebSocket send — swallows disconnect errors."""
    try:
        await ws.send_json(data)
    except Exception:
        pass
