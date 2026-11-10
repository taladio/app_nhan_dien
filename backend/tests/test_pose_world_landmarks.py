from types import SimpleNamespace

import cv2
import numpy as np
import pytest
from pydantic import ValidationError

from backend.schemas.pose_result import PoseWorldPoint
from backend.services.pose_landmarker_service import PoseLandmarkerService


def process(world=True, bad_coordinate=False):
    image_points = [
        SimpleNamespace(x=.3, y=.4, z=-.1, visibility=.9) for _ in range(33)
    ]
    image_points[23].y = 1.35  # Off-screen hip must not snap to image bottom.
    world_points = [
        SimpleNamespace(x=-.2, y=-.5, z=.12) for _ in range(33)
    ]
    if bad_coordinate:
        world_points[11].z = float("nan")
    result = SimpleNamespace(
        pose_landmarks=[image_points],
        pose_world_landmarks=[world_points] if world else [],
    )
    service = PoseLandmarkerService()
    service.landmarker = SimpleNamespace(detect_for_video=lambda *_: result)
    service._mp = SimpleNamespace(
        Image=lambda **kwargs: kwargs,
        ImageFormat=SimpleNamespace(SRGB=1),
    )
    ok, encoded = cv2.imencode(".jpg", np.zeros((16, 16, 3), dtype=np.uint8))
    assert ok
    return service.process_jpeg(encoded.tobytes(), 1)


def test_real_world_coordinates_are_not_normalized_or_clipped():
    result = process()
    assert result is not None
    assert len(result.world_landmarks) == 33
    shoulder = result.world_landmarks["left_shoulder"]
    assert shoulder.x == -.2
    assert shoulder.y == -.5
    assert shoulder.z == .12
    assert shoulder.visibility == .9
    assert result.landmarks["left_hip"].y == 1.35


def test_missing_world_output_stays_empty_instead_of_fabricating_3d():
    result = process(world=False)
    assert result is not None
    assert result.world_landmarks == {}
    assert len(result.landmarks) == 33


def test_nonfinite_world_joint_is_omitted():
    result = process(bad_coordinate=True)
    assert result is not None
    assert "left_shoulder" not in result.world_landmarks
    assert "right_shoulder" in result.world_landmarks
    with pytest.raises(ValidationError):
        PoseWorldPoint(x=float("inf"), y=0, z=0, visibility=1)
