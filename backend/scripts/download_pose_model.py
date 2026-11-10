"""Tải thủ công model Pose Landmarker chính thức của MediaPipe."""

from __future__ import annotations

import argparse
import tempfile
import urllib.request
from pathlib import Path


BACKEND_DIR = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=("lite", "full", "heavy"), default="full")
    variant = parser.parse_args().variant
    model_name = f"pose_landmarker_{variant}"
    model_url = (
        "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
        f"{model_name}/float16/latest/{model_name}.task"
    )
    target = BACKEND_DIR / "models" / f"{model_name}.task"
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=target.parent,
        suffix=".part",
        delete=False,
    ) as temporary:
        temporary_path = Path(temporary.name)
    try:
        print(f"Downloading the official MediaPipe model from {model_url}")
        urllib.request.urlretrieve(model_url, temporary_path)
        if temporary_path.stat().st_size < 1_000_000:
            raise RuntimeError("Tệp model tải về quá nhỏ, có thể đã bị lỗi.")
        temporary_path.replace(target)
        print(f"Saved model to: {target}")
    finally:
        temporary_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
