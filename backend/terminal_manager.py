"""
Terminal Manager — PTY-based terminal sessions for Claude Code and Shell modes.
Each terminal is a real pseudo-terminal with full system access.
Supports multiple concurrent terminals per user with mode switching.
"""

from __future__ import annotations

import asyncio
import base64
import fcntl
import logging
import os
import pty
import signal
import struct
import termios
import uuid
from collections import deque
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any, Optional

from fastapi import WebSocket

import database

logger = logging.getLogger("arcbench.terminal")

# Max output buffer per terminal (for reconnection replay)
OUTPUT_BUFFER_MAX_BYTES = 100 * 1024  # 100KB


class TerminalMode(str, Enum):
    CLAUDE = "claude"
    SHELL = "shell"


class ManagedTerminal:
    """A single PTY terminal session — Claude Code or Shell mode."""

    def __init__(
        self,
        terminal_id: str,
        user_id: str,
        working_dir: str,
        master_fd: int,
        pid: int,
        mode: TerminalMode = TerminalMode.CLAUDE,
    ):
        self.id = terminal_id
        self.user_id = user_id
        self.working_dir = working_dir
        self.mode = mode
        self.command = mode.value
        self.master_fd = master_fd
        self.pid = pid
        self.is_alive = True
        self.created_at = datetime.now(timezone.utc).isoformat()
        self.last_active = self.created_at

        # Connected WebSocket clients viewing this terminal
        self.subscribers: set[WebSocket] = set()

        # Rolling output buffer for reconnection replay (shared across modes)
        self.output_buffer: deque[bytes] = deque()
        self._buffer_size = 0

        # MCP/Skills registry (future-proof: skills registered for this session)
        self.skills: list[dict[str, Any]] = []
        self.mcp_endpoints: list[str] = []

    def add_to_buffer(self, data: bytes):
        """Add output data to the rolling buffer, trimming from front if over limit."""
        self.output_buffer.append(data)
        self._buffer_size += len(data)
        while self._buffer_size > OUTPUT_BUFFER_MAX_BYTES and self.output_buffer:
            removed = self.output_buffer.popleft()
            self._buffer_size -= len(removed)

    def get_replay_data(self) -> bytes:
        """Get all buffered output for replay on reconnection."""
        return b"".join(self.output_buffer)

    def to_info_dict(self) -> dict:
        """Serialise terminal state for API/WS responses."""
        return {
            "id": self.id,
            "user_id": self.user_id,
            "working_dir": self.working_dir,
            "mode": self.mode.value,
            "command": self.command,
            "is_alive": self.is_alive,
            "created_at": self.created_at,
            "last_active": self.last_active,
            "skills": [s["name"] for s in self.skills],
            "mcp_endpoints": self.mcp_endpoints,
        }


