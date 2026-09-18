"""Tải thủ công model Pose Landmarker Lite chính thức của MediaPipe."""

from __future__ import annotations

import tempfile
import urllib.request
from pathlib import Path


MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
)
BACKEND_DIR = Path(__file__).resolve().parents[1]
TARGET = BACKEND_DIR / "models" / "pose_landmarker_lite.task"


def main() -> None:
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=TARGET.parent,
        suffix=".part",
        delete=False,
    ) as temporary:
        temporary_path = Path(temporary.name)
    try:
        print(f"Downloading the official MediaPipe model from {MODEL_URL}")
        urllib.request.urlretrieve(MODEL_URL, temporary_path)
        if temporary_path.stat().st_size < 1_000_000:
            raise RuntimeError("Tệp model tải về quá nhỏ, có thể đã bị lỗi.")
        temporary_path.replace(TARGET)
        print(f"Saved model to: {TARGET}")
    finally:
        temporary_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
