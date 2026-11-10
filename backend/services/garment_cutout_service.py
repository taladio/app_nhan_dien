"""Extract a product-photo foreground in memory; no AI API or image storage."""

from io import BytesIO
import warnings

import cv2
import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError

MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_PIXELS = 20_000_000
MAX_EDGE = 900
_IMAGE_OPEN = Image.open  # Capture Pillow before Ultralytics patches Image.open.


class CutoutError(ValueError):
    pass


def cutout_garment(data: bytes, crop: tuple[float, float, float, float]) -> bytes:
    """Crop (normalized, EXIF-oriented), retain alpha or extract foreground."""
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with _IMAGE_OPEN(BytesIO(data)) as source:
                if source.format not in {"JPEG", "PNG", "WEBP"}:
                    raise CutoutError("Chỉ hỗ trợ ảnh JPEG, PNG hoặc WebP.")
                if source.width * source.height > MAX_PIXELS:
                    raise CutoutError("Ảnh quá lớn. Hãy chọn ảnh dưới 20 megapixel.")
                rgba = ImageOps.exif_transpose(source).convert("RGBA")
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError,
            Image.DecompressionBombWarning) as error:
        raise CutoutError("Không đọc được ảnh. Hãy chọn ảnh khác.") from error

    x, y, width, height = crop
    if x + width > 1.00001 or y + height > 1.00001:
        raise CutoutError("Vùng cắt phải nằm trong ảnh.")
    rgba = rgba.crop((round(x * rgba.width), round(y * rgba.height),
                      round((x + width) * rgba.width), round((y + height) * rgba.height)))
    if min(rgba.size) < 16:
        raise CutoutError("Vùng cắt quá nhỏ. Hãy khoanh trọn món đồ.")
    rgba.thumbnail((MAX_EDGE, MAX_EDGE), Image.Resampling.LANCZOS)
    pixels = np.array(rgba)
    alpha = pixels[:, :, 3]

    # An existing cutout must keep its transparency, including fine details.
    if not np.any(alpha < 250):
        rgb = np.ascontiguousarray(pixels[:, :, :3])
        h, w = alpha.shape
        margin = max(1, round(min(w, h) * 0.02))
        mask = np.zeros((h, w), np.uint8)
        try:
            cv2.grabCut(
                rgb, mask, (margin, margin, w - margin * 2, h - margin * 2),
                np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64),
                4, cv2.GC_INIT_WITH_RECT,
            )
        except cv2.error as error:
            raise CutoutError("Chưa tách được nền. Hãy chọn ảnh đồ trên nền đơn giản.") from error
        foreground = np.isin(mask, (cv2.GC_FGD, cv2.GC_PR_FGD)).astype(np.uint8) * 255
        if np.count_nonzero(foreground) < h * w * 0.005:
            raise CutoutError("Không tìm thấy món đồ rõ ràng. Hãy chọn lại vùng cắt hoặc ảnh khác.")
        # Feather only the silhouette edge; the garment remains opaque.
        alpha = cv2.GaussianBlur(foreground, (3, 3), 0)
        pixels[:, :, 3] = alpha

    visible = np.argwhere(alpha > 8)
    if not len(visible):
        raise CutoutError("Ảnh không còn phần quần áo nhìn thấy.")
    top, left = visible.min(axis=0)
    bottom, right = visible.max(axis=0) + 1
    output = Image.fromarray(pixels).crop((int(left), int(top), int(right), int(bottom)))
    encoded = BytesIO()
    output.save(encoded, format="PNG")
    return encoded.getvalue()
