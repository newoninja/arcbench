"""Spark REST endpoints — list, get, retry, cancel, delete."""

from fastapi import APIRouter, Depends, HTTPException
from auth import get_current_user
from models import SparkResponse
import database

router = APIRouter()


def _spark_to_response(spark: dict) -> SparkResponse:
    return SparkResponse(
        id=spark["id"],
        user_id=spark["user_id"],
        terminal_id=spark.get("terminal_id"),
        agent_slug=spark["agent_slug"],
        agent_name=spark.get("agent_name"),
        content=spark["content"],
        chip_label=spark.get("chip_label"),
        working_dir=spark["working_dir"],
        status=spark["status"],
        revision_count=spark.get("revision_count", 0),
        review_summary=spark.get("review_summary"),
        preview_url=spark.get("preview_url"),
        created_at=spark["created_at"],
        updated_at=spark["updated_at"],
    )


@router.get("", response_model=list[SparkResponse])
async def list_sparks(user: dict = Depends(get_current_user)):
    """Get all sparks for the authenticated user."""
    sparks = await database.get_user_sparks(user["id"])
    return [_spark_to_response(s) for s in sparks]


@router.get("/{spark_id}", response_model=SparkResponse)
async def get_spark(spark_id: str, user: dict = Depends(get_current_user)):
    """Get a specific spark by ID."""
    spark = await database.get_spark_by_id(spark_id)
    if not spark or spark["user_id"] != user["id"]:
        raise HTTPException(status_code=404, detail="Spark not found")
    return _spark_to_response(spark)


@router.post("/{spark_id}/retry")
async def retry_spark(spark_id: str, user: dict = Depends(get_current_user)):
    """Retry a failed or timed-out spark (re-dispatch it)."""
    spark = await database.get_spark_by_id(spark_id)
    if not spark or spark["user_id"] != user["id"]:
        raise HTTPException(status_code=404, detail="Spark not found")
    if spark["status"] not in ("failed", "timeout", "review_failed", "needs_revision", "cancelled"):
        raise HTTPException(status_code=400, detail=f"Cannot retry spark in '{spark['status']}' state")

    # Reset status to building — the dispatcher will be called by the WS handler
    await database.update_spark_status(spark_id, "pending_retry")
    return {"status": "pending_retry", "spark_id": spark_id}


@router.post("/{spark_id}/cancel")
async def cancel_spark(spark_id: str, user: dict = Depends(get_current_user)):
    """Cancel a running spark."""
    spark = await database.get_spark_by_id(spark_id)
    if not spark or spark["user_id"] != user["id"]:
        raise HTTPException(status_code=404, detail="Spark not found")
    if spark["status"] not in ("building", "reviewing", "revising"):
        raise HTTPException(status_code=400, detail=f"Cannot cancel spark in '{spark['status']}' state")

    await database.update_spark_status(spark_id, "cancelled")
    return {"status": "cancelled", "spark_id": spark_id}


@router.delete("/{spark_id}")
async def delete_spark(spark_id: str, user: dict = Depends(get_current_user)):
    """Delete a spark record."""
    spark = await database.get_spark_by_id(spark_id)
    if not spark or spark["user_id"] != user["id"]:
        raise HTTPException(status_code=404, detail="Spark not found")

    await database.delete_spark(spark_id, user["id"])
    return {"status": "deleted", "spark_id": spark_id}
