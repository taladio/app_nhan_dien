"""Kiểu dữ liệu trao đổi qua WebSocket của tính năng thử đồ ảo."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class PoseConfig(BaseModel):
    """Cấu hình camera phải là thông điệp đầu tiên của mỗi kết nối."""

    model_config = ConfigDict(extra="forbid")

    type: Literal["config"]
    camera: Literal["front", "back", "external"]
    mirrored: bool
    rotation_degrees: int
    frame_width: int = Field(ge=1, le=8192)
    frame_height: int = Field(ge=1, le=8192)

    @field_validator("rotation_degrees")
    @classmethod
    def validate_rotation(cls, value: int) -> int:
        if value not in {0, 90, 180, 270}:
            raise ValueError("rotation_degrees phải là 0, 90, 180 hoặc 270")
        return value


class PosePoint(BaseModel):
    model_config = ConfigDict(extra="forbid")

    x: float = Field(ge=0.0, le=1.0)
    y: float = Field(ge=0.0, le=1.0)
    z: float
    visibility: float = Field(ge=0.0, le=1.0)


class AnchorPoint(BaseModel):
    x: float = Field(ge=0.0, le=1.0)
    y: float = Field(ge=0.0, le=1.0)


class PoseAnchors(BaseModel):
    shoulder_center: AnchorPoint
    shoulder_width: float = Field(ge=0.0)
    shoulder_angle: float
    hip_center: AnchorPoint
    hip_width: float = Field(ge=0.0)
    hip_angle: float
    torso_center: AnchorPoint
    torso_height: float = Field(ge=0.0)
    left_leg_length: float = Field(ge=0.0)
    right_leg_length: float = Field(ge=0.0)
    body_visible: bool


class PoseResult(BaseModel):
    type: Literal["pose_result"] = "pose_result"
    frame_id: int = Field(ge=1)
    timestamp_ms: int = Field(ge=0)
    processing_ms: float = Field(ge=0.0)
    pose_detected: bool
    body_visible: bool
    landmarks: dict[str, PosePoint] = Field(default_factory=dict)
    anchors: PoseAnchors | None = None
    message: str | None = None

