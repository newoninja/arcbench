"""SQLite database layer for ArcBench — users, refresh tokens, and terminal metadata."""

from __future__ import annotations

import aiosqlite
from pathlib import Path

DB_PATH = Path(__file__).parent.parent / "arcbench.db"

_db: aiosqlite.Connection | None = None


async def init_db():
    """Initialize database and create tables."""
    global _db
    _db = await aiosqlite.connect(str(DB_PATH))
    _db.row_factory = aiosqlite.Row

    await _db.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            firebase_uid TEXT UNIQUE,
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS refresh_tokens (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            token_hash TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            revoked INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_refresh_user ON refresh_tokens(user_id);
        CREATE TABLE IF NOT EXISTS terminals (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            working_dir TEXT NOT NULL,
            mode TEXT NOT NULL DEFAULT 'claude',
            created_at TEXT NOT NULL,
            last_active TEXT NOT NULL,
            is_alive INTEGER NOT NULL DEFAULT 1,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );
        CREATE TABLE IF NOT EXISTS sparks (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            terminal_id TEXT,
            agent_slug TEXT NOT NULL,
            agent_name TEXT,
            content TEXT NOT NULL,
            chip_label TEXT,
            working_dir TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'building',
            revision_count INTEGER NOT NULL DEFAULT 0,
            review_summary TEXT,
            preview_url TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );
        CREATE INDEX IF NOT EXISTS idx_sparks_user ON sparks(user_id);
        CREATE TABLE IF NOT EXISTS device_tokens (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            token TEXT NOT NULL UNIQUE,
            platform TEXT NOT NULL DEFAULT 'fcm',
            created_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );
        CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);
        CREATE TABLE IF NOT EXISTS notifications (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            data TEXT,
            read INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );
        CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
    """)
    await _db.commit()

    # -- Schema migrations for existing databases --
    await _run_migrations(_db)

    # Create indexes that depend on migrated columns (must run after migrations)
    try:
        await _db.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users(username) WHERE firebase_uid IS NULL"
        )
        await _db.commit()
    except Exception:
        pass  # Index already exists or column still missing


async def _run_migrations(db):
    """Add columns that may be missing in older databases."""
    migrations = [
        ("users", "firebase_uid", "ALTER TABLE users ADD COLUMN firebase_uid TEXT UNIQUE"),
        ("sparks", "agent_name", "ALTER TABLE sparks ADD COLUMN agent_name TEXT"),
        ("sparks", "revision_count", "ALTER TABLE sparks ADD COLUMN revision_count INTEGER NOT NULL DEFAULT 0"),
        ("sparks", "review_summary", "ALTER TABLE sparks ADD COLUMN review_summary TEXT"),
        ("sparks", "preview_url", "ALTER TABLE sparks ADD COLUMN preview_url TEXT"),
    ]
    for table, column, sql in migrations:
        try:
            async with db.execute(f"PRAGMA table_info({table})") as cur:
                cols = [row[1] for row in await cur.fetchall()]
            if column not in cols:
                await db.execute(sql)
        except Exception:
            pass  # Column already exists or table doesn't exist yet
    await db.commit()


async def close_db():
    """Close the database connection."""
    global _db
    if _db:
        await _db.close()
        _db = None


def get_db() -> aiosqlite.Connection:
    """Get the database connection."""
    assert _db is not None, "Database not initialized"
    return _db


# -- User CRUD --

async def create_user(user_id: str, username: str, password_hash: str, created_at: str):
    db = get_db()
    await db.execute(
        "INSERT INTO users (id, username, password_hash, created_at) VALUES (?, ?, ?, ?)",
        (user_id, username, password_hash, created_at),
    )
    await db.commit()


async def get_user_by_username(username: str) -> dict | None:
    db = get_db()
    async with db.execute("SELECT * FROM users WHERE username = ?", (username,)) as cur:
        row = await cur.fetchone()
        return dict(row) if row else None


async def get_user_by_id(user_id: str) -> dict | None:
    db = get_db()
    async with db.execute("SELECT * FROM users WHERE id = ?", (user_id,)) as cur:
        row = await cur.fetchone()
        return dict(row) if row else None


async def count_users() -> int:
    db = get_db()
    async with db.execute("SELECT COUNT(*) as c FROM users") as cur:
        row = await cur.fetchone()
        return row["c"]


# -- Refresh token CRUD --

async def save_refresh_token(
    token_id: str, user_id: str, token_hash: str, expires_at: str, created_at: str
):
    db = get_db()
    await db.execute(
        "INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?)",
        (token_id, user_id, token_hash, expires_at, created_at),
    )
    await db.commit()


async def get_refresh_token(token_id: str) -> dict | None:
    db = get_db()
    async with db.execute(
        "SELECT * FROM refresh_tokens WHERE id = ? AND revoked = 0", (token_id,)
    ) as cur:
        row = await cur.fetchone()
        return dict(row) if row else None


async def revoke_refresh_token(token_id: str):
    db = get_db()
    await db.execute("UPDATE refresh_tokens SET revoked = 1 WHERE id = ?", (token_id,))
    await db.commit()


async def revoke_all_user_tokens(user_id: str):
    db = get_db()
    await db.execute("UPDATE refresh_tokens SET revoked = 1 WHERE user_id = ?", (user_id,))
    await db.commit()


async def cleanup_expired_tokens():
    """Remove expired refresh tokens."""
    from datetime import datetime, timezone

    db = get_db()
    now = datetime.now(timezone.utc).isoformat()
    await db.execute("DELETE FROM refresh_tokens WHERE expires_at < ? OR revoked = 1", (now,))
    await db.commit()


# -- Terminal metadata CRUD --

async def save_terminal(terminal_id: str, user_id: str, working_dir: str, created_at: str, mode: str = "claude"):
    db = get_db()
    await db.execute(
        "INSERT OR REPLACE INTO terminals (id, user_id, working_dir, mode, created_at, last_active, is_alive) VALUES (?, ?, ?, ?, ?, ?, 1)",
        (terminal_id, user_id, working_dir, mode, created_at, created_at),
    )
    await db.commit()


async def update_terminal_active(terminal_id: str):
    db = get_db()
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc).isoformat()
    await db.execute("UPDATE terminals SET last_active = ? WHERE id = ?", (now, terminal_id))
    await db.commit()


async def mark_terminal_dead(terminal_id: str):
    db = get_db()
    await db.execute("UPDATE terminals SET is_alive = 0 WHERE id = ?", (terminal_id,))
    await db.commit()


async def get_user_terminals(user_id: str) -> list[dict]:
    db = get_db()
    async with db.execute(
        "SELECT * FROM terminals WHERE user_id = ? ORDER BY created_at DESC", (user_id,)
    ) as cur:
        rows = await cur.fetchall()
        return [dict(r) for r in rows]


async def delete_terminal(terminal_id: str, user_id: str):
    db = get_db()
    await db.execute("DELETE FROM terminals WHERE id = ? AND user_id = ?", (terminal_id, user_id))
    await db.commit()


# -- Firebase user CRUD --

async def get_user_by_firebase_uid(firebase_uid: str) -> dict | None:
    db = get_db()
    async with db.execute("SELECT * FROM users WHERE firebase_uid = ?", (firebase_uid,)) as cur:
        row = await cur.fetchone()
        return dict(row) if row else None


async def create_firebase_user(
    user_id: str, username: str, password_hash: str, firebase_uid: str, created_at: str
):
    db = get_db()
    await db.execute(
        "INSERT INTO users (id, username, password_hash, firebase_uid, created_at) VALUES (?, ?, ?, ?, ?)",
        (user_id, username, password_hash, firebase_uid, created_at),
    )
    await db.commit()


# -- Spark CRUD --

async def get_spark_by_id(spark_id: str) -> dict | None:
    db = get_db()
    async with db.execute("SELECT * FROM sparks WHERE id = ?", (spark_id,)) as cur:
        row = await cur.fetchone()
        return dict(row) if row else None


async def get_user_sparks(user_id: str) -> list[dict]:
    db = get_db()
    async with db.execute(
        "SELECT * FROM sparks WHERE user_id = ? ORDER BY created_at DESC", (user_id,)
    ) as cur:
        rows = await cur.fetchall()
        return [dict(r) for r in rows]


async def delete_spark(spark_id: str, user_id: str):
    db = get_db()
    await db.execute("DELETE FROM sparks WHERE id = ? AND user_id = ?", (spark_id, user_id))
    await db.commit()


async def update_spark_status(spark_id: str, status: str):
    from datetime import datetime, timezone
    db = get_db()
    now = datetime.now(timezone.utc).isoformat()
    await db.execute(
        "UPDATE sparks SET status = ?, updated_at = ? WHERE id = ?",
        (status, now, spark_id),
    )
    await db.commit()


async def increment_spark_revision(spark_id: str) -> int:
    """Increment revision count and return the new count."""
    from datetime import datetime, timezone
    db = get_db()
    now = datetime.now(timezone.utc).isoformat()
    await db.execute(
        "UPDATE sparks SET revision_count = revision_count + 1, updated_at = ? WHERE id = ?",
        (now, spark_id),
    )
    await db.commit()
    spark = await get_spark_by_id(spark_id)
    return spark["revision_count"] if spark else 0


async def update_spark_review_summary(spark_id: str, summary: str):
    from datetime import datetime, timezone
    db = get_db()
    now = datetime.now(timezone.utc).isoformat()
    await db.execute(
        "UPDATE sparks SET review_summary = ?, updated_at = ? WHERE id = ?",
        (summary, now, spark_id),
    )
    await db.commit()


async def update_spark_preview_url(spark_id: str, preview_url: str):
    from datetime import datetime, timezone
    db = get_db()
    now = datetime.now(timezone.utc).isoformat()
    await db.execute(
        "UPDATE sparks SET preview_url = ?, updated_at = ? WHERE id = ?",
        (preview_url, now, spark_id),
    )
    await db.commit()


# -- Device token CRUD --

async def save_device_token(user_id: str, token: str, platform: str = "fcm"):
    from datetime import datetime, timezone
    db = get_db()
    now = datetime.now(timezone.utc).isoformat()
    await db.execute(
        """INSERT OR REPLACE INTO device_tokens (user_id, token, platform, created_at)
           VALUES (?, ?, ?, ?)""",
        (user_id, token, platform, now),
    )
    await db.commit()


async def delete_device_token(token: str):
    db = get_db()
    await db.execute("DELETE FROM device_tokens WHERE token = ?", (token,))
    await db.commit()


# -- Notification CRUD --

async def get_user_notifications(user_id: str, limit: int = 50) -> list[dict]:
    db = get_db()
    async with db.execute(
        "SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT ?",
        (user_id, limit),
    ) as cur:
        rows = await cur.fetchall()
        return [dict(r) for r in rows]


async def mark_notification_read(notification_id: str, user_id: str):
    db = get_db()
    await db.execute(
        "UPDATE notifications SET read = 1 WHERE id = ? AND user_id = ?",
        (notification_id, user_id),
    )
    await db.commit()
