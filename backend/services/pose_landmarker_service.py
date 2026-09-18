"""MediaPipe Pose Landmarker dùng chung cho luồng WebSocket realtime."""

from __future__ import annotations

import logging
import os
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np

try:
    from ..schemas.pose_result import PoseAnchors, PosePoint
    from .pose_anchor_service import calculate_pose_anchors
except ImportError:  # Hỗ trợ `cd backend; uvicorn main:app`.
    from schemas.pose_result import PoseAnchors, PosePoint
    from services.pose_anchor_service import calculate_pose_anchors


LOGGER = logging.getLogger(__name__)
BACKEND_DIR = Path(__file__).resolve().parents[1]
DEFAULT_POSE_MODEL_PATH = BACKEND_DIR / "models" / "pose_landmarker_lite.task"
MAX_POSE_FRAME_SIZE = 3 * 1024 * 1024

LANDMARK_INDEXES = {
    "left_shoulder": 11,
    "right_shoulder": 12,
    "left_hip": 23,
    "right_hip": 24,
    "left_knee": 25,
    "right_knee": 26,
    "left_ankle": 27,
    "right_ankle": 28,
    "left_heel": 29,
    "right_heel": 30,
    "left_foot_index": 31,
    "right_foot_index": 32,
}


class InvalidPoseFrame(ValueError):
    """Frame không thể giải mã thành ảnh."""


@dataclass(frozen=True)
class PoseAnalysis:
    landmarks: dict[str, PosePoint]
    anchors: PoseAnchors


def configured_pose_model_path() -> Path:
    override = os.getenv("POSE_MODEL_PATH", "").strip()
    if not override:
        return DEFAULT_POSE_MODEL_PATH
    path = Path(override).expanduser()
    return path if path.is_absolute() else (Path.cwd() / path).resolve()


def _confidence(name: str, default: float = 0.5) -> float:
    try:
        return min(max(float(os.getenv(name, str(default))), 0.0), 1.0)
    except ValueError:
        return default


class PoseLandmarkerService:
    """Nạp model đúng một lần và tuần tự hóa VIDEO inference giữa các client."""

    def __init__(self, model_path: Path | None = None) -> None:
        self.model_path = model_path or configured_pose_model_path()
        self.landmarker: Any | None = None
        self.load_error: str | None = None
        self._load_attempted = False
        self._load_lock = threading.Lock()
        self._inference_lock = threading.Lock()
        self._last_timestamp_ms = -1

    @property
    def loaded(self) -> bool:
        return self.landmarker is not None

    def load_once(self) -> None:
        with self._load_lock:
            if self._load_attempted:
                return
            self._load_attempted = True

            if not self.model_path.is_file():
                self.load_error = "Không tìm thấy pose_landmarker_lite.task"
                return

            try:
                import mediapipe as mp
                from mediapipe.tasks import python
                from mediapipe.tasks.python import vision

                options = vision.PoseLandmarkerOptions(
                    base_options=python.BaseOptions(
                        model_asset_path=str(self.model_path),
                    ),
                    running_mode=vision.RunningMode.VIDEO,
                    num_poses=1,
                    min_pose_detection_confidence=_confidence(
                        "POSE_MIN_DETECTION_CONFIDENCE"
                    ),
                    min_pose_presence_confidence=_confidence(
                        "POSE_MIN_PRESENCE_CONFIDENCE"
                    ),
                    min_tracking_confidence=_confidence(
                        "POSE_MIN_TRACKING_CONFIDENCE"
                    ),
                )
                self.landmarker = vision.PoseLandmarker.create_from_options(options)
                self._mp = mp
            except Exception:
                LOGGER.exception("Không thể tải MediaPipe Pose Landmarker")
                self.load_error = (
                    "Không thể tải MediaPipe Pose Landmarker. "
                    "Hãy kiểm tra requirements.txt và tệp model."
                )

    def process_jpeg(self, data: bytes, timestamp_ms: int) -> PoseAnalysis | None:
        if not self.loaded:
            raise RuntimeError(self.load_error or "Pose Landmarker chưa sẵn sàng.")
        if not data or len(data) > MAX_POSE_FRAME_SIZE:
            raise InvalidPoseFrame("Khung hình JPEG không hợp lệ.")

        encoded = np.frombuffer(data, dtype=np.uint8)
        bgr = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
        if bgr is None or bgr.ndim != 3:
            raise InvalidPoseFrame("Khung hình JPEG không hợp lệ.")
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        mp_image = self._mp.Image(
            image_format=self._mp.ImageFormat.SRGB,
            data=rgb,
        )

        with self._inference_lock:
            video_timestamp = max(timestamp_ms, self._last_timestamp_ms + 1)
            self._last_timestamp_ms = video_timestamp
            result = self.landmarker.detect_for_video(mp_image, video_timestamp)

        if not result.pose_landmarks:
            return None

        source = result.pose_landmarks[0]
        landmarks = {
            name: PosePoint(
                x=min(max(float(source[index].x), 0.0), 1.0),
                y=min(max(float(source[index].y), 0.0), 1.0),
                z=float(source[index].z),
                visibility=min(max(float(source[index].visibility), 0.0), 1.0),
            )
            for name, index in LANDMARK_INDEXES.items()
        }
        anchors = calculate_pose_anchors(
            landmarks,
            visibility_threshold=_confidence("POSE_VISIBILITY_THRESHOLD"),
        )
        if anchors is None:
            return None
        return PoseAnalysis(landmarks=landmarks, anchors=anchors)

    def close(self) -> None:
        landmarker = self.landmarker
        self.landmarker = None
        if landmarker is not None:
            landmarker.close()


pose_runtime = PoseLandmarkerService()
pose_runtime.load_once()

