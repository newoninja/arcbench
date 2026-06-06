"""
Computer Control API — Full macOS automation endpoints.
"""

from __future__ import annotations

from typing import Optional
from fastapi import APIRouter
from pydantic import BaseModel

from computer_control import (
    open_app, quit_app, list_running_apps, activate_app,
    run_applescript, take_screenshot,
    mouse_move, mouse_click, mouse_scroll,
    keyboard_type, keyboard_hotkey, keyboard_press, get_mouse_position,
    browser,
    run_shell, get_clipboard, set_clipboard,
    open_file, open_url,
)

router = APIRouter()


# ─── Request Models ──────────────────────────────────────────

class AppRequest(BaseModel):
    name: str

class AppleScriptRequest(BaseModel):
    script: str

class ScreenshotRequest(BaseModel):
    x: Optional[int] = None
    y: Optional[int] = None
    w: Optional[int] = None
    h: Optional[int] = None

class MouseMoveRequest(BaseModel):
    x: int
    y: int
    duration: float = 0.3

class MouseClickRequest(BaseModel):
    x: Optional[int] = None
    y: Optional[int] = None
    button: str = "left"
    clicks: int = 1

class MouseScrollRequest(BaseModel):
    amount: int
    x: Optional[int] = None
    y: Optional[int] = None

class TypeRequest(BaseModel):
    text: str
    interval: float = 0.02

class HotkeyRequest(BaseModel):
    keys: list[str]

class KeyRequest(BaseModel):
    key: str

class BrowserLaunchRequest(BaseModel):
    headless: bool = False
    browser_type: str = "chromium"

class TabRequest(BaseModel):
    url: str = "about:blank"
    tab_id: Optional[str] = None

class NavigateRequest(BaseModel):
    tab_id: str
    url: str

class ClickRequest(BaseModel):
    tab_id: str
    selector: str

class FillRequest(BaseModel):
    tab_id: str
    selector: str
    value: str

class BrowserTypeRequest(BaseModel):
    tab_id: str
    selector: str
    text: str
    delay: float = 50

class BrowserKeyRequest(BaseModel):
    tab_id: str
    key: str

class ScreenshotTabRequest(BaseModel):
    tab_id: str
    full_page: bool = False

class GetTextRequest(BaseModel):
    tab_id: str
    selector: str = "body"

class EvalRequest(BaseModel):
    tab_id: str
    js: str

class WaitRequest(BaseModel):
    tab_id: str
    selector: str
    timeout: int = 10000

class ShellRequest(BaseModel):
    command: str
    timeout: int = 30

class ClipboardRequest(BaseModel):
    text: str

class FileRequest(BaseModel):
    path: str

class UrlRequest(BaseModel):
    url: str

class TabIdRequest(BaseModel):
    tab_id: str


# ─── App Control ─────────────────────────────────────────────

@router.post("/app/open")
async def api_open_app(req: AppRequest):
    return await open_app(req.name)

@router.post("/app/quit")
async def api_quit_app(req: AppRequest):
    return await quit_app(req.name)

@router.get("/app/list")
async def api_list_apps():
    return await list_running_apps()

@router.post("/app/activate")
async def api_activate_app(req: AppRequest):
    return await activate_app(req.name)


# ─── AppleScript ─────────────────────────────────────────────

@router.post("/applescript")
async def api_applescript(req: AppleScriptRequest):
    return await run_applescript(req.script)


# ─── Screenshot ──────────────────────────────────────────────

@router.post("/screenshot")
async def api_screenshot(req: ScreenshotRequest):
    region = None
    if req.x is not None and req.y is not None and req.w is not None and req.h is not None:
        region = {"x": req.x, "y": req.y, "w": req.w, "h": req.h}
    return await take_screenshot(region)


# ─── Mouse ───────────────────────────────────────────────────

@router.post("/mouse/move")
async def api_mouse_move(req: MouseMoveRequest):
    return await mouse_move(req.x, req.y, req.duration)

@router.post("/mouse/click")
async def api_mouse_click(req: MouseClickRequest):
    return await mouse_click(req.x, req.y, req.button, req.clicks)

@router.post("/mouse/scroll")
async def api_mouse_scroll(req: MouseScrollRequest):
    return await mouse_scroll(req.amount, req.x, req.y)

@router.get("/mouse/position")
async def api_mouse_position():
    return await get_mouse_position()


# ─── Keyboard ────────────────────────────────────────────────

@router.post("/keyboard/type")
async def api_keyboard_type(req: TypeRequest):
    return await keyboard_type(req.text, req.interval)

@router.post("/keyboard/hotkey")
async def api_keyboard_hotkey(req: HotkeyRequest):
    return await keyboard_hotkey(*req.keys)

@router.post("/keyboard/press")
async def api_keyboard_press(req: KeyRequest):
    return await keyboard_press(req.key)


# ─── Browser ─────────────────────────────────────────────────

@router.post("/browser/launch")
async def api_browser_launch(req: BrowserLaunchRequest):
    return await browser.launch(req.headless, req.browser_type)

@router.post("/browser/close")
async def api_browser_close():
    return await browser.close()

@router.post("/browser/tab/new")
async def api_browser_new_tab(req: TabRequest):
    return await browser.new_tab(req.url, req.tab_id)

@router.post("/browser/tab/close")
async def api_browser_tab_close(req: TabIdRequest):
    return await browser.close_tab(req.tab_id)

@router.get("/browser/tabs")
async def api_browser_tabs():
    return await browser.list_tabs()

@router.post("/browser/navigate")
async def api_browser_navigate(req: NavigateRequest):
    return await browser.navigate(req.tab_id, req.url)

@router.post("/browser/click")
async def api_browser_click(req: ClickRequest):
    return await browser.click(req.tab_id, req.selector)

@router.post("/browser/fill")
async def api_browser_fill(req: FillRequest):
    return await browser.fill(req.tab_id, req.selector, req.value)

@router.post("/browser/type")
async def api_browser_type(req: BrowserTypeRequest):
    return await browser.type_text(req.tab_id, req.selector, req.text, req.delay)

@router.post("/browser/key")
async def api_browser_key(req: BrowserKeyRequest):
    return await browser.press_key(req.tab_id, req.key)

@router.post("/browser/screenshot")
async def api_browser_screenshot(req: ScreenshotTabRequest):
    return await browser.screenshot_tab(req.tab_id, req.full_page)

@router.post("/browser/text")
async def api_browser_text(req: GetTextRequest):
    return await browser.get_text(req.tab_id, req.selector)

@router.post("/browser/html")
async def api_browser_html(req: GetTextRequest):
    return await browser.get_html(req.tab_id, req.selector)

@router.post("/browser/eval")
async def api_browser_eval(req: EvalRequest):
    return await browser.evaluate(req.tab_id, req.js)

@router.post("/browser/wait")
async def api_browser_wait(req: WaitRequest):
    return await browser.wait_for_selector(req.tab_id, req.selector, req.timeout)


# ─── Shell ───────────────────────────────────────────────────

@router.post("/shell")
async def api_shell(req: ShellRequest):
    return await run_shell(req.command, req.timeout)


# ─── Clipboard ───────────────────────────────────────────────

@router.get("/clipboard")
async def api_get_clipboard():
    return await get_clipboard()

@router.post("/clipboard")
async def api_set_clipboard(req: ClipboardRequest):
    return await set_clipboard(req.text)


# ─── File / URL ──────────────────────────────────────────────

@router.post("/open/file")
async def api_open_file(req: FileRequest):
    return await open_file(req.path)

@router.post("/open/url")
async def api_open_url(req: UrlRequest):
    return await open_url(req.url)
