"""Nhận diện màu quần áo từ crop của bounding box bằng không gian HSV."""

from __future__ import annotations

import cv2
import numpy as np

UNKNOWN_COLOR = "Không xác định"
COLOR_NAMES: tuple[str, ...] = (
    "Đen",
    "Trắng",
    "Xám",
    "Đỏ",
    "Cam",
    "Vàng",
    "Xanh lá",
    "Xanh ngọc",
    "Xanh dương",
    "Tím",
    "Hồng",
    "Nâu",
    "Be",
)


def detect_clothing_colors(crop: np.ndarray) -> tuple[str, list[str]]:
    """Trả về màu chính và tối đa hai màu phụ đủ nổi bật.

    Chỉ lấy phần giữa crop để giảm nền/da ở rìa. Ảnh được thu nhỏ trước khi
    phân loại HSV nên không giữ lại hoặc sao chép dữ liệu ảnh sau request.
    """

    try:
        if crop is None or crop.size == 0 or crop.ndim != 3:
            return UNKNOWN_COLOR, []

        height, width = crop.shape[:2]
        if height < 2 or width < 2:
            return UNKNOWN_COLOR, []

        y_margin = int(height * 0.13)
        x_margin = int(width * 0.13)
        center = crop[y_margin : height - y_margin, x_margin : width - x_margin]
        if center.size == 0:
            center = crop

        scale = min(1.0, 220.0 / max(center.shape[:2]))
        if scale < 1.0:
            center = cv2.resize(
                center,
                (max(1, round(center.shape[1] * scale)), max(1, round(center.shape[0] * scale))),
                interpolation=cv2.INTER_AREA,
            )

        hsv = cv2.cvtColor(center, cv2.COLOR_BGR2HSV)
        hue = hsv[:, :, 0]
        saturation = hsv[:, :, 1]
        value = hsv[:, :, 2]
        labels = np.full(hue.shape, -1, dtype=np.int8)

        labels[value <= 45] = 0
        labels[(labels < 0) & (saturation <= 28) & (value >= 205)] = 1
        labels[
            (labels < 0)
            & (hue >= 8)
            & (hue <= 28)
            & (saturation >= 18)
            & (saturation <= 105)
            & (value >= 135)
        ] = 12
        labels[(labels < 0) & (saturation <= 48)] = 2

        unlabelled = labels < 0
        labels[
            unlabelled
            & (hue >= 5)
            & (hue < 22)
            & ((value < 165) | (saturation < 115))
        ] = 11
        unlabelled = labels < 0
        labels[unlabelled & ((hue < 10) | (hue >= 170))] = 3
        labels[unlabelled & (hue >= 10) & (hue < 20)] = 4
        labels[unlabelled & (hue >= 20) & (hue < 35)] = 5
        labels[unlabelled & (hue >= 35) & (hue < 85)] = 6
        labels[unlabelled & (hue >= 85) & (hue < 100)] = 7
        labels[unlabelled & (hue >= 100) & (hue < 130)] = 8
        labels[unlabelled & (hue >= 130) & (hue < 150)] = 9
        labels[unlabelled & (hue >= 150) & (hue < 170)] = 10

        valid = labels[labels >= 0]
        if valid.size < 16:
            return UNKNOWN_COLOR, []

        counts = np.bincount(valid, minlength=len(COLOR_NAMES))
        ranked = np.argsort(counts)[::-1]
        primary_index = int(ranked[0])
        if counts[primary_index] <= 0:
            return UNKNOWN_COLOR, []

        minimum_secondary = max(16, int(valid.size * 0.12))
        secondary = [
            COLOR_NAMES[int(index)]
            for index in ranked[1:]
            if counts[int(index)] >= minimum_secondary
        ][:2]
        return COLOR_NAMES[primary_index], secondary
    except (cv2.error, TypeError, ValueError, IndexError):
        return UNKNOWN_COLOR, []
