"""
Quick test script — verifies the backend is running and endpoints work.
Usage: python test_client.py [host] [port] [api_key]
"""

import asyncio
import json
import sys

import websockets
from httpx import Client

HOST = sys.argv[1] if len(sys.argv) > 1 else "localhost"
PORT = sys.argv[2] if len(sys.argv) > 2 else "8000"
API_KEY = sys.argv[3] if len(sys.argv) > 3 else "change-me"

BASE = f"http://{HOST}:{PORT}"
HEADERS = {"X-API-Key": API_KEY}


def test_rest():
    """Test REST endpoints."""
    print(f"Testing REST API at {BASE}...\n")
    c = Client(headers=HEADERS, timeout=10)

    # Status
    r = c.get(f"{BASE}/status")
    print(f"GET /status → {r.status_code}")
    if r.status_code == 200:
        data = r.json()
        print(f"  hostname: {data['hostname']}")
        print(f"  repo:     {data['repo_path']}")
        print(f"  model:    {data['default_model']}")
        print(f"  uptime:   {data['uptime_seconds']}s")
    else:
        print(f"  ERROR: {r.text}")
        return False

    # Sessions list
    r = c.get(f"{BASE}/sessions")
    print(f"\nGET /sessions → {r.status_code}")
    print(f"  sessions: {len(r.json())}")

    # Create session
    r = c.post(f"{BASE}/sessions", json={})
    print(f"\nPOST /sessions → {r.status_code}")
    if r.status_code == 201:
        session = r.json()
        print(f"  id:     {session['id']}")
        print(f"  branch: {session['branch']}")
        return session["id"]
    else:
        print(f"  ERROR: {r.text}")
        return None


async def test_websocket(session_id: str):
    """Test WebSocket streaming."""
    ws_url = f"ws://{HOST}:{PORT}/ws?api_key={API_KEY}"
    print(f"\nTesting WebSocket at {ws_url}...")

    async with websockets.connect(ws_url) as ws:
        # Send a simple prompt
        msg = {
            "type": "prompt",
            "session_id": session_id,
            "content": "Say hello in a code comment",
        }
        await ws.send(json.dumps(msg))
        print(f"  Sent prompt: {msg['content']}")

        # Read streamed responses
        print("  Streaming response:")
        while True:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=60)
                data = json.loads(raw)
                if data["type"] == "stream":
                    print(f"    {data['content']}", end="")
                elif data["type"] == "complete":
                    print(f"\n  Complete! Changes: {len(data.get('pending_changes', []))}")
                    print(f"  Token usage: {data.get('token_usage', {})}")
                    break
                elif data["type"] == "error":
                    print(f"\n  ERROR: {data['message']}")
                    break
            except asyncio.TimeoutError:
                print("\n  Timeout waiting for response")
                break


def main():
    print("=" * 50)
    print("ArcBench Backend Test Client")
    print("=" * 50)

    session_id = test_rest()

    if session_id:
        print("\n" + "-" * 50)
        asyncio.run(test_websocket(session_id))

    print("\n" + "=" * 50)
    print("Tests complete!")


if __name__ == "__main__":
    main()
