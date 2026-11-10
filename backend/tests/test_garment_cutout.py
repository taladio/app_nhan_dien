from io import BytesIO

import numpy as np
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from backend.routers.try_on import router
from backend.services.garment_cutout_service import MAX_EDGE, cutout_garment

app = FastAPI()
app.include_router(router)
client = TestClient(app)


def encode(image):
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def product_photo():
    image = Image.new("RGB", (160, 200), "white")
    draw = ImageDraw.Draw(image)
    draw.polygon([(50, 25), (110, 25), (140, 65), (115, 80),
                  (110, 175), (50, 175), (45, 80), (20, 65)], fill="teal")
    return image


def test_product_photo_returns_transparent_cropped_png():
    response = client.post("/api/v1/try-on/cutout", files={
        "file": ("shirt.png", encode(product_photo()), "image/png"),
    })
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"
    assert response.headers["cache-control"] == "no-store"
    result = np.array(Image.open(BytesIO(response.content)))
    assert result.shape[2] == 4
    assert result.shape[0] < 200 and result.shape[1] < 160
    assert result[0, 0, 3] < 10
    assert result[result.shape[0] // 2, result.shape[1] // 2, 3] == 255


def test_existing_alpha_is_not_segmented_again():
    image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    ImageDraw.Draw(image).rectangle((10, 10, 50, 50), fill=(20, 80, 120, 128))
    output = cutout_garment(encode(image), (0, 0, 1, 1))
    result = np.array(Image.open(BytesIO(output)))
    assert result.shape == (41, 41, 4)
    assert np.all(result[:, :, 3] == 128)


@pytest.mark.parametrize("payload,mime,status", [
    (b"", "image/png", 400),
    (b"not an image", "image/png", 422),
    (b"not an image", "text/plain", 415),
    (b"x" * (10 * 1024 * 1024 + 1), "image/jpeg", 413),
], ids=["empty", "corrupt", "wrong-mime", "oversized"])
def test_invalid_uploads(payload, mime, status):
    assert client.post("/api/v1/try-on/cutout", files={
        "file": ("bad", payload, mime),
    }).status_code == status


@pytest.mark.parametrize("crop", [
    {"x": -1}, {"width": 0}, {"x": 0.8, "width": 0.5}, {"x": "nan"},
])
def test_invalid_crop(crop):
    assert client.post("/api/v1/try-on/cutout", data=crop, files={
        "file": ("shirt.png", encode(product_photo()), "image/png"),
    }).status_code == 422


def test_blank_photo_reports_failure_instead_of_empty_filter():
    response = client.post("/api/v1/try-on/cutout", files={
        "file": ("blank.png", encode(Image.new("RGB", (64, 64), "white")), "image/png"),
    })
    assert response.status_code == 422


def test_large_transparent_image_is_bounded_and_crop_is_applied():
    image = Image.new("RGBA", (2000, 2000), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rectangle((100, 100, 800, 1800), fill="red")
    draw.rectangle((1200, 100, 1900, 1800), fill="blue")
    result = Image.open(BytesIO(cutout_garment(encode(image), (0, 0, 0.5, 1))))
    assert max(result.size) <= MAX_EDGE
    assert result.getpixel((result.width // 2, result.height // 2)) == (255, 0, 0, 255)