class TerminalManager:
    """Manages all active terminal sessions across all users."""

    def __init__(self):
        self._terminals: dict[str, ManagedTerminal] = {}
        self._read_tasks: dict[str, asyncio.Task] = {}
        self._reaper_task: Optional[asyncio.Task] = None

    # ── Dead-PTY Reaper ──

    async def reap_dead_terminals(self) -> None:
        """Check all terminals for dead PIDs and clean them up."""
        dead_ids: list[str] = []

        for tid, terminal in list(self._terminals.items()):
            if not terminal.is_alive:
                continue
            try:
                pid_result, status = os.waitpid(terminal.pid, os.WNOHANG)
                if pid_result == 0:
                    continue  # still alive
            except ChildProcessError:
                # Already reaped or not our child — treat as dead
                pass

            dead_ids.append(tid)

        for tid in dead_ids:
            terminal = self._terminals.get(tid)
            if terminal is None:
                continue

            terminal.is_alive = False

            # Close the master fd
            try:
                os.close(terminal.master_fd)
            except OSError:
                pass

            # Cancel read task
            task = self._read_tasks.pop(tid, None)
            if task:
                task.cancel()

            # Notify subscribers
            for ws in list(terminal.subscribers):
                try:
                    await ws.send_json({
                        "type": "terminated",
                        "terminal_id": tid,
                    })
                except Exception:
                    pass

            # Mark dead in DB and remove from registry
            await database.mark_terminal_dead(tid)
            self._terminals.pop(tid, None)

            logger.info(f"Reaped dead terminal {tid} (PID {terminal.pid})")

        if dead_ids:
            logger.info(f"Reaper cleaned up {len(dead_ids)} dead terminal(s)")

    async def start_reaper(self, interval: int = 30) -> None:
        """Start a background task that periodically reaps dead terminals."""
        async def _reaper_loop():
            while True:
                await asyncio.sleep(interval)
                try:
                    await self.reap_dead_terminals()
                except asyncio.CancelledError:
                    raise
                except Exception as e:
                    logger.error(f"Reaper error: {e}")

        self._reaper_task = asyncio.create_task(_reaper_loop())

    async def stop_reaper(self) -> None:
        """Cancel the reaper background task."""
        if self._reaper_task is not None:
            self._reaper_task.cancel()
            try:
                await self._reaper_task
            except asyncio.CancelledError:
                pass
            self._reaper_task = None
            logger.info("Dead-PTY reaper stopped")

    async def create_terminal(
        self,
        user_id: str,
        working_dir: str = "~",
        cols: int = 120,
        rows: int = 40,
        command: str = "claude",
        shell_path: str | None = None,
    ) -> ManagedTerminal:
        """Spawn a new PTY terminal running the given command."""
        expanded_dir = os.path.expanduser(working_dir)
        if not os.path.isdir(expanded_dir):
            os.makedirs(expanded_dir, exist_ok=True)

        terminal_id = uuid.uuid4().hex[:12]
        mode = TerminalMode(command) if command in ("claude", "shell") else TerminalMode.SHELL

        pid, master_fd = pty.fork()

        if pid == 0:
            # -- Child process --
            os.chdir(expanded_dir)
            os.environ["TERM"] = "xterm-256color"
            os.environ["COLORTERM"] = "truecolor"
            os.environ["LANG"] = "en_US.UTF-8"
            os.environ.pop("CLAUDECODE", None)

            # Ensure common bin dirs are in PATH for child process
            path = os.environ.get("PATH", "")
            extra = ["/usr/local/bin", "/opt/homebrew/bin",
                     os.path.expanduser("~/.npm-global/bin"),
                     os.path.expanduser("~/.local/bin"),
                     os.path.expanduser("~/.nvm/versions/node/*/bin")]
            import glob
            resolved = []
            for p in extra:
                if "*" in p:
                    resolved.extend(glob.glob(p))
                else:
                    resolved.append(p)
            for d in resolved:
                if d not in path:
                    path = f"{d}:{path}"
            os.environ["PATH"] = path

            if command == "claude":
                os.execlp("claude", "claude")
            elif command == "shell":
                shell = shell_path or os.environ.get("SHELL", "/bin/zsh")
                os.execlp(shell, shell)
            else:
                os.execlp(command, command)
        else:
            # -- Parent process --
            winsize = struct.pack("HHHH", rows, cols, 0, 0)
            fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)

            terminal = ManagedTerminal(
                terminal_id=terminal_id,
                user_id=user_id,
                working_dir=expanded_dir,
                master_fd=master_fd,
                pid=pid,
                mode=mode,
            )
            self._terminals[terminal_id] = terminal

            await database.save_terminal(
                terminal_id, user_id, expanded_dir, terminal.created_at, mode.value
            )

            task = asyncio.create_task(self._read_loop(terminal))
            self._read_tasks[terminal_id] = task

            logger.info(
                f"Created terminal {terminal_id} for user {user_id} "
                f"(PID {pid}, dir={expanded_dir}, mode={mode.value})"
            )
            return terminal

    async def switch_mode(
        self,
        terminal_id: str,
        user_id: str,
        new_mode: str,
        cols: int = 120,
        rows: int = 40,
        shell_path: str | None = None,
    ) -> ManagedTerminal | None:
        """Switch a terminal's mode by destroying and recreating it.
        Preserves the replay buffer from the old session."""
        old = self.get_terminal(terminal_id, user_id)
        if not old:
            return None

        working_dir = old.working_dir
        subscribers = set(old.subscribers)
        old_replay = old.get_replay_data()

        # Destroy old terminal
        await self.destroy_terminal(terminal_id, user_id)

        # Create new terminal in the new mode
        new_terminal = await self.create_terminal(
            user_id=user_id,
            working_dir=working_dir,
            cols=cols,
            rows=rows,
            command=new_mode,
            shell_path=shell_path,
        )

        # Re-attach old subscribers
        for ws in subscribers:
            new_terminal.subscribers.add(ws)

        # Inject old replay buffer so client still has context
        if old_replay:
            new_terminal.add_to_buffer(old_replay)

        return new_terminal

    async def run_command(
        self,
        terminal_id: str,
        user_id: str,
        command: str,
    ) -> bool:
        """Execute a shell command in an existing terminal by writing it to PTY stdin.
        Works in both Claude and Shell mode."""
        terminal = self.get_terminal(terminal_id, user_id)
        if not terminal or not terminal.is_alive:
            return False

        # Write the command + newline to execute it
        cmd_bytes = (command.rstrip("\n") + "\n").encode("utf-8")
        try:
            os.write(terminal.master_fd, cmd_bytes)
            terminal.last_active = datetime.now(timezone.utc).isoformat()
            return True
        except OSError as e:
            logger.error(f"run_command error on terminal {terminal_id}: {e}")
            return False

    async def _read_loop(self, terminal: ManagedTerminal):
        """Continuously read PTY output and broadcast to subscribers."""
        loop = asyncio.get_event_loop()

        while terminal.is_alive:
            try:
                data = await loop.run_in_executor(
                    None, self._blocking_read, terminal.master_fd
                )
                if data is None:
                    break
                if not data:
                    continue

                terminal.add_to_buffer(data)
                terminal.last_active = datetime.now(timezone.utc).isoformat()

                encoded = base64.b64encode(data).decode("ascii")
                msg = {
                    "type": "output",
                    "terminal_id": terminal.id,
                    "data": encoded,
                }

                dead_subs = set()
                for ws in terminal.subscribers:
                    try:
                        await ws.send_json(msg)
                    except Exception:
                        dead_subs.add(ws)
                terminal.subscribers -= dead_subs

            except OSError:
                break
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Read error on terminal {terminal.id}: {e}")
                break

        terminal.is_alive = False
        await database.mark_terminal_dead(terminal.id)

        for ws in list(terminal.subscribers):
            try:
                await ws.send_json({
                    "type": "terminated",
                    "terminal_id": terminal.id,
                })
            except Exception:
                pass

        logger.info(f"Terminal {terminal.id} exited")

    @staticmethod
    def _blocking_read(fd: int) -> Optional[bytes]:
        """Blocking read with 0.5s timeout. Returns bytes, b"" on timeout, None on EOF."""
        import select

        ready, _, _ = select.select([fd], [], [], 0.5)
        if ready:
            try:
                data = os.read(fd, 4096)
                return data if data else None
            except OSError:
                return None
        return b""

    def write_input(self, terminal_id: str, user_id: str, data: bytes):
        """Write user input to a terminal's PTY stdin."""
        terminal = self.get_terminal(terminal_id, user_id)
        if not terminal or not terminal.is_alive:
            return
        try:
            os.write(terminal.master_fd, data)
            terminal.last_active = datetime.now(timezone.utc).isoformat()
        except OSError as e:
            logger.error(f"Write error on terminal {terminal_id}: {e}")

    def resize_terminal(self, terminal_id: str, user_id: str, cols: int, rows: int):
        """Resize a terminal's PTY window."""
        terminal = self.get_terminal(terminal_id, user_id)
        if not terminal or not terminal.is_alive:
            return
        try:
            winsize = struct.pack("HHHH", rows, cols, 0, 0)
            fcntl.ioctl(terminal.master_fd, termios.TIOCSWINSZ, winsize)
            os.kill(terminal.pid, signal.SIGWINCH)
        except (OSError, ProcessLookupError) as e:
            logger.error(f"Resize error on terminal {terminal_id}: {e}")

    async def destroy_terminal(self, terminal_id: str, user_id: str):
        """Kill a terminal and clean up."""
        terminal = self.get_terminal(terminal_id, user_id)
        if not terminal:
            return

        if terminal.is_alive:
            try:
                os.kill(terminal.pid, signal.SIGTERM)
                await asyncio.sleep(1)
                try:
                    os.kill(terminal.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            except ProcessLookupError:
                pass

        terminal.is_alive = False

        try:
            os.close(terminal.master_fd)
        except OSError:
            pass

        task = self._read_tasks.pop(terminal_id, None)
        if task:
            task.cancel()

        for ws in list(terminal.subscribers):
            try:
                await ws.send_json({
                    "type": "destroyed",
                    "terminal_id": terminal_id,
                })
            except Exception:
                pass

        self._terminals.pop(terminal_id, None)
        await database.mark_terminal_dead(terminal_id)

        try:
            os.waitpid(terminal.pid, os.WNOHANG)
        except ChildProcessError:
            pass

        logger.info(f"Destroyed terminal {terminal_id}")

    def get_terminal(self, terminal_id: str, user_id: str) -> Optional[ManagedTerminal]:
        """Get a terminal by ID, enforcing user ownership."""
        terminal = self._terminals.get(terminal_id)
        if terminal and terminal.user_id == user_id:
            return terminal
        return None

    def list_terminals(self, user_id: str) -> list[ManagedTerminal]:
        """List all active terminals for a user."""
        return [t for t in self._terminals.values() if t.user_id == user_id]

    def subscribe(self, terminal_id: str, user_id: str, ws: WebSocket) -> Optional[bytes]:
        """Subscribe a WebSocket to a terminal's output. Returns replay data."""
        terminal = self.get_terminal(terminal_id, user_id)
        if not terminal:
            return None
        terminal.subscribers.add(ws)
        return terminal.get_replay_data()

    def unsubscribe(self, terminal_id: str, user_id: str, ws: WebSocket):
        """Unsubscribe a WebSocket from a terminal."""
        terminal = self.get_terminal(terminal_id, user_id)
        if terminal:
            terminal.subscribers.discard(ws)

    def unsubscribe_all(self, ws: WebSocket):
        """Remove a WebSocket from all terminals (on disconnect)."""
        for terminal in self._terminals.values():
            terminal.subscribers.discard(ws)

    # NOTE: start_reaper / stop_reaper defined above (lines 166-189)

    async def shutdown_all(self):
        """Kill all terminals on server shutdown."""
        for terminal_id in list(self._terminals.keys()):
            terminal = self._terminals[terminal_id]
            try:
                os.kill(terminal.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

        for task in self._read_tasks.values():
            task.cancel()

        await asyncio.sleep(1)
        for terminal in self._terminals.values():
            try:
                os.kill(terminal.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                os.close(terminal.master_fd)
            except OSError:
                pass

        self._terminals.clear()
        self._read_tasks.clear()
        logger.info("All terminals shut down")
