"""
ArcBench Computer Control — Full macOS automation.
===================================================
App launching, browser automation, mouse/keyboard, screenshots, AppleScript.
"""

from __future__ import annotations

import asyncio
import base64
import logging
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

logger = logging.getLogger("arcbench.computer")


# ─── App Control ─────────────────────────────────────────────

async def open_app(app_name: str) -> dict:
    """Open a macOS application by name."""
    proc = await asyncio.create_subprocess_exec(
        "open", "-a", app_name,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()
    if proc.returncode != 0:
        return {"ok": False, "error": stderr.decode().strip()}
    return {"ok": True, "app": app_name}


async def quit_app(app_name: str) -> dict:
    """Quit a macOS application gracefully via AppleScript."""
    script = f'tell application "{app_name}" to quit'
    return await run_applescript(script)


async def list_running_apps() -> dict:
    """List all running GUI applications."""
    script = 'tell application "System Events" to get name of every process whose background only is false'
    result = await run_applescript(script)
    if result["ok"] and result.get("output"):
        apps = [a.strip() for a in result["output"].split(",")]
        return {"ok": True, "apps": apps}
    return result


async def activate_app(app_name: str) -> dict:
    """Bring an app to the foreground."""
    script = f'tell application "{app_name}" to activate'
    return await run_applescript(script)


# ─── AppleScript Bridge ─────────────────────────────────────

async def run_applescript(script: str) -> dict:
    """Execute arbitrary AppleScript."""
    proc = await asyncio.create_subprocess_exec(
        "osascript", "-e", script,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()
    if proc.returncode != 0:
        return {"ok": False, "error": stderr.decode().strip()}
    return {"ok": True, "output": stdout.decode().strip()}


# ─── Screenshot ──────────────────────────────────────────────

async def take_screenshot(region: Optional[dict] = None) -> dict:
    """
    Capture a screenshot. Returns base64-encoded PNG.
    region: optional {x, y, w, h} to capture a specific area.
    """
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        path = f.name

    cmd = ["screencapture", "-x"]  # -x = no sound
    if region:
        cmd += ["-R", f"{region['x']},{region['y']},{region['w']},{region['h']}"]
    cmd.append(path)

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    await proc.communicate()

    p = Path(path)
    if not p.exists():
        return {"ok": False, "error": "Screenshot failed"}

    data = p.read_bytes()
    p.unlink()
    return {
        "ok": True,
        "image_base64": base64.b64encode(data).decode(),
        "format": "png",
        "size": len(data),
    }


# ─── Mouse & Keyboard (pyautogui) ───────────────────────────

def _ensure_pyautogui():
    try:
        import pyautogui
        pyautogui.FAILSAFE = True  # move mouse to corner to abort
        pyautogui.PAUSE = 0.1
        return pyautogui
    except ImportError:
        raise RuntimeError("pyautogui not installed — run: pip install pyautogui")


async def mouse_move(x: int, y: int, duration: float = 0.3) -> dict:
    pag = _ensure_pyautogui()
    await asyncio.to_thread(pag.moveTo, x, y, duration=duration)
    return {"ok": True, "position": [x, y]}


async def mouse_click(x: Optional[int] = None, y: Optional[int] = None,
                       button: str = "left", clicks: int = 1) -> dict:
    pag = _ensure_pyautogui()
    kwargs = {"button": button, "clicks": clicks}
    if x is not None and y is not None:
        kwargs["x"] = x
        kwargs["y"] = y
    await asyncio.to_thread(pag.click, **kwargs)
    pos = pag.position()
    return {"ok": True, "position": [pos.x, pos.y]}


async def mouse_scroll(amount: int, x: Optional[int] = None, y: Optional[int] = None) -> dict:
    pag = _ensure_pyautogui()
    kwargs = {"clicks": amount}
    if x is not None and y is not None:
        kwargs["x"] = x
        kwargs["y"] = y
    await asyncio.to_thread(pag.scroll, **kwargs)
    return {"ok": True, "scrolled": amount}


async def keyboard_type(text: str, interval: float = 0.02) -> dict:
    pag = _ensure_pyautogui()
    await asyncio.to_thread(pag.typewrite, text, interval=interval)
    return {"ok": True, "typed": len(text)}


async def keyboard_hotkey(*keys: str) -> dict:
    """Press a hotkey combo, e.g. keyboard_hotkey('command', 'c')."""
    pag = _ensure_pyautogui()
    await asyncio.to_thread(pag.hotkey, *keys)
    return {"ok": True, "keys": list(keys)}


async def keyboard_press(key: str) -> dict:
    """Press a single key, e.g. 'enter', 'tab', 'escape'."""
    pag = _ensure_pyautogui()
    await asyncio.to_thread(pag.press, key)
    return {"ok": True, "key": key}


async def get_mouse_position() -> dict:
    pag = _ensure_pyautogui()
    pos = pag.position()
    return {"ok": True, "x": pos.x, "y": pos.y}


# ─── Browser Automation (Playwright) ────────────────────────

class BrowserController:
    """Manages a persistent Playwright browser session."""

    def __init__(self):
        self._playwright = None
        self._browser = None
        self._context = None
        self._pages: dict[str, object] = {}  # tab_id -> Page

    async def launch(self, headless: bool = False, browser_type: str = "chromium") -> dict:
        try:
            from playwright.async_api import async_playwright
        except ImportError:
            return {"ok": False, "error": "playwright not installed — run: pip install playwright && playwright install chromium"}

        if self._browser:
            return {"ok": True, "status": "already_running"}

        self._playwright = await async_playwright().start()
        launcher = getattr(self._playwright, browser_type, self._playwright.chromium)
        self._browser = await launcher.launch(headless=headless)
        self._context = await self._browser.new_context(
            viewport={"width": 1280, "height": 900},
            user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        )
        logger.info(f"Browser launched: {browser_type}, headless={headless}")
        return {"ok": True, "browser": browser_type, "headless": headless}

    async def close(self) -> dict:
        if self._browser:
            await self._browser.close()
        if self._playwright:
            await self._playwright.stop()
        self._browser = None
        self._context = None
        self._playwright = None
        self._pages.clear()
        return {"ok": True}

    async def new_tab(self, url: str = "about:blank", tab_id: Optional[str] = None) -> dict:
        if not self._context:
            return {"ok": False, "error": "Browser not launched"}
        page = await self._context.new_page()
        if url != "about:blank":
            await page.goto(url, wait_until="domcontentloaded", timeout=30000)
        tid = tab_id or f"tab_{len(self._pages)}"
        self._pages[tid] = page
        return {"ok": True, "tab_id": tid, "url": page.url, "title": await page.title()}

    async def close_tab(self, tab_id: str) -> dict:
        page = self._pages.pop(tab_id, None)
        if not page:
            return {"ok": False, "error": f"Tab {tab_id} not found"}
        await page.close()
        return {"ok": True, "tab_id": tab_id}

    async def navigate(self, tab_id: str, url: str) -> dict:
        page = self._pages.get(tab_id)
        if not page:
            return {"ok": False, "error": f"Tab {tab_id} not found"}
        await page.goto(url, wait_until="domcontentloaded", timeout=30000)
        return {"ok": True, "url": page.url, "title": await page.title()}

    async def click(self, tab_id: str, selector: str) -> dict:
        page = self._pages.get(tab_id)
        if not page:
            return {"ok": False, "error": f"Tab {tab_id} not found"}
        await page.click(selector, timeout=10000)
        return {"ok": True, "selector": selector}

    async def fill(self, tab_id: str, selector: str, value: str) -> dict:
        page = self._pages.get(tab_id)
        if not page:
            return {"ok": False, "error": f"Tab {tab_id} not found"}
        await page.fill(selector, value, timeout=10000)
        return {"ok": True, "selector": selector}

    async def type_text(self, tab_id: str, selector: str, text: str, delay: float = 50) -> dict:
        """Type text character by character (more human-like than fill)."""
        page = self._pages.get(tab_id)
        if not page:
            return {"ok": False, "error": f"Tab {tab_id} not found"}
        await page.type(selector, text, delay=delay)
        return {"ok": True, "selector": selector}

    async def press_key(self, tab_id: str, key: str) -> dict:
        page = self._pages.get(tab_id)
        if not page:
            return {"ok": False, "error": f"Tab {tab_id} not found"}
        await page.keyboard.press(key)
        return {"ok": True, "key": key}

    async def screenshot_tab(self, tab_id: str, full_page: bool = False) -> dict:
        page = self._pages.get(tab_id)
        if not page:
            return {"ok": False, "error": f"Tab {tab_id} not found"}
        data = await page.screenshot(full_page=full_page)
        return {
            "ok": True,
            "image_base64": base64.b64encode(data).decode(),
            "format": "png",
            "size": len(data),
        }

    async def get_text(self, tab_id: str, selector: str = "body") -> dict:
        page = self._pages.get(tab_id)
        if not page:
            return {"ok": False, "error": f"Tab {tab_id} not found"}
        text = await page.inner_text(selector, timeout=10000)
        return {"ok": True, "text": text[:10000]}  # cap at 10k chars

    async def get_html(self, tab_id: str, selector: str = "body") -> dict:
        page = self._pages.get(tab_id)
        if not page:
            return {"ok": False, "error": f"Tab {tab_id} not found"}
        html = await page.inner_html(selector, timeout=10000)
        return {"ok": True, "html": html[:50000]}

    async def evaluate(self, tab_id: str, js: str) -> dict:
        """Run arbitrary JavaScript in a tab."""
        page = self._pages.get(tab_id)
        if not page:
            return {"ok": False, "error": f"Tab {tab_id} not found"}
        result = await page.evaluate(js)
        return {"ok": True, "result": result}

    async def wait_for_selector(self, tab_id: str, selector: str, timeout: int = 10000) -> dict:
        page = self._pages.get(tab_id)
        if not page:
            return {"ok": False, "error": f"Tab {tab_id} not found"}
        await page.wait_for_selector(selector, timeout=timeout)
        return {"ok": True, "selector": selector}

    async def list_tabs(self) -> dict:
        tabs = []
        for tid, page in self._pages.items():
            tabs.append({"tab_id": tid, "url": page.url, "title": await page.title()})
        return {"ok": True, "tabs": tabs}


# Global browser instance
browser = BrowserController()


# ─── Shell Execution ─────────────────────────────────────────

async def run_shell(command: str, timeout: int = 30) -> dict:
    """Run a shell command and return output."""
    try:
        proc = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        return {
            "ok": proc.returncode == 0,
            "returncode": proc.returncode,
            "stdout": stdout.decode(errors="replace")[:50000],
            "stderr": stderr.decode(errors="replace")[:10000],
        }
    except asyncio.TimeoutError:
        proc.kill()
        return {"ok": False, "error": f"Command timed out after {timeout}s"}


# ─── Clipboard ───────────────────────────────────────────────

async def get_clipboard() -> dict:
    result = await run_shell("pbpaste")
    return {"ok": True, "content": result.get("stdout", "")}


async def set_clipboard(text: str) -> dict:
    proc = await asyncio.create_subprocess_exec(
        "pbcopy",
        stdin=asyncio.subprocess.PIPE,
    )
    await proc.communicate(input=text.encode())
    return {"ok": True}


# ─── File System Helpers ─────────────────────────────────────

async def open_file(path: str) -> dict:
    """Open a file with its default application."""
    proc = await asyncio.create_subprocess_exec(
        "open", path,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await proc.communicate()
    if proc.returncode != 0:
        return {"ok": False, "error": stderr.decode().strip()}
    return {"ok": True, "path": path}


async def open_url(url: str) -> dict:
    """Open a URL in the default browser."""
    proc = await asyncio.create_subprocess_exec(
        "open", url,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    await proc.communicate()
    return {"ok": True, "url": url}
