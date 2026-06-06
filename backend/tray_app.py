"""
ArcBench Desktop Tray App — lightweight system tray for local control.
Launches the FastAPI server, shows status, opens browser UI.

Requires: pip install pystray Pillow
"""

import subprocess
import sys
import threading
import webbrowser
from pathlib import Path

try:
    import pystray
    from PIL import Image, ImageDraw
except ImportError:
    print("Install tray dependencies: pip install pystray Pillow")
    sys.exit(1)

PORT = 8000
server_process = None


def create_icon_image():
    """Create a simple green circle icon for the system tray."""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse([8, 8, 56, 56], fill=(0, 230, 118, 255))
    draw.text((20, 18), "GC", fill=(0, 0, 0, 255))
    return img


def start_server():
    """Start the FastAPI server as a subprocess."""
    global server_process
    if server_process and server_process.poll() is None:
        return  # Already running

    backend_dir = Path(__file__).parent
    server_process = subprocess.Popen(
        [sys.executable, "main.py"],
        cwd=str(backend_dir),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    print(f"Server started (PID {server_process.pid})")


def stop_server():
    """Stop the FastAPI server."""
    global server_process
    if server_process and server_process.poll() is None:
        server_process.terminate()
        server_process.wait(timeout=5)
        print("Server stopped")
    server_process = None


def open_browser(item=None):
    """Open the Swagger UI in the browser."""
    webbrowser.open(f"http://localhost:{PORT}/docs")


def on_quit(icon, item):
    """Clean shutdown."""
    stop_server()
    icon.stop()


def setup(icon):
    """Called when the tray icon is ready."""
    icon.visible = True
    # Auto-start server
    threading.Thread(target=start_server, daemon=True).start()


def main():
    menu = pystray.Menu(
        pystray.MenuItem("Open Dashboard", open_browser, default=True),
        pystray.MenuItem("Restart Server", lambda: (stop_server(), start_server())),
        pystray.MenuItem("Stop Server", lambda: stop_server()),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Quit", on_quit),
    )

    icon = pystray.Icon(
        "arcbench",
        create_icon_image(),
        "ArcBench Desktop Host",
        menu,
    )

    icon.run(setup)


if __name__ == "__main__":
    main()
