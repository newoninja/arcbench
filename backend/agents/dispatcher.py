"""
Spark Idea Dispatcher — receives spark ideas, classifies, spawns PTY build agents,
monitors for COMPLETE, schedules auto Grok review, handles revision loops,
starts preview servers, and sends push notifications.
"""

from __future__ import annotations

import asyncio
import base64
import logging
import os
import shutil
import socket
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from terminal_manager import TerminalManager, ManagedTerminal
from agents.registry import AgentSpec, classify_agent, get_agent, AGENT_REGISTRY
from agents.grok_reviewer import schedule_grok_review
from agents.notifier import send_push_notification
import database

logger = logging.getLogger("arcbench.agents.dispatcher")

# Base directory for all spark builds
BUILDS_ROOT = Path.home() / "arcbench-builds"

# Max revision attempts before giving up
MAX_REVISION_ATTEMPTS = 3

# Track active preview servers so we can clean them up
_preview_servers: dict[str, subprocess.Popen] = {}


async def dispatch_spark(
    idea: dict[str, Any],
    user_id: str,
    terminal_manager: TerminalManager,
    notify_callback: Any = None,
) -> dict[str, Any]:
    """
    Full spark idea pipeline:
      1. Classify (or use user-specified agent via chip_label)
      2. Create working directory
      3. Write SOUL.md into the directory
      4. Spawn PTY running Claude with the SOUL.md context
      5. Inject the idea as the first prompt
      6. Monitor output for "COMPLETE" signal
      7. Schedule Grok review (if auto_grok_review)
      8. Handle revision feedback loop (up to MAX_REVISION_ATTEMPTS)
      9. Start preview server + send push notification on approval
    """
    idea_id = idea.get("idea_id", uuid.uuid4().hex[:12])
    content = idea.get("content", "")
    chip_label = idea.get("chip_label")

    if not content:
        return {"error": "Empty spark idea", "status": "rejected"}

    # 1. Classify
    agent = classify_agent(content, chip_label)
    logger.info(f"Spark {idea_id}: classified -> {agent.name} ({agent.slug})")

    # 2. Create working directory
    build_dir = BUILDS_ROOT / agent.slug / idea_id
    build_dir.mkdir(parents=True, exist_ok=True)

    # 3. Inject SOUL.md
    soul_content = _load_soul(agent)
    soul_dest = build_dir / "SOUL.md"
    soul_dest.write_text(soul_content, encoding="utf-8")

    # Also write a CLAUDE.md that points Claude to the SOUL
    claude_md = build_dir / "CLAUDE.md"
    claude_md.write_text(
        f"# ArcBench Spark Build — {agent.name}\n\n"
        f"Read SOUL.md for your full personality and instructions.\n"
        f"Follow every directive in SOUL.md exactly.\n\n"
        f"## Spark Idea\n\n{content}\n\n"
        f"## Completion Signal\n\n"
        f"When you are done building, output the exact line:\n"
        f"```\nCOMPLETE: {idea_id}\n```\n"
        f"This signals the orchestrator to start Grok review.\n",
        encoding="utf-8",
    )

    # 4. Spawn PTY
    terminal = await terminal_manager.create_terminal(
        user_id=user_id,
        working_dir=str(build_dir),
        cols=120,
        rows=40,
        command="claude",
    )

    logger.info(
        f"Spark {idea_id}: PTY spawned (terminal={terminal.id}, "
        f"dir={build_dir}, agent={agent.slug})"
    )

    # 5. Save spark record to DB
    await _save_spark(
        spark_id=idea_id,
        user_id=user_id,
        terminal_id=terminal.id,
        agent_slug=agent.slug,
        agent_name=agent.name,
        content=content,
        chip_label=chip_label,
        working_dir=str(build_dir),
    )

    # 6. Notify client
    if notify_callback:
        await notify_callback(user_id, {
            "type": "spark_dispatched",
            "idea_id": idea_id,
            "agent": agent.slug,
            "agent_name": agent.name,
            "terminal_id": terminal.id,
            "working_dir": str(build_dir),
            "status": "building",
        })

    # 7. Start output monitor (watches for COMPLETE signal)
    asyncio.create_task(
        _monitor_for_completion(
            idea_id=idea_id,
            terminal=terminal,
            agent=agent,
            user_id=user_id,
            terminal_manager=terminal_manager,
            notify_callback=notify_callback,
        )
    )

    return {
        "idea_id": idea_id,
        "agent_slug": agent.slug,
        "agent_name": agent.name,
        "terminal_id": terminal.id,
        "working_dir": str(build_dir),
        "status": "building",
    }


