from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.routers.pose_websocket import create_pose_websocket_router
from backend.schemas.pose_result import AnchorPoint, PoseAnchors, PosePoint
from backend.services.pose_landmarker_service import InvalidPoseFrame, PoseAnalysis


CONFIG = {
    "type": "config",
    "camera": "front",
    "mirrored": True,
    "rotation_degrees": 90,
    "frame_width": 480,
    "frame_height": 640,
}


class FakePoseProcessor:
    loaded = True
    load_error = None

    def __init__(self, result: PoseAnalysis | None = None, *, invalid: bool = False) -> None:
        self.result = result
        self.invalid = invalid
        self.frames: list[bytes] = []

    def load_once(self) -> None:
        return

    def process_jpeg(self, data: bytes, timestamp_ms: int) -> PoseAnalysis | None:
        del timestamp_ms
        self.frames.append(data)
        if self.invalid:
            raise InvalidPoseFrame("bad frame")
        return self.result


def _client(processor: FakePoseProcessor) -> TestClient:
    app = FastAPI()
    app.include_router(create_pose_websocket_router(processor))
    return TestClient(app)


def _analysis() -> PoseAnalysis:
    point = PosePoint(x=0.5, y=0.5, z=0, visibility=0.99)
    return PoseAnalysis(
        landmarks={"left_shoulder": point},
        anchors=PoseAnchors(
            shoulder_center=AnchorPoint(x=0.5, y=0.3),
            shoulder_width=0.4,
            shoulder_angle=0,
            hip_center=AnchorPoint(x=0.5, y=0.55),
            hip_width=0.25,
            hip_angle=0,
            torso_center=AnchorPoint(x=0.5, y=0.425),
            torso_height=0.25,
            left_leg_length=0.4,
            right_leg_length=0.4,
            body_visible=True,
        ),
    )


def test_invalid_config_returns_safe_error() -> None:
    config = {**CONFIG, "rotation_degrees": 45}
    with _client(FakePoseProcessor()).websocket_connect("/api/v1/pose/ws") as socket:
        socket.send_json(config)
        assert socket.receive_json() == {
            "type": "error",
            "message": "Cấu hình camera không hợp lệ.",
        }


def test_non_image_frame_returns_error() -> None:
    processor = FakePoseProcessor(invalid=True)
    with _client(processor).websocket_connect("/api/v1/pose/ws") as socket:
        socket.send_json(CONFIG)
        socket.send_bytes(b"not-a-jpeg")
        assert socket.receive_json() == {
            "type": "error",
            "message": "Khung hình JPEG không hợp lệ.",
        }


def test_no_pose_response_contains_full_body_hint() -> None:
    with _client(FakePoseProcessor()).websocket_connect("/api/v1/pose/ws") as socket:
        socket.send_json(CONFIG)
        socket.send_bytes(b"jpeg-in-memory")
        payload = socket.receive_json()

    assert payload["type"] == "pose_result"
    assert payload["pose_detected"] is False
    assert payload["body_visible"] is False
    assert "đứng lùi lại" in payload["message"]


def test_pose_response_and_frame_is_not_saved(tmp_path: Path) -> None:
    processor = FakePoseProcessor(_analysis())
    before = set(tmp_path.iterdir())
    with _client(processor).websocket_connect("/api/v1/pose/ws") as socket:
        socket.send_json(CONFIG)
        socket.send_bytes(b"jpeg-kept-only-in-memory")
        payload = socket.receive_json()

    assert payload["pose_detected"] is True
    assert payload["body_visible"] is True
    assert payload["anchors"]["shoulder_width"] == 0.4
    assert processor.frames == [b"jpeg-kept-only-in-memory"]
    assert set(tmp_path.iterdir()) == before

