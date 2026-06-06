"""Authentication — JWT access tokens + bcrypt + 30-day refresh tokens (SQLite-backed).

Also supports Firebase ID token exchange: phone authenticates with Firebase,
sends the ID token to POST /auth/firebase-exchange, gets a backend JWT pair.
"""

from __future__ import annotations

import hashlib
import logging
import os
import secrets
import uuid
from datetime import datetime, timezone, timedelta
from typing import Optional

import bcrypt
from jose import JWTError, jwt
from fastapi import Depends, HTTPException, status, WebSocket
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

logger = logging.getLogger("arcbench.auth")

from database import (
    create_user,
    get_user_by_username,
    get_user_by_id,
    get_user_by_firebase_uid,
    save_refresh_token,
    get_refresh_token,
    revoke_refresh_token,
    revoke_all_user_tokens,
)

# Config
JWT_SECRET = os.getenv("JWT_SECRET", "arcbench-dev-secret-change-in-production")
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60  # short-lived access token
REFRESH_TOKEN_EXPIRE_DAYS = 30

security = HTTPBearer(auto_error=False)


# -- Password hashing --

def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode(), hashed.encode())


# -- JWT access tokens --

def create_access_token(user_id: str, username: str) -> str:
    payload = {
        "sub": user_id,
        "username": username,
        "type": "access",
        "exp": datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_token(token: str) -> dict:
    """Decode and validate a JWT. Raises on invalid/expired."""
    return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])


# -- Refresh tokens (opaque, hashed in DB) --

def _hash_refresh(raw_token: str) -> str:
    """SHA-256 hash of the raw refresh token for DB storage."""
    return hashlib.sha256(raw_token.encode()).hexdigest()


async def create_refresh_token(user_id: str) -> str:
    """Generate and persist a 30-day refresh token. Returns the raw token string."""
    raw = secrets.token_urlsafe(48)
    token_id = uuid.uuid4().hex
    now = datetime.now(timezone.utc)
    expires = now + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)

    await save_refresh_token(
        token_id=token_id,
        user_id=user_id,
        token_hash=_hash_refresh(raw),
        expires_at=expires.isoformat(),
        created_at=now.isoformat(),
    )
    # Encode token_id + raw secret so we can look up the row later
    return f"{token_id}:{raw}"


async def validate_refresh_token(compound_token: str) -> dict:
    """Validate a refresh token. Returns the user dict. Revokes the used token (rotation)."""
    if ":" not in compound_token:
        raise HTTPException(status_code=401, detail="Malformed refresh token")

    token_id, raw = compound_token.split(":", 1)
    row = await get_refresh_token(token_id)
    if not row:
        raise HTTPException(status_code=401, detail="Refresh token revoked or not found")

    # Check hash matches
    if _hash_refresh(raw) != row["token_hash"]:
        # Possible token theft — revoke all tokens for this user
        await revoke_all_user_tokens(row["user_id"])
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    # Check expiry
    expires = datetime.fromisoformat(row["expires_at"])
    if datetime.now(timezone.utc) > expires:
        await revoke_refresh_token(token_id)
        raise HTTPException(status_code=401, detail="Refresh token expired")

    # Rotate: revoke old, caller will issue new
    await revoke_refresh_token(token_id)

    user = await get_user_by_id(row["user_id"])
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user


# -- FastAPI dependencies --

async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
) -> dict:
    """Extract user from JWT in Authorization header. Returns user dict."""
    if not credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")

    try:
        payload = decode_token(credentials.credentials)
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token")
        if payload.get("type") != "access":
            raise HTTPException(status_code=401, detail="Expected access token")
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    user = await get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user


async def get_ws_user(token: str) -> Optional[dict]:
    """Validate a JWT from WebSocket query param. Returns user dict or None."""
    try:
        payload = decode_token(token)
        user_id = payload.get("sub")
        if not user_id:
            return None
        return await get_user_by_id(user_id)
    except (JWTError, Exception):
        return None


# -- Registration / Login logic --

