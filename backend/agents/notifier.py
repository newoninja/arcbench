"""
Push Notification Service — sends notifications via Firebase Cloud Messaging (FCM)
or falls back to APNs for iOS devices.

Requires:
  - FIREBASE_SERVICE_ACCOUNT_PATH env var pointing to a service account JSON
  - OR APNS_KEY_PATH + APNS_KEY_ID + APNS_TEAM_ID for direct APNs
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger("arcbench.agents.notifier")

# Firebase Admin SDK (lazy import to avoid hard dependency)
_firebase_app = None
_initialized = False


def _init_firebase():
    """Lazy-initialize Firebase Admin SDK."""
    global _firebase_app, _initialized
    if _initialized:
        return

    _initialized = True
    sa_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")

    if not sa_path or not Path(sa_path).exists():
        logger.warning(
            "FIREBASE_SERVICE_ACCOUNT_PATH not set or file missing — "
            "push notifications disabled"
        )
        return

    try:
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(sa_path)
        _firebase_app = firebase_admin.initialize_app(cred, name="arcbench-push")
        logger.info("Firebase Admin SDK initialized for push notifications")
    except ImportError:
        logger.warning(
            "firebase-admin not installed — push notifications disabled. "
            "Install with: pip install firebase-admin"
        )
    except Exception as e:
        logger.error(f"Firebase Admin init failed: {e}")


async def send_push_notification(
    user_id: str,
    title: str,
    body: str,
    data: Optional[dict[str, Any]] = None,
) -> bool:
    """
    Send a push notification to all of a user's registered devices.

    Looks up FCM tokens from the database, sends via Firebase Admin SDK.
    Falls back to logging if Firebase is not configured.

    Returns True if at least one notification was sent.
    """
    _init_firebase()

    # Get device tokens for this user
    tokens = await _get_device_tokens(user_id)
    if not tokens:
        logger.info(
            f"No device tokens for user {user_id} — "
            f"notification logged only: {title}"
        )
        # Log the notification so it can be polled via REST
        await _save_notification(user_id, title, body, data)
        return False

    if _firebase_app is None:
        logger.info(f"Firebase not configured — logging notification: {title}")
        await _save_notification(user_id, title, body, data)
        return False

    try:
        from firebase_admin import messaging

        sent_count = 0
        stale_tokens = []

        for token in tokens:
            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data={k: str(v) for k, v in (data or {}).items()},
                token=token,
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(
                            alert=messaging.ApsAlert(title=title, body=body),
                            sound="default",
                            badge=1,
                        ),
                    ),
                ),
            )

            try:
                messaging.send(message, app=_firebase_app)
                sent_count += 1
            except messaging.UnregisteredError:
                stale_tokens.append(token)
            except Exception as e:
                logger.error(f"FCM send failed for token {token[:20]}...: {e}")

        # Clean up stale tokens
        if stale_tokens:
            await _remove_device_tokens(user_id, stale_tokens)
            logger.info(f"Removed {len(stale_tokens)} stale FCM tokens for user {user_id}")

        logger.info(f"Sent {sent_count}/{len(tokens)} push notifications to user {user_id}")
        await _save_notification(user_id, title, body, data)
        return sent_count > 0

    except ImportError:
        logger.warning("firebase-admin not available for push")
        await _save_notification(user_id, title, body, data)
        return False
    except Exception as e:
        logger.exception(f"Push notification error: {e}")
        await _save_notification(user_id, title, body, data)
        return False


async def _get_device_tokens(user_id: str) -> list[str]:
    """Get all FCM device tokens for a user from the database."""
    try:
        import database
        db = database.get_db()
        async with db.execute(
            "SELECT token FROM device_tokens WHERE user_id = ?",
            (user_id,),
        ) as cur:
            rows = await cur.fetchall()
            return [row["token"] for row in rows]
    except Exception:
        return []


async def _remove_device_tokens(user_id: str, tokens: list[str]):
    """Remove stale device tokens."""
    try:
        import database
        db = database.get_db()
        for token in tokens:
            await db.execute(
                "DELETE FROM device_tokens WHERE user_id = ? AND token = ?",
                (user_id, token),
            )
        await db.commit()
    except Exception as e:
        logger.error(f"Failed to remove stale tokens: {e}")


async def _save_notification(
    user_id: str,
    title: str,
    body: str,
    data: Optional[dict[str, Any]] = None,
):
    """Save notification to DB so it can be polled via REST."""
    try:
        import database
        import uuid
        from datetime import datetime, timezone

        db = database.get_db()
        now = datetime.now(timezone.utc).isoformat()
        await db.execute(
            """INSERT INTO notifications (id, user_id, title, body, data, read, created_at)
               VALUES (?, ?, ?, ?, ?, 0, ?)""",
            (uuid.uuid4().hex[:12], user_id, title, body,
             json.dumps(data) if data else None, now),
        )
        await db.commit()
    except Exception as e:
        logger.error(f"Failed to save notification: {e}")
