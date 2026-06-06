"""
WebSocket handler — per-terminal and multiplexed terminal I/O for ArcBench.
Supports Claude Code and Shell modes with run_command and switch_mode.
"""

from __future__ import annotations

import base64
import json
import logging

from fastapi import WebSocket, WebSocketDisconnect

from auth import get_ws_user
from terminal_manager import TerminalManager

logger = logging.getLogger("arcbench.ws")


async def websocket_terminal(
    websocket: WebSocket,
    terminal_id: str,
    token: str,
    terminal_manager: TerminalManager,
):
    """
    Per-terminal WebSocket endpoint.
    Endpoint: /ws/{terminal_id}?token=<jwt>

    On connect: authenticate, subscribe to terminal, send replay buffer.

    Client -> Server (JSON text frames):
      {"type": "input", "data": "<base64>"}
      {"type": "resize", "cols": 120, "rows": 40}
      {"type": "run_command", "command": "ls -la"}

    Server -> Client (JSON text frames):
      {"type": "output", "terminal_id": "abc123", "data": "<base64>"}
      {"type": "replay", "terminal_id": "abc123", "data": "<base64>"}
      {"type": "terminated", "terminal_id": "abc123"}
      {"type": "command_sent", "terminal_id": "abc123", "command": "..."}
      {"type": "error", "message": "..."}
    """
    # Authenticate
    user = await get_ws_user(token)
    if not user:
        await websocket.close(code=4001, reason="Invalid token")
        return

    user_id = user["id"]
    username = user["username"]

    # Subscribe and get replay data
    replay = terminal_manager.subscribe(terminal_id, user_id, websocket)
    if replay is None:
        await websocket.close(code=4004, reason="Terminal not found or access denied")
        return

    await websocket.accept()
    logger.info(f"WS connected: {username} -> terminal {terminal_id}")

    # Send replay buffer so client catches up
    if replay:
        await _send(websocket, {
            "type": "replay",
            "terminal_id": terminal_id,
            "data": base64.b64encode(replay).decode("ascii"),
        })

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await _send(websocket, {"type": "error", "message": "Invalid JSON"})
                continue

            msg_type = msg.get("type", "")

            if msg_type == "input":
                data_b64 = msg.get("data", "")
                if data_b64:
                    try:
                        data = base64.b64decode(data_b64)
                        terminal_manager.write_input(terminal_id, user_id, data)
                    except Exception:
                        pass

            elif msg_type == "resize":
                cols = msg.get("cols", 120)
                rows = msg.get("rows", 40)
                terminal_manager.resize_terminal(terminal_id, user_id, cols, rows)

            elif msg_type == "run_command":
                command = msg.get("command", "")
                if command:
                    ok = await terminal_manager.run_command(terminal_id, user_id, command)
                    if ok:
                        await _send(websocket, {
                            "type": "command_sent",
                            "terminal_id": terminal_id,
                            "command": command,
                        })
                    else:
                        await _send(websocket, {"type": "error", "message": "Failed to run command"})

            else:
                await _send(websocket, {"type": "error", "message": f"Unknown type: {msg_type}"})

    except WebSocketDisconnect:
        logger.info(f"WS disconnected: {username} <- terminal {terminal_id}")
    except Exception as e:
        logger.exception(f"WS error for {username} on terminal {terminal_id}")
    finally:
        terminal_manager.unsubscribe(terminal_id, user_id, websocket)


async def websocket_multiplex(
    websocket: WebSocket,
    token: str,
    terminal_manager: TerminalManager,
):
    """
    Multiplexed WebSocket — single connection handles all terminals for a user.
    Endpoint: /ws?token=<jwt>

    Client -> Server (JSON text frames):
      {"type": "create", "working_dir": "/path", "cols": 120, "rows": 40, "command": "claude"|"shell", "shell_path": "/bin/zsh"}
      {"type": "attach", "terminal_id": "abc123"}
      {"type": "detach", "terminal_id": "abc123"}
      {"type": "input", "terminal_id": "abc123", "data": "<base64>"}
      {"type": "resize", "terminal_id": "abc123", "cols": 120, "rows": 40}
      {"type": "destroy", "terminal_id": "abc123"}
      {"type": "list"}
      {"type": "run_command", "terminal_id": "abc123", "command": "ls -la"}
      {"type": "switch_mode", "terminal_id": "abc123", "mode": "shell"|"claude", "shell_path": "/bin/zsh"}

    Server -> Client (JSON text frames):
      {"type": "output", "terminal_id": "abc123", "data": "<base64>"}
      {"type": "created", "terminal_id": "abc123", "working_dir": "/path", "mode": "claude"|"shell"}
      {"type": "terminated", "terminal_id": "abc123"}
      {"type": "destroyed", "terminal_id": "abc123"}
      {"type": "attached", "terminal_id": "abc123", "replay": "<base64>", "mode": "claude"|"shell"}
      {"type": "terminals", "list": [...]}
      {"type": "switched", "old_terminal_id": "...", "new_terminal_id": "...", "mode": "..."}
      {"type": "command_sent", "terminal_id": "abc123", "command": "..."}
      {"type": "error", "message": "..."}
    """
    user = await get_ws_user(token)
    if not user:
        await websocket.close(code=4001, reason="Invalid token")
        return

    await websocket.accept()
    user_id = user["id"]
    username = user["username"]
    logger.info(f"Multiplex WS connected: {username} ({user_id})")

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await _send(websocket, {"type": "error", "message": "Invalid JSON"})
                continue

            msg_type = msg.get("type", "")

            try:
                if msg_type == "create":
                    await _handle_create(websocket, msg, user_id, terminal_manager)
                elif msg_type == "attach":
                    await _handle_attach(websocket, msg, user_id, terminal_manager)
                elif msg_type == "detach":
                    tid = msg.get("terminal_id", "")
                    terminal_manager.unsubscribe(tid, user_id, websocket)
                    await _send(websocket, {"type": "detached", "terminal_id": tid})
                elif msg_type == "input":
                    await _handle_input(msg, user_id, terminal_manager)
                elif msg_type == "resize":
                    tid = msg.get("terminal_id", "")
                    terminal_manager.resize_terminal(
                        tid, user_id, msg.get("cols", 120), msg.get("rows", 40)
                    )
                elif msg_type == "destroy":
                    await terminal_manager.destroy_terminal(msg.get("terminal_id", ""), user_id)
                elif msg_type == "list":
                    await _handle_list(websocket, user_id, terminal_manager)
                elif msg_type == "run_command":
                    await _handle_run_command(websocket, msg, user_id, terminal_manager)
                elif msg_type == "switch_mode":
                    await _handle_switch_mode(websocket, msg, user_id, terminal_manager)
                else:
                    await _send(websocket, {"type": "error", "message": f"Unknown type: {msg_type}"})

            except Exception as e:
                logger.exception(f"Error handling {msg_type}")
                await _send(websocket, {"type": "error", "message": str(e)})

    except WebSocketDisconnect:
        logger.info(f"Multiplex WS disconnected: {username}")
    except Exception:
        logger.exception(f"Multiplex WS error for {username}")
    finally:
        terminal_manager.unsubscribe_all(websocket)


