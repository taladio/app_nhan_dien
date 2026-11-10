"""Failures must block IDE launch, without killing another process."""

from io import BytesIO
import json
from unittest.mock import Mock, patch

import pytest

from backend.scripts import ensure_dev_backend as launcher


def test_reuses_ready_backend_without_spawning_another_process():
    with patch.object(launcher, "backend_ready", return_value=True), patch.object(
        launcher.subprocess, "Popen"
    ) as spawn:
        assert "reusing" in launcher.ensure_backend()
    spawn.assert_not_called()


def test_occupied_port_does_not_spawn_or_stop_anything(tmp_path):
    with patch.object(launcher, "backend_ready", return_value=False), patch.object(
        launcher.socket, "socket"
    ) as socket_factory, patch.object(launcher.subprocess, "Popen") as spawn:
        socket_factory.return_value.__enter__.return_value.bind.side_effect = OSError(
            "Address in use"
        )
        with pytest.raises(launcher.BackendStartError, match="Port 8000 is occupied"):
            launcher.ensure_backend(tmp_path)
    spawn.assert_not_called()


def test_unloaded_yolo_blocks_launch_instead_of_claiming_ready():
    payload = {
        "status": "degraded", "model_loaded": False,
        "number_of_model_classes": 0, "pose_model_loaded": False,
    }
    with patch.object(launcher, "build_opener") as build_opener:
        build_opener.return_value.open.return_value = BytesIO(json.dumps(payload).encode())
        with pytest.raises(launcher.BackendStartError, match="YOLO is not ready"):
            launcher.backend_ready()


@pytest.mark.parametrize("response", [b"not json", b'{"status":"ok"}', b"[]"])
def test_other_services_are_not_mistaken_for_fashion_backend(response):
    with patch.object(launcher, "build_opener") as build_opener:
        build_opener.return_value.open.return_value = BytesIO(response)
        assert launcher.backend_ready() is False


def test_exited_backend_fails_without_waiting_for_timeout(tmp_path):
    python = tmp_path / "backend" / ".venv" / (
        "Scripts/python.exe" if launcher.os.name == "nt" else "bin/python"
    )
    python.parent.mkdir(parents=True)
    python.touch()
    process = Mock()
    process.poll.return_value = 1
    with patch.object(launcher, "backend_ready", return_value=False), patch.object(
        launcher.socket, "socket"
    ), patch.object(launcher.subprocess, "Popen", return_value=process), patch.object(
        launcher.time, "sleep"
    ) as sleep:
        with pytest.raises(launcher.BackendStartError, match="exited before becoming ready"):
            launcher.ensure_backend(tmp_path)
    sleep.assert_not_called()
