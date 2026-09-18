from __future__ import annotations

import math

import pytest

from backend.schemas.pose_result import PosePoint
from backend.services.pose_anchor_service import calculate_pose_anchors


def _landmarks() -> dict[str, PosePoint]:
    values = {
        "left_shoulder": (0.30, 0.20),
        "right_shoulder": (0.70, 0.30),
        "left_hip": (0.40, 0.50),
        "right_hip": (0.60, 0.54),
        "left_knee": (0.42, 0.70),
        "right_knee": (0.58, 0.71),
        "left_ankle": (0.43, 0.90),
        "right_ankle": (0.57, 0.91),
        "left_heel": (0.42, 0.93),
        "right_heel": (0.58, 0.94),
        "left_foot_index": (0.47, 0.95),
        "right_foot_index": (0.63, 0.96),
    }
    return {
        name: PosePoint(x=x, y=y, z=0, visibility=0.99)
        for name, (x, y) in values.items()
    }


def test_calculates_centers_widths_and_angles() -> None:
    anchors = calculate_pose_anchors(_landmarks())

    assert anchors is not None
    assert anchors.shoulder_center.x == pytest.approx(0.5)
    assert anchors.shoulder_center.y == pytest.approx(0.25)
    assert anchors.hip_center.x == pytest.approx(0.5)
    assert anchors.hip_center.y == pytest.approx(0.52)
    assert anchors.shoulder_width == pytest.approx(math.hypot(0.4, 0.1))
    assert anchors.hip_width == pytest.approx(math.hypot(0.2, 0.04))
    assert anchors.shoulder_angle == pytest.approx(math.atan2(0.1, 0.4))
    assert anchors.hip_angle == pytest.approx(math.atan2(0.04, 0.2))
    assert anchors.torso_center.x == pytest.approx(0.5)
    assert anchors.torso_center.y == pytest.approx(0.385)
    assert anchors.left_leg_length > 0
    assert anchors.right_leg_length > 0
    assert anchors.body_visible is True


def test_missing_landmark_returns_none() -> None:
    landmarks = _landmarks()
    del landmarks["left_ankle"]

    assert calculate_pose_anchors(landmarks) is None


def test_low_visibility_landmark_returns_none() -> None:
    landmarks = _landmarks()
    landmarks["right_foot_index"] = PosePoint(
        x=0.63,
        y=0.96,
        z=0,
        visibility=0.2,
    )

    assert calculate_pose_anchors(landmarks, visibility_threshold=0.5) is None