def _load_soul(agent: AgentSpec) -> str:
    """Load the SOUL.md file for an agent, with fallback."""
    if agent.soul_path.exists():
        return agent.soul_path.read_text(encoding="utf-8")

    logger.warning(f"SOUL.md not found for {agent.slug}, generating minimal soul")
    return (
        f"# {agent.name} — SOUL\n\n"
        f"You are {agent.name}, a specialized AI build agent.\n\n"
        f"## Identity\n"
        f"{agent.description}\n\n"
        f"## Available Tools\n"
        f"{', '.join(agent.tools)}\n\n"
        f"## Directives\n"
        f"1. Read the user's spark idea from CLAUDE.md\n"
        f"2. Build the complete deliverable in this directory\n"
        f"3. Create production-ready files — no placeholders, no TODOs\n"
        f"4. When finished, output: COMPLETE: <idea_id>\n\n"
        f"## Quality Standards\n"
        f"- Clean, documented code\n"
        f"- Working out of the box\n"
        f"- Follow modern best practices\n"
    )


async def _monitor_for_completion(
    idea_id: str,
    terminal: ManagedTerminal,
    agent: AgentSpec,
    user_id: str,
    terminal_manager: TerminalManager,
    notify_callback: Any = None,
):
    """
    Monitor terminal output buffer for the COMPLETE signal.
    When detected, trigger Grok review and push notification.
    """
    complete_signal = f"COMPLETE: {idea_id}"
    check_interval = 5  # seconds
    max_wait = 3600  # 1 hour timeout
    elapsed = 0

    logger.info(f"Spark {idea_id}: monitoring for completion signal...")

    while elapsed < max_wait:
        await asyncio.sleep(check_interval)
        elapsed += check_interval

        # Check if spark was cancelled
        spark = await database.get_spark_by_id(idea_id)
        if spark and spark["status"] == "cancelled":
            logger.info(f"Spark {idea_id}: cancelled by user")
            return

        if not terminal.is_alive:
            logger.warning(f"Spark {idea_id}: terminal died before completion")
            await _update_spark_status(idea_id, "failed")
            if notify_callback:
                await notify_callback(user_id, {
                    "type": "spark_status",
                    "idea_id": idea_id,
                    "status": "failed",
                    "reason": "Terminal exited before COMPLETE signal",
                })
            return

        # Check the replay buffer for the completion signal
        replay = terminal.get_replay_data()
        try:
            replay_text = replay.decode("utf-8", errors="replace")
        except Exception:
            continue

        if complete_signal in replay_text:
            logger.info(f"Spark {idea_id}: COMPLETE signal detected!")

            # Phase 6: "BUILD COMPLETE" prefix message
            if notify_callback:
                await notify_callback(user_id, {
                    "type": "spark_status",
                    "idea_id": idea_id,
                    "status": "reviewing",
                    "message": "BUILD COMPLETE \u2013 Grok review requested",
                    "agent": agent.slug,
                })

            await _update_spark_status(idea_id, "reviewing")

            # Phase 6: Start preview server if index.html exists
            preview_url = await _start_preview_server(idea_id, terminal.working_dir)
            if preview_url:
                await database.update_spark_preview_url(idea_id, preview_url)

            # Schedule Grok review
            if agent.auto_grok_review:
                asyncio.create_task(
                    _run_grok_review(
                        idea_id=idea_id,
                        agent=agent,
                        user_id=user_id,
                        working_dir=terminal.working_dir,
                        terminal_manager=terminal_manager,
                        notify_callback=notify_callback,
                        preview_url=preview_url,
                    )
                )
            else:
                await _update_spark_status(idea_id, "approved")

            return

    # Timeout
    logger.warning(f"Spark {idea_id}: timed out after {max_wait}s")
    await _update_spark_status(idea_id, "timeout")
    if notify_callback:
        await notify_callback(user_id, {
            "type": "spark_status",
            "idea_id": idea_id,
            "status": "timeout",
        })