async def register_user(username: str, password: str) -> tuple[dict, str, str]:
    """Register a new user. Returns (user_dict, access_token, refresh_token)."""
    existing = await get_user_by_username(username)
    if existing:
        raise HTTPException(status_code=409, detail="Username already taken")

    user_id = uuid.uuid4().hex
    pw_hash = hash_password(password)
    now = datetime.now(timezone.utc).isoformat()

    await create_user(user_id, username, pw_hash, now)

    access = create_access_token(user_id, username)
    refresh = await create_refresh_token(user_id)

    return {"id": user_id, "username": username, "created_at": now}, access, refresh


async def login_user(username: str, password: str) -> tuple[dict, str, str]:
    """Login a user. Returns (user_dict, access_token, refresh_token)."""
    user = await get_user_by_username(username)
    if not user or not verify_password(password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid username or password")

    access = create_access_token(user["id"], user["username"])
    refresh = await create_refresh_token(user["id"])

    return user, access, refresh


# -- Firebase token exchange --

_firebase_app_auth = None
_firebase_init_done = False


def _ensure_firebase():
    """Lazy-init Firebase Admin SDK for ID token verification."""
    global _firebase_app_auth, _firebase_init_done
    if _firebase_init_done:
        return
    _firebase_init_done = True

    sa_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
    try:
        import firebase_admin
        from firebase_admin import credentials

        if sa_path and os.path.exists(sa_path):
            cred = credentials.Certificate(sa_path)
            _firebase_app_auth = firebase_admin.initialize_app(cred, name="arcbench-auth")
        else:
            # Use default credentials / Application Default Credentials
            _firebase_app_auth = firebase_admin.initialize_app(name="arcbench-auth")
        logger.info("Firebase Admin SDK initialized for token verification")
    except Exception as e:
        logger.warning(f"Firebase Admin init failed (token exchange will be unavailable): {e}")


async def verify_firebase_token(id_token: str) -> dict:
    """
    Verify a Firebase ID token and return the decoded claims.
    Raises HTTPException on failure.
    """
    _ensure_firebase()
    if _firebase_app_auth is None:
        raise HTTPException(status_code=503, detail="Firebase not configured on server")

    try:
        from firebase_admin import auth as fb_auth
        decoded = fb_auth.verify_id_token(id_token, app=_firebase_app_auth)
        return decoded
    except Exception as e:
        logger.warning(f"Firebase token verification failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid Firebase ID token")


async def get_or_create_firebase_user(firebase_claims: dict) -> dict:
    """
    Bridge a Firebase UID to a local ArcBench user.
    Creates the user if they don't exist yet.
    Returns the local user dict.
    """
    firebase_uid = firebase_claims["uid"]
    email = firebase_claims.get("email", "")
    display_name = firebase_claims.get("name", "") or email.split("@")[0]

    # Try to find existing user by firebase_uid
    user = await get_user_by_firebase_uid(firebase_uid)
    if user:
        return user

    # Create a new local user linked to this Firebase UID
    user_id = uuid.uuid4().hex
    now = datetime.now(timezone.utc).isoformat()
    # Use a random password hash since Firebase handles auth
    dummy_hash = hash_password(secrets.token_urlsafe(32))

    from database import create_firebase_user
    await create_firebase_user(
        user_id=user_id,
        username=display_name,
        password_hash=dummy_hash,
        firebase_uid=firebase_uid,
        created_at=now,
    )

    user = await get_user_by_firebase_uid(firebase_uid)
    if not user:
        raise HTTPException(status_code=500, detail="Failed to create user")
    logger.info(f"Created local user {user_id} for Firebase UID {firebase_uid}")
    return user


async def exchange_firebase_token(id_token: str) -> tuple[dict, str, str]:
    """
    Full Firebase token exchange flow:
    1. Verify the Firebase ID token
    2. Get or create the local user
    3. Issue backend JWT + refresh token

    Returns (user_dict, access_token, refresh_token).
    """
    claims = await verify_firebase_token(id_token)
    user = await get_or_create_firebase_user(claims)

    access = create_access_token(user["id"], user["username"])
    refresh = await create_refresh_token(user["id"])

    return user, access, refresh