# -- Multiplex helpers --

async def _handle_create(ws: WebSocket, msg: dict, user_id: str, tm: TerminalManager):
    terminal = await tm.create_terminal(
        user_id=user_id,
        working_dir=msg.get("working_dir", "~"),
        cols=msg.get("cols", 120),
        rows=msg.get("rows", 40),
        command=msg.get("command", "claude"),
        shell_path=msg.get("shell_path"),
    )
    terminal.subscribers.add(ws)
    await _send(ws, {
        "type": "created",
        "terminal_id": terminal.id,
        "working_dir": terminal.working_dir,
        "mode": terminal.mode.value,
        "command": terminal.command,
    })


async def _handle_attach(ws: WebSocket, msg: dict, user_id: str, tm: TerminalManager):
    tid = msg.get("terminal_id", "")
    replay_data = tm.subscribe(tid, user_id, ws)
    if replay_data is None:
        await _send(ws, {"type": "error", "message": f"Terminal {tid} not found"})
        return

    terminal = tm.get_terminal(tid, user_id)
    mode = terminal.mode.value if terminal else "unknown"

    encoded = base64.b64encode(replay_data).decode("ascii") if replay_data else ""
    await _send(ws, {
        "type": "attached",
        "terminal_id": tid,
        "replay": encoded,
        "mode": mode,
    })


async def _handle_input(msg: dict, user_id: str, tm: TerminalManager):
    tid = msg.get("terminal_id", "")
    data_b64 = msg.get("data", "")
    if not data_b64:
        return
    try:
        data = base64.b64decode(data_b64)
    except Exception:
        return
    tm.write_input(tid, user_id, data)


async def _handle_list(ws: WebSocket, user_id: str, tm: TerminalManager):
    terminals = tm.list_terminals(user_id)
    await _send(ws, {
        "type": "terminals",
        "list": [t.to_info_dict() for t in terminals],
    })


async def _handle_run_command(ws: WebSocket, msg: dict, user_id: str, tm: TerminalManager):
    """Execute a shell command in an existing terminal."""
    tid = msg.get("terminal_id", "")
    command = msg.get("command", "")
    if not command:
        await _send(ws, {"type": "error", "message": "No command provided"})
        return

    ok = await tm.run_command(tid, user_id, command)
    if ok:
        await _send(ws, {
            "type": "command_sent",
            "terminal_id": tid,
            "command": command,
        })
    else:
        await _send(ws, {"type": "error", "message": f"Failed to run command on {tid}"})


async def _handle_switch_mode(ws: WebSocket, msg: dict, user_id: str, tm: TerminalManager):
    """Switch a terminal between Claude and Shell mode."""
    tid = msg.get("terminal_id", "")
    new_mode = msg.get("mode", "shell")
    cols = msg.get("cols", 120)
    rows = msg.get("rows", 40)
    shell_path = msg.get("shell_path")

    if new_mode not in ("claude", "shell"):
        await _send(ws, {"type": "error", "message": f"Invalid mode: {new_mode}"})
        return

    new_terminal = await tm.switch_mode(
        terminal_id=tid,
        user_id=user_id,
        new_mode=new_mode,
        cols=cols,
        rows=rows,
        shell_path=shell_path,
    )

    if new_terminal:
        new_terminal.subscribers.add(ws)
        await _send(ws, {
            "type": "switched",
            "old_terminal_id": tid,
            "new_terminal_id": new_terminal.id,
            "mode": new_terminal.mode.value,
            "working_dir": new_terminal.working_dir,
        })
    else:
        await _send(ws, {"type": "error", "message": f"Terminal {tid} not found"})


async def _send(ws: WebSocket, data: dict):
    """Safe WebSocket send — swallows disconnect errors."""
    try:
        await ws.send_json(data)
    except Exception:
        pass
