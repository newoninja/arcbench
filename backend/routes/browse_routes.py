"""File browser routes — list, read, write, upload with path-traversal protection."""

from __future__ import annotations

import os
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from auth import get_current_user
from models import (
    DirectoryListing,
    FileEntry,
    FileReadResponse,
    FileWriteRequest,
    FileWriteResponse,
)

router = APIRouter()

# Configurable allowed roots — everything must resolve under one of these.
# Default: user's home directory. Override via ARCBENCH_ALLOWED_ROOTS env var.
_allowed_roots: list[Path] = []


def _get_allowed_roots() -> list[Path]:
    global _allowed_roots
    if not _allowed_roots:
        env = os.getenv("ARCBENCH_ALLOWED_ROOTS", "")
        if env:
            _allowed_roots = [Path(p).expanduser().resolve() for p in env.split(":") if p]
        else:
            _allowed_roots = [Path.home()]
    return _allowed_roots


def _safe_resolve(p: str) -> Path:
    """Expand ~ and resolve, then enforce path-traversal protection."""
    resolved = Path(os.path.expanduser(p)).resolve()

    for root in _get_allowed_roots():
        try:
            resolved.relative_to(root)
            return resolved
        except ValueError:
            continue

    raise HTTPException(
        status_code=403,
        detail=f"Access denied: path must be under {[str(r) for r in _get_allowed_roots()]}",
    )


MAX_READ_SIZE = 10 * 1024 * 1024  # 10MB
MAX_UPLOAD_SIZE = 50 * 1024 * 1024  # 50MB


@router.get("", response_model=DirectoryListing)
async def browse_directory(
    path: str = Query(default="~", description="Directory path to list"),
    show_hidden: bool = Query(default=False),
    user: dict = Depends(get_current_user),
):
    """List contents of a directory. Folders first, then files."""
    target = _safe_resolve(path)

    if not target.exists():
        raise HTTPException(status_code=404, detail=f"Path not found: {path}")
    if not target.is_dir():
        raise HTTPException(status_code=400, detail=f"Not a directory: {path}")

    try:
        entries = list(target.iterdir())
    except PermissionError:
        raise HTTPException(status_code=403, detail=f"Permission denied: {path}")

    items = []
    for entry in sorted(entries, key=lambda e: (not e.is_dir(), e.name.lower())):
        if not show_hidden and entry.name.startswith("."):
            continue
        try:
            s = entry.stat()
            items.append(FileEntry(
                name=entry.name,
                path=str(entry),
                is_dir=entry.is_dir(),
                size=s.st_size if not entry.is_dir() else None,
            ))
        except (PermissionError, OSError):
            continue

    return DirectoryListing(
        path=str(target),
        parent=str(target.parent) if target != target.parent else None,
        items=items,
    )


@router.get("/read", response_model=FileReadResponse)
async def read_file(
    path: str = Query(description="File path to read"),
    user: dict = Depends(get_current_user),
):
    """Read a file's contents as UTF-8 text."""
    target = _safe_resolve(path)

    if not target.exists():
        raise HTTPException(status_code=404, detail="File not found")
    if not target.is_file():
        raise HTTPException(status_code=400, detail="Not a regular file")
    if target.stat().st_size > MAX_READ_SIZE:
        raise HTTPException(status_code=413, detail=f"File too large (max {MAX_READ_SIZE // 1024 // 1024}MB)")

    try:
        content = target.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        raise HTTPException(status_code=415, detail="File is not valid UTF-8 text")
    except PermissionError:
        raise HTTPException(status_code=403, detail="Permission denied")

    return FileReadResponse(path=str(target), content=content, size=len(content))


@router.put("/write", response_model=FileWriteResponse)
async def write_file(
    req: FileWriteRequest,
    user: dict = Depends(get_current_user),
):
    """Write content to a file (creates parent dirs if needed)."""
    target = _safe_resolve(req.path)

    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(req.content, encoding="utf-8")
    except PermissionError:
        raise HTTPException(status_code=403, detail="Permission denied")

    return FileWriteResponse(path=str(target), size=len(req.content))


@router.post("/upload")
async def upload_file(
    path: str = Query(description="Destination directory"),
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    """Upload a file to a directory on the host."""
    target_dir = _safe_resolve(path)

    if not target_dir.is_dir():
        raise HTTPException(status_code=400, detail="Destination must be a directory")

    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename provided")

    # Sanitize filename — strip path separators
    safe_name = Path(file.filename).name
    if not safe_name or safe_name.startswith("."):
        raise HTTPException(status_code=400, detail="Invalid filename")

    dest = target_dir / safe_name
    # Re-check resolved dest is still under allowed roots
    _safe_resolve(str(dest))

    content = await file.read()
    if len(content) > MAX_UPLOAD_SIZE:
        raise HTTPException(status_code=413, detail=f"File too large (max {MAX_UPLOAD_SIZE // 1024 // 1024}MB)")

    try:
        dest.write_bytes(content)
    except PermissionError:
        raise HTTPException(status_code=403, detail="Permission denied")

    return {
        "path": str(dest),
        "filename": safe_name,
        "size": len(content),
    }


@router.get("/bookmarks")
async def get_bookmarks(user: dict = Depends(get_current_user)):
    """Return common quick-access directories."""
    home = Path.home()
    bookmarks = []

    candidates = [
        ("Home", home),
        ("Desktop", home / "Desktop"),
        ("Documents", home / "Documents"),
        ("Downloads", home / "Downloads"),
        ("Projects", home / "Projects"),
        ("Developer", home / "Developer"),
        ("Code", home / "code"),
        ("repos", home / "repos"),
    ]

    for label, p in candidates:
        if p.exists() and p.is_dir():
            bookmarks.append({"label": label, "path": str(p)})

    return {"bookmarks": bookmarks}
