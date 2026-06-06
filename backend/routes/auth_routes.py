"""Auth REST endpoints — register, login, refresh, logout, me, firebase-exchange."""

from fastapi import APIRouter, Depends
from auth import (
    register_user,
    login_user,
    get_current_user,
    validate_refresh_token,
    create_access_token,
    create_refresh_token,
    revoke_all_user_tokens,
    exchange_firebase_token,
)
from models import RegisterRequest, LoginRequest, TokenResponse, RefreshRequest, UserInfo, FirebaseExchangeRequest

router = APIRouter()


@router.post("/register", response_model=TokenResponse)
async def register(req: RegisterRequest):
    """Create a new account. Returns access + refresh tokens."""
    user, access, refresh = await register_user(req.username, req.password)
    return TokenResponse(
        access_token=access,
        refresh_token=refresh,
        username=user["username"],
        user_id=user["id"],
    )


@router.post("/login", response_model=TokenResponse)
async def login(req: LoginRequest):
    """Log in and get access + refresh tokens."""
    user, access, refresh = await login_user(req.username, req.password)
    return TokenResponse(
        access_token=access,
        refresh_token=refresh,
        username=user["username"],
        user_id=user["id"],
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh(req: RefreshRequest):
    """Exchange a refresh token for a new access + refresh token pair (rotation)."""
    user = await validate_refresh_token(req.refresh_token)
    access = create_access_token(user["id"], user["username"])
    new_refresh = await create_refresh_token(user["id"])
    return TokenResponse(
        access_token=access,
        refresh_token=new_refresh,
        username=user["username"],
        user_id=user["id"],
    )


@router.post("/logout")
async def logout(user: dict = Depends(get_current_user)):
    """Revoke all refresh tokens for this user."""
    await revoke_all_user_tokens(user["id"])
    return {"status": "logged_out"}


@router.post("/firebase-exchange", response_model=TokenResponse)
async def firebase_exchange(req: FirebaseExchangeRequest):
    """Exchange a Firebase ID token for backend JWT access + refresh tokens."""
    user, access, refresh = await exchange_firebase_token(req.id_token)
    return TokenResponse(
        access_token=access,
        refresh_token=refresh,
        username=user["username"],
        user_id=user["id"],
    )


@router.get("/me", response_model=UserInfo)
async def me(user: dict = Depends(get_current_user)):
    """Get current user info."""
    return UserInfo(
        user_id=user["id"],
        username=user["username"],
        created_at=user["created_at"],
    )
