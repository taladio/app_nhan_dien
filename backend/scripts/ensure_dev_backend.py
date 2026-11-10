"""Start the local backend once before Android Studio launches Flutter."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import URLError
from urllib.request import ProxyHandler, build_opener


PROJECT_ROOT = Path(__file__).resolve().parents[2]
HEALTH_URL = "http://127.0.0.1:8000/health"
STARTUP_TIMEOUT_SECONDS = 90


class BackendStartError(RuntimeError):
    """An actionable error for the IDE's Before launch task."""


def backend_ready() -> bool:
    # A system proxy must never receive the local readiness request.
    opener = build_opener(ProxyHandler({}))
    try:
        with opener.open(HEALTH_URL, timeout=1) as response:
            payload = json.loads(response.read(32 * 1024))
    except (OSError, URLError, ValueError):
        return False
    if not isinstance(payload, dict) or not {
        "model_loaded",
        "number_of_model_classes",
        "pose_model_loaded",
    }.issubset(payload):
        return False
    if payload.get("status") != "ok" or payload["model_loaded"] is not True:
        raise BackendStartError(
            "Backend is running but YOLO is not ready. Check backend/models/best.pt "
            "and the backend log before retrying."
        )
    return True


def ensure_backend(project_root: Path = PROJECT_ROOT) -> str:
    if backend_ready():
        return "Backend is already ready on port 8000; reusing it."

    # Do not launch duplicates or stop another application using this port.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as port_check:
        if os.name == "nt":
            port_check.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        try:
            port_check.bind(("0.0.0.0", 8000))
        except OSError as error:
            raise BackendStartError(
                "Port 8000 is occupied, but the backend health check failed. "
                "Check the existing backend; it may still be starting, or be bound "
                "only to a Wi-Fi IP. Use --host 0.0.0.0. No process was stopped."
            ) from error

    python = project_root / "backend" / ".venv" / (
        "Scripts/python.exe" if os.name == "nt" else "bin/python"
    )
    if not python.is_file():
        raise BackendStartError(
            "Backend Python environment is missing. Create backend/.venv "
            "and install backend/requirements.txt first."
        )

    log_path = project_root / ".dart_tool" / "backend" / "server.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    options = (
        {
            "creationflags": subprocess.CREATE_NO_WINDOW
            | subprocess.CREATE_NEW_PROCESS_GROUP
        }
        if os.name == "nt"
        else {"start_new_session": True}
    )
    print("Starting backend; waiting for YOLO to load...", flush=True)
    print(f"Backend log: {log_path}", flush=True)
    with log_path.open("ab") as log:
        process = subprocess.Popen(
            [
                str(python), "-u", "-m", "uvicorn", "backend.main:app",
                "--host", "0.0.0.0", "--port", "8000",
            ],
            cwd=project_root,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            **options,
        )

    deadline = time.monotonic() + STARTUP_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise BackendStartError(f"Backend exited before becoming ready. See {log_path}")
        if backend_ready():
            return "Backend is ready on port 8000. Starting Flutter."
        time.sleep(0.5)
    raise BackendStartError(
        f"Backend did not become ready within {STARTUP_TIMEOUT_SECONDS} seconds. "
        f"It may still be loading; check {log_path} before retrying."
    )


def main() -> int:
    try:
        print(ensure_backend(), flush=True)
        return 0
    except (BackendStartError, OSError) as error:
        print(f"Cannot start the app: {error}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