async def _run_grok_review(
    idea_id: str,
    agent: AgentSpec,
    user_id: str,
    working_dir: str,
    terminal_manager: TerminalManager,
    notify_callback: Any = None,
    preview_url: str | None = None,
    revision_attempt: int = 0,
):
    """Spawn Grok review and handle the result. On REVISION, triggers revision loop."""
    try:
        result = await schedule_grok_review(
            idea_id=idea_id,
            working_dir=working_dir,
            agent_slug=agent.slug,
            terminal_manager=terminal_manager,
            user_id=user_id,
        )

        approved = result.get("approved", False)
        summary = result.get("summary", "")

        # Save review summary to DB
        await database.update_spark_review_summary(idea_id, summary)

        if approved:
            await _update_spark_status(idea_id, "approved")

            # Notify via WebSocket
            if notify_callback:
                await notify_callback(user_id, {
                    "type": "spark_status",
                    "idea_id": idea_id,
                    "status": "approved",
                    "review_summary": summary,
                    "preview_url": preview_url,
                    "review_terminal_id": result.get("terminal_id"),
                })

            # Send push notification
            title = "BUILD COMPLETE \u2013 Grok review requested"
            body = summary or "Your build has been reviewed and approved by Grok."
            if preview_url:
                body += f"\nPreview: {preview_url}"

            await send_push_notification(
                user_id=user_id,
                title=title,
                body=body,
                data={
                    "type": "spark_approved",
                    "idea_id": idea_id,
                    "agent": agent.slug,
                    "preview_url": preview_url or "",
                },
            )

            # Phase 7: Agent chaining
            if hasattr(agent, 'post_approve_chain') and agent.post_approve_chain:
                chained = get_agent(agent.post_approve_chain)
                if chained:
                    logger.info(f"Spark {idea_id}: chaining to {chained.slug}")
                    await dispatch_spark(
                        idea={"idea_id": f"{idea_id}-chain", "content": f"Continue from {working_dir}", "chip_label": None},
                        user_id=user_id,
                        terminal_manager=terminal_manager,
                        notify_callback=notify_callback,
                    )
        else:
            # REVISION needed — trigger feedback loop
            await _handle_revision(
                idea_id=idea_id,
                agent=agent,
                user_id=user_id,
                working_dir=working_dir,
                terminal_manager=terminal_manager,
                notify_callback=notify_callback,
                review_summary=summary,
                revision_attempt=revision_attempt,
                preview_url=preview_url,
            )

    except Exception as e:
        logger.exception(f"Grok review failed for spark {idea_id}: {e}")
        await _update_spark_status(idea_id, "review_failed")
        if notify_callback:
            await notify_callback(user_id, {
                "type": "spark_status",
                "idea_id": idea_id,
                "status": "review_failed",
                "error": str(e),
            })


