"""Device token & notification REST endpoints."""

from fastapi import APIRouter, Depends, HTTPException
from auth import get_current_user
from models import DeviceTokenRequest, NotificationResponse
import database

router = APIRouter()


@router.post("/register")
async def register_device(req: DeviceTokenRequest, user: dict = Depends(get_current_user)):
    """Register a device token for push notifications."""
    await database.save_device_token(user["id"], req.token, req.platform)
    return {"status": "registered"}


@router.delete("/{token}")
async def unregister_device(token: str, user: dict = Depends(get_current_user)):
    """Remove a device token."""
    await database.delete_device_token(token)
    return {"status": "unregistered"}


@router.get("/notifications", response_model=list[NotificationResponse])
async def get_notifications(user: dict = Depends(get_current_user)):
    """Get notifications for the authenticated user."""
    rows = await database.get_user_notifications(user["id"])
    return [
        NotificationResponse(
            id=n["id"],
            user_id=n["user_id"],
            title=n["title"],
            body=n["body"],
            data=n.get("data"),
            read=bool(n["read"]),
            created_at=n["created_at"],
        )
        for n in rows
    ]


@router.post("/notifications/{notification_id}/read")
async def read_notification(notification_id: str, user: dict = Depends(get_current_user)):
    """Mark a notification as read."""
    await database.mark_notification_read(notification_id, user["id"])
    return {"status": "read"}
