"""Tính các điểm neo trang phục từ landmark MediaPipe."""

from __future__ import annotations

import math
from collections.abc import Mapping

try:
    from ..schemas.pose_result import AnchorPoint, PoseAnchors, PosePoint
except ImportError:  # Hỗ trợ `cd backend; uvicorn main:app`.
    from schemas.pose_result import AnchorPoint, PoseAnchors, PosePoint


REQUIRED_LANDMARKS = (
    "left_shoulder",
    "right_shoulder",
    "left_hip",
    "right_hip",
    "left_knee",
    "right_knee",
    "left_ankle",
    "right_ankle",
    "left_heel",
    "right_heel",
    "left_foot_index",
    "right_foot_index",
)


def _distance(first: PosePoint | AnchorPoint, second: PosePoint | AnchorPoint) -> float:
    return math.hypot(second.x - first.x, second.y - first.y)


def _midpoint(first: PosePoint, second: PosePoint) -> AnchorPoint:
    return AnchorPoint(x=(first.x + second.x) / 2, y=(first.y + second.y) / 2)


def calculate_pose_anchors(
    landmarks: Mapping[str, PosePoint],
    *,
    visibility_threshold: float = 0.5,
) -> PoseAnchors | None:
    """Trả anchor khi toàn bộ điểm quan trọng đủ rõ, ngược lại trả ``None``."""

    if any(
        name not in landmarks
        or landmarks[name].visibility < visibility_threshold
        for name in REQUIRED_LANDMARKS
    ):
        return None

    left_shoulder = landmarks["left_shoulder"]
    right_shoulder = landmarks["right_shoulder"]
    left_hip = landmarks["left_hip"]
    right_hip = landmarks["right_hip"]
    shoulder_center = _midpoint(left_shoulder, right_shoulder)
    hip_center = _midpoint(left_hip, right_hip)

    return PoseAnchors(
        shoulder_center=shoulder_center,
        shoulder_width=_distance(left_shoulder, right_shoulder),
        shoulder_angle=math.atan2(
            right_shoulder.y - left_shoulder.y,
            right_shoulder.x - left_shoulder.x,
        ),
        hip_center=hip_center,
        hip_width=_distance(left_hip, right_hip),
        hip_angle=math.atan2(
            right_hip.y - left_hip.y,
            right_hip.x - left_hip.x,
        ),
        torso_center=AnchorPoint(
            x=(shoulder_center.x + hip_center.x) / 2,
            y=(shoulder_center.y + hip_center.y) / 2,
        ),
        torso_height=_distance(shoulder_center, hip_center),
        left_leg_length=(
            _distance(left_hip, landmarks["left_knee"])
            + _distance(landmarks["left_knee"], landmarks["left_ankle"])
        ),
        right_leg_length=(
            _distance(right_hip, landmarks["right_knee"])
            + _distance(landmarks["right_knee"], landmarks["right_ankle"])
        ),
        body_visible=True,
    )