async def _handle_revision(
    idea_id: str,
    agent: AgentSpec,
    user_id: str,
    working_dir: str,
    terminal_manager: TerminalManager,
    notify_callback: Any = None,
    review_summary: str = "",
    revision_attempt: int = 0,
    preview_url: str | None = None,
):
    """
    Phase 4: Bounded recursive revision loop.
    On REVISION verdict from Grok:
    1. Write REVISION_FEEDBACK.md with Grok's feedback
    2. Spawn new build terminal in the same directory
    3. Agent sees existing work + feedback, builds again
    4. Re-trigger completion monitor -> Grok review
    Max MAX_REVISION_ATTEMPTS attempts.
    """
    new_attempt = revision_attempt + 1
    revision_count = await database.increment_spark_revision(idea_id)

    if new_attempt >= MAX_REVISION_ATTEMPTS:
        logger.warning(
            f"Spark {idea_id}: max revision attempts ({MAX_REVISION_ATTEMPTS}) reached"
        )
        await _update_spark_status(idea_id, "max_revisions_reached")
        if notify_callback:
            await notify_callback(user_id, {
                "type": "spark_status",
                "idea_id": idea_id,
                "status": "max_revisions_reached",
                "review_summary": review_summary,
                "revision_count": revision_count,
            })
        await send_push_notification(
            user_id=user_id,
            title=f"Spark Needs Manual Review: {agent.name}",
            body=f"Max revisions ({MAX_REVISION_ATTEMPTS}) reached. {review_summary}",
            data={"type": "spark_max_revisions", "idea_id": idea_id},
        )
        return

    # Update status to revising
    await _update_spark_status(idea_id, "revising")

    if notify_callback:
        await notify_callback(user_id, {
            "type": "spark_status",
            "idea_id": idea_id,
            "status": "revising",
            "revision_count": revision_count,
            "review_summary": review_summary,
            "message": f"Revising (attempt {new_attempt}/{MAX_REVISION_ATTEMPTS})",
        })

    # Write REVISION_FEEDBACK.md
    feedback_path = Path(working_dir) / "REVISION_FEEDBACK.md"
    feedback_content = (
        f"# Revision Feedback (Attempt {new_attempt})\n\n"
        f"The Grok reviewer found issues with the current build.\n\n"
        f"## Reviewer Summary\n\n{review_summary}\n\n"
        f"## Instructions\n\n"
        f"1. Read the reviewer's feedback above carefully\n"
        f"2. Fix ALL issues mentioned\n"
        f"3. Do NOT start from scratch — improve the existing files\n"
        f"4. When done, output: COMPLETE: {idea_id}\n"
    )
    feedback_path.write_text(feedback_content, encoding="utf-8")

    # Spawn new build terminal in the same directory
    terminal = await terminal_manager.create_terminal(
        user_id=user_id,
        working_dir=working_dir,
        cols=120,
        rows=40,
        command="claude",
    )

    logger.info(
        f"Spark {idea_id}: revision PTY spawned (terminal={terminal.id}, "
        f"attempt={new_attempt}/{MAX_REVISION_ATTEMPTS})"
    )

    # Monitor for COMPLETE again, then re-trigger Grok
    asyncio.create_task(
        _monitor_for_completion_revision(
            idea_id=idea_id,
            terminal=terminal,
            agent=agent,
            user_id=user_id,
            terminal_manager=terminal_manager,
            notify_callback=notify_callback,
            revision_attempt=new_attempt,
            preview_url=preview_url,
        )
    )


async def _monitor_for_completion_revision(
    idea_id: str,
    terminal: ManagedTerminal,
    agent: AgentSpec,
    user_id: str,
    terminal_manager: TerminalManager,
    notify_callback: Any = None,
    revision_attempt: int = 0,
    preview_url: str | None = None,
):
    """Monitor for COMPLETE during a revision attempt, then re-trigger Grok review."""
    complete_signal = f"COMPLETE: {idea_id}"
    check_interval = 5
    max_wait = 3600
    elapsed = 0

    while elapsed < max_wait:
        await asyncio.sleep(check_interval)
        elapsed += check_interval

        spark = await database.get_spark_by_id(idea_id)
        if spark and spark["status"] == "cancelled":
            return

        if not terminal.is_alive:
            await _update_spark_status(idea_id, "failed")
            if notify_callback:
                await notify_callback(user_id, {
                    "type": "spark_status",
                    "idea_id": idea_id,
                    "status": "failed",
                    "reason": f"Revision terminal died (attempt {revision_attempt})",
                })
            return

        replay = terminal.get_replay_data()
        try:
            replay_text = replay.decode("utf-8", errors="replace")
        except Exception:
            continue

        if complete_signal in replay_text:
            logger.info(f"Spark {idea_id}: revision COMPLETE (attempt {revision_attempt})")
            await _update_spark_status(idea_id, "reviewing")

            if notify_callback:
                await notify_callback(user_id, {
                    "type": "spark_status",
                    "idea_id": idea_id,
                    "status": "reviewing",
                    "message": f"BUILD COMPLETE \u2013 Grok review requested (revision {revision_attempt})",
                })

            # Re-trigger Grok review
            asyncio.create_task(
                _run_grok_review(
                    idea_id=idea_id,
                    agent=agent,
                    user_id=user_id,
                    working_dir=terminal.working_dir,
                    terminal_manager=terminal_manager,
                    notify_callback=notify_callback,
                    preview_url=preview_url,
                    revision_attempt=revision_attempt,
                )
            )
            return

    # Timeout
    await _update_spark_status(idea_id, "timeout")
    if notify_callback:
        await notify_callback(user_id, {
            "type": "spark_status",
            "idea_id": idea_id,
            "status": "timeout",
        })


