"""
Grok Reviewer — spawns a review terminal that runs Grok to audit the build output.

After a spark agent signals COMPLETE, the dispatcher calls schedule_grok_review()
which spawns a new PTY, injects a review prompt, and monitors for APPROVED/REVISION.
"""

from __future__ import annotations

import asyncio
import logging
import os
from pathlib import Path
from typing import Any

from terminal_manager import TerminalManager

logger = logging.getLogger("arcbench.agents.grok_reviewer")

# How long to wait for Grok to finish reviewing (seconds)
REVIEW_TIMEOUT = 300  # 5 minutes
REVIEW_CHECK_INTERVAL = 3

# The review prompt injected into the Grok terminal
REVIEW_PROMPT_TEMPLATE = """\
Review the project in this directory. This was built by the {agent_name} agent for spark idea {idea_id}.

## Your Task
1. Read every file in this directory
2. Check for:
   - Completeness — does it fulfill the spark idea in CLAUDE.md?
   - Quality — clean code, no TODOs, no placeholders
   - Security — no hardcoded secrets, no injection vulnerabilities
   - Functionality — would this work if deployed right now?
3. Output your verdict as EXACTLY one of these lines:

   APPROVED: {idea_id}
   REVISION: {idea_id}

4. After the verdict line, write a 2-3 sentence summary.

Be thorough but concise. Start now.
"""


async def schedule_grok_review(
    idea_id: str,
    working_dir: str,
    agent_slug: str,
    terminal_manager: TerminalManager,
    user_id: str,
) -> dict[str, Any]:
    """
    Spawn a Grok review terminal and wait for the verdict.

    Returns:
        {
            "approved": bool,
            "summary": str,
            "terminal_id": str,
        }
    """
    logger.info(f"Scheduling Grok review for spark {idea_id} in {working_dir}")

    # Check if grok CLI is available; fall back to claude with review instructions
    grok_available = _check_grok_cli()
    command = "grok" if grok_available else "claude"

    # Spawn the review terminal
    terminal = await terminal_manager.create_terminal(
        user_id=user_id,
        working_dir=working_dir,
        cols=120,
        rows=40,
        command=command,
    )

    logger.info(
        f"Grok review terminal spawned: {terminal.id} "
        f"(command={command}, dir={working_dir})"
    )

    # Give the CLI a moment to initialize
    await asyncio.sleep(3)

    # Inject the review prompt
    review_prompt = REVIEW_PROMPT_TEMPLATE.format(
        agent_name=agent_slug,
        idea_id=idea_id,
    )

    prompt_bytes = (review_prompt + "\n").encode("utf-8")
    try:
        os.write(terminal.master_fd, prompt_bytes)
    except OSError as e:
        logger.error(f"Failed to inject review prompt: {e}")
        return {
            "approved": False,
            "summary": f"Review failed: could not inject prompt ({e})",
            "terminal_id": terminal.id,
        }

    # Monitor for verdict
    approved_signal = f"APPROVED: {idea_id}"
    revision_signal = f"REVISION: {idea_id}"
    elapsed = 0

    while elapsed < REVIEW_TIMEOUT:
        await asyncio.sleep(REVIEW_CHECK_INTERVAL)
        elapsed += REVIEW_CHECK_INTERVAL

        if not terminal.is_alive:
            logger.warning(f"Review terminal died for spark {idea_id}")
            break

        replay = terminal.get_replay_data()
        try:
            text = replay.decode("utf-8", errors="replace")
        except Exception:
            continue

        if approved_signal in text:
            summary = _extract_summary(text, approved_signal)
            logger.info(f"Spark {idea_id}: Grok APPROVED")
            return {
                "approved": True,
                "summary": summary,
                "terminal_id": terminal.id,
            }

        if revision_signal in text:
            summary = _extract_summary(text, revision_signal)
            logger.info(f"Spark {idea_id}: Grok requested REVISION")
            return {
                "approved": False,
                "summary": summary,
                "terminal_id": terminal.id,
            }

    # Timeout — treat as needs revision
    logger.warning(f"Grok review timed out for spark {idea_id}")
    return {
        "approved": False,
        "summary": "Review timed out — manual review required.",
        "terminal_id": terminal.id,
    }


def _extract_summary(full_text: str, signal: str) -> str:
    """Extract the summary text that follows the verdict signal."""
    idx = full_text.find(signal)
    if idx == -1:
        return ""
    after = full_text[idx + len(signal):].strip()
    # Take first 500 chars after the signal as summary
    lines = after.split("\n")
    summary_lines = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            if summary_lines:
                break
            continue
        summary_lines.append(stripped)
        if len(summary_lines) >= 5:
            break
    return " ".join(summary_lines)[:500] if summary_lines else "Review complete."


def _check_grok_cli() -> bool:
    """Check if the grok CLI is available on PATH."""
    import shutil
    available = shutil.which("grok") is not None
    if available:
        logger.info("Grok CLI found on PATH")
    else:
        logger.info("Grok CLI not found — falling back to Claude for review")
    return available
