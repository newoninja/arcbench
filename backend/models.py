"""Pydantic models for ArcBench v2."""

from __future__ import annotations

from typing import Optional
from pydantic import BaseModel, Field


# -- Auth --

class RegisterRequest(BaseModel):
    username: str = Field(min_length=2, max_length=32)
    password: str = Field(min_length=6)


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    username: str
    user_id: str


class RefreshRequest(BaseModel):
    refresh_token: str


class FirebaseExchangeRequest(BaseModel):
    id_token: str


class UserInfo(BaseModel):
    user_id: str
    username: str
    created_at: str


# -- Terminals --

class CreateTerminalRequest(BaseModel):
    working_dir: str = Field(default="~")
    cols: int = Field(default=120, ge=40, le=400)
    rows: int = Field(default=40, ge=10, le=200)
    command: str = Field(default="claude", pattern=r"^(claude|shell)$")
    shell_path: Optional[str] = Field(default=None, pattern=r"^[a-zA-Z0-9_/.\- ]+$")


class TerminalInfo(BaseModel):
    id: str
    user_id: str
    working_dir: str
    mode: str = "claude"
    command: str = "claude"
    is_alive: bool
    created_at: str
    last_active: str


class TerminalListResponse(BaseModel):
    terminals: list[TerminalInfo]


class RunCommandRequest(BaseModel):
    command: str = Field(min_length=1, max_length=4096)


class SwitchModeRequest(BaseModel):
    mode: str = Field(pattern=r"^(claude|shell)$")
    cols: int = Field(default=120, ge=40, le=400)
    rows: int = Field(default=40, ge=10, le=200)
    shell_path: Optional[str] = Field(default=None, pattern=r"^[a-zA-Z0-9_/.\- ]+$")


# -- File browser --

class FileEntry(BaseModel):
    name: str
    path: str
    is_dir: bool
    size: Optional[int] = None


class DirectoryListing(BaseModel):
    path: str
    parent: Optional[str] = None
    items: list[FileEntry]


class FileReadResponse(BaseModel):
    path: str
    content: str
    size: int
    encoding: str = "utf-8"


class FileWriteRequest(BaseModel):
    path: str
    content: str


class FileWriteResponse(BaseModel):
    path: str
    size: int


# -- Status --

class StatusResponse(BaseModel):
    status: str = "ok"
    version: str = "2.1.0"
    hostname: str = ""
    active_terminals: int = 0
    total_users: int = 0
    uptime_seconds: float = 0.0
    cpu_percent: float = 0.0
    memory_mb: float = 0.0
    websocket_connections: int = 0
    unique_users_connected: int = 0
    terminal_subscriptions: int = 0


# -- Sparks --

class SparkResponse(BaseModel):
    id: str
    user_id: str
    terminal_id: Optional[str] = None
    agent_slug: str
    agent_name: Optional[str] = None
    content: str
    chip_label: Optional[str] = None
    working_dir: str
    status: str
    revision_count: int = 0
    review_summary: Optional[str] = None
    preview_url: Optional[str] = None
    created_at: str
    updated_at: str


# -- Device tokens --

class DeviceTokenRequest(BaseModel):
    token: str
    platform: str = "fcm"


# -- Notifications --

class NotificationResponse(BaseModel):
    id: str
    user_id: str
    title: str
    body: str
    data: Optional[str] = None
    read: bool = False
    created_at: str