# ─── Phase 6: Preview Server ───

def _get_tailscale_ip() -> str | None:
    """Get the machine's Tailscale IPv4 address."""
    try:
        result = subprocess.run(
            ["tailscale", "ip", "-4"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            ip = result.stdout.strip().split("\n")[0]
            return ip
    except Exception:
        pass
    return None


def _find_open_port(start: int = 8080, end: int = 8099) -> int | None:
    """Find an available port in the given range."""
    for port in range(start, end + 1):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("0.0.0.0", port))
                return port
            except OSError:
                continue
    return None


async def _start_preview_server(idea_id: str, working_dir: str) -> str | None:
    """
    If index.html exists in the build directory, start a simple HTTP server
    and return the Tailscale-accessible URL.
    """
    build_path = Path(working_dir)
    index = build_path / "index.html"
    if not index.exists():
        return None

    port = _find_open_port()
    if port is None:
        logger.warning(f"Spark {idea_id}: no available preview port (8080-8099)")
        return None

    ts_ip = _get_tailscale_ip()
    host = ts_ip or "localhost"

    try:
        proc = subprocess.Popen(
            ["python3", "-m", "http.server", str(port)],
            cwd=str(build_path),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        _preview_servers[idea_id] = proc
        url = f"http://{host}:{port}"
        logger.info(f"Spark {idea_id}: preview server started at {url}")
        return url
    except Exception as e:
        logger.error(f"Spark {idea_id}: failed to start preview server: {e}")
        return None


# ─── Phase 7: Cancel support ───

async def cancel_spark(
    idea_id: str,
    terminal_manager: TerminalManager,
) -> bool:
    """Cancel a running spark by killing its terminal."""
    spark = await database.get_spark_by_id(idea_id)
    if not spark:
        return False

    terminal_id = spark.get("terminal_id")
    if terminal_id:
        await terminal_manager.destroy_terminal(terminal_id, spark["user_id"])

    await _update_spark_status(idea_id, "cancelled")

    # Kill preview server if running
    proc = _preview_servers.pop(idea_id, None)
    if proc:
        proc.terminate()

    return True


# ─── Database helpers ───

async def _save_spark(
    spark_id: str,
    user_id: str,
    terminal_id: str,
    agent_slug: str,
    agent_name: str,
    content: str,
    chip_label: Optional[str],
    working_dir: str,
):
    """Persist a spark idea record."""
    db = database.get_db()
    now = datetime.now(timezone.utc).isoformat()
    await db.execute(
        """INSERT OR REPLACE INTO sparks
           (id, user_id, terminal_id, agent_slug, agent_name, content, chip_label,
            working_dir, status, revision_count, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'building', 0, ?, ?)""",
        (spark_id, user_id, terminal_id, agent_slug, agent_name, content, chip_label,
         working_dir, now, now),
    )
    await db.commit()


async def _update_spark_status(spark_id: str, status: str):
    """Update a spark's status."""
    await database.update_spark_status(spark_id, status)
    logger.info(f"Spark {spark_id}: status -> {status}")


async def get_user_sparks(user_id: str) -> list[dict]:
    """Get all sparks for a user, newest first."""
    return await database.get_user_sparks(user_id)
