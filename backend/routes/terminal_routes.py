"""Terminal REST endpoints — list, create, destroy, run_command, switch_mode."""

from fastapi import APIRouter, Depends, HTTPException, Request
from auth import get_current_user
from models import (
    CreateTerminalRequest, TerminalInfo, TerminalListResponse,
    RunCommandRequest, SwitchModeRequest,
)

router = APIRouter()


@router.get("", response_model=TerminalListResponse)
async def list_terminals(request: Request, user: dict = Depends(get_current_user)):
    """List all terminals for the current user."""
    tm = request.app.state.terminal_manager
    terminals = tm.list_terminals(user["id"])
    return TerminalListResponse(
        terminals=[
            TerminalInfo(
                id=t.id,
                user_id=t.user_id,
                working_dir=t.working_dir,
                mode=t.mode.value,
                command=t.command,
                is_alive=t.is_alive,
                created_at=t.created_at,
                last_active=t.last_active,
            )
            for t in terminals
        ]
    )


@router.post("", response_model=TerminalInfo, status_code=201)
async def create_terminal(
    req: CreateTerminalRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Create a new terminal session."""
    tm = request.app.state.terminal_manager
    terminal = await tm.create_terminal(
        user_id=user["id"],
        working_dir=req.working_dir,
        cols=req.cols,
        rows=req.rows,
        command=req.command,
        shell_path=req.shell_path,
    )
    return TerminalInfo(
        id=terminal.id,
        user_id=terminal.user_id,
        working_dir=terminal.working_dir,
        mode=terminal.mode.value,
        command=terminal.command,
        is_alive=terminal.is_alive,
        created_at=terminal.created_at,
        last_active=terminal.last_active,
    )


@router.delete("/{terminal_id}")
async def destroy_terminal(
    terminal_id: str,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Destroy a terminal."""
    tm = request.app.state.terminal_manager
    terminal = tm.get_terminal(terminal_id, user["id"])
    if not terminal:
        raise HTTPException(status_code=404, detail="Terminal not found")
    await tm.destroy_terminal(terminal_id, user["id"])
    return {"status": "destroyed", "terminal_id": terminal_id}


@router.post("/{terminal_id}/run")
async def run_command(
    terminal_id: str,
    req: RunCommandRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Execute a command in an existing terminal. Output streams via WebSocket."""
    tm = request.app.state.terminal_manager
    terminal = tm.get_terminal(terminal_id, user["id"])
    if not terminal:
        raise HTTPException(status_code=404, detail="Terminal not found")
    ok = await tm.run_command(terminal_id, user["id"], req.command)
    if not ok:
        raise HTTPException(status_code=500, detail="Failed to execute command")
    return {"status": "sent", "terminal_id": terminal_id, "command": req.command}


@router.post("/{terminal_id}/switch")
async def switch_mode(
    terminal_id: str,
    req: SwitchModeRequest,
    request: Request,
    user: dict = Depends(get_current_user),
):
    """Switch terminal mode (claude <-> shell). Destroys and recreates the terminal."""
    tm = request.app.state.terminal_manager
    terminal = tm.get_terminal(terminal_id, user["id"])
    if not terminal:
        raise HTTPException(status_code=404, detail="Terminal not found")

    new_terminal = await tm.switch_mode(
        terminal_id=terminal_id,
        user_id=user["id"],
        new_mode=req.mode,
        cols=req.cols,
        rows=req.rows,
        shell_path=req.shell_path,
    )
    if not new_terminal:
        raise HTTPException(status_code=500, detail="Failed to switch mode")

    return TerminalInfo(
        id=new_terminal.id,
        user_id=new_terminal.user_id,
        working_dir=new_terminal.working_dir,
        mode=new_terminal.mode.value,
        command=new_terminal.command,
        is_alive=new_terminal.is_alive,
        created_at=new_terminal.created_at,
        last_active=new_terminal.last_active,
    )
