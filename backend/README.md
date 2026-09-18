# Backend YOLO + đánh giá trang phục + MediaPipe Pose

FastAPI dùng một instance Ultralytics YOLO được tải khi module khởi động. Model
21 lớp (nếu có) được chuẩn hóa về tám nhóm `tshirt`, `shirt`, `jacket`, `pants`,
`shorts`, `skirt`, `dress`, `shoes`. Endpoint mới dùng metadata nhận diện để gọi
OpenAI Responses API với Structured Outputs hoặc fallback cục bộ.
WebSocket Pose nhận JPEG trong RAM, chạy Pose Landmarker ở chế độ `VIDEO` và trả
landmark/anchor cho màn thử đồ ảo. Frame không được ghi ra ổ đĩa.

## Cài đặt

Từ thư mục gốc repository:

```powershell
python -m venv backend\.venv
.\backend\.venv\Scripts\Activate.ps1
python -m pip install -r backend\requirements.txt
Copy-Item backend\.env.example backend\.env
python backend\scripts\download_pose_model.py
```

Môi trường đã kiểm thử dùng Python 3.13.7 và MediaPipe 1.0.1. Đặt model YOLO tại
`backend/models/best.pt`. Có thể dùng `MODEL_PATH` để trỏ tới vị trí khác; đường
dẫn tương đối được tính từ working directory của tiến trình. Script tải model
Pose Lite chính thức vào `backend/models/pose_landmarker_lite.task`; backend
không tự tải model khi khởi động. Có thể dùng `POSE_MODEL_PATH` để thay đổi
đường dẫn.

`backend/.env`:

```dotenv
OPENAI_API_KEY=
OPENAI_MODEL=gpt-5.6-luna
OPENAI_TIMEOUT_SECONDS=30
```

Không có key hoặc lỗi 429/quota/timeout/network/model/schema/refusal sẽ tự dùng
`rule_based_outfit_service.py` và trả `source: fallback`. Không log API key.
ChatGPT Plus không bao gồm credit OpenAI API.

## Chạy

Từ thư mục `backend`:

```powershell
.\.venv\Scripts\Activate.ps1
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Hoặc từ thư mục gốc:

```powershell
.\backend\.venv\Scripts\python.exe -m uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

Các route:

- `GET /health`: trạng thái model, device và đường dẫn model.
- `GET /api/v1/classes`: lớp model và kết quả chuẩn hóa.
- `POST /api/v1/detect`: endpoint YOLO cũ, nhận JPEG/PNG/WebP.
- `POST /api/v1/outfit/analyze`: multipart YOLO + đánh giá, chỉ nhận JPEG/PNG.
- `WS /api/v1/pose/ws`: binary JPEG → MediaPipe Pose landmark/anchor.
- `GET /docs`: Swagger UI để thử cả hai endpoint.

Endpoint phân tích nhận `file`, `height_cm`, `weight_kg`, `season`,
`temperature_c`, `style`, `occasion`, `confidence`. Ảnh tối đa 10 MB và chỉ tồn
tại trong request. OpenAI chỉ nhận loại đồ, màu, confidence, profile và context;
không nhận bytes/base64/path/URL ảnh.

WebSocket yêu cầu JSON config đầu tiên (`camera`, `mirrored`,
`rotation_degrees`, `frame_width`, `frame_height`), sau đó chỉ nhận binary JPEG
tối đa 3 MB. Model có `num_poses=1`; các ngưỡng mặc định là 0.5 và có thể đổi
qua `POSE_MIN_DETECTION_CONFIDENCE`, `POSE_MIN_PRESENCE_CONFIDENCE`,
`POSE_MIN_TRACKING_CONFIDENCE`, `POSE_VISIBILITY_THRESHOLD`. Inference chạy
trong threadpool để không khóa event loop FastAPI.

## Cấu trúc mã

```text
backend/
├── main.py                         # runtime YOLO và endpoint cũ
├── routers/outfit_analysis.py      # endpoint kết hợp
├── routers/pose_websocket.py       # WebSocket JPEG/pose
├── schemas/outfit_analysis.py      # request/response/Structured Output
├── schemas/pose_result.py          # config và pose response
├── services/color_detector.py      # màu chính + tối đa hai màu phụ
├── services/openai_outfit_service.py
├── services/rule_based_outfit_service.py
├── services/pose_anchor_service.py
├── services/pose_landmarker_service.py
├── scripts/download_pose_model.py
└── tests/
```

## Kiểm thử

```powershell
.\backend\.venv\Scripts\python.exe -m pytest backend\tests -v
```

Test mock YOLO, OpenAI và MediaPipe; kiểm tra ảnh, anchor, visibility, WebSocket
config/frame lỗi, trường hợp không thấy người và không lưu frame. Không phát
sinh chi phí API.

## Lỗi thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| `/health` báo `model_loaded: false` | Kiểm tra `backend/models/best.pt`, Ultralytics/PyTorch và `MODEL_PATH`. |
| `/api/v1/outfit/analyze` trả 503 | Model chưa tải được; xem `/health` và log server. |
| WebSocket báo `Không tìm thấy pose_landmarker_lite.task` | Chạy `python backend/scripts/download_pose_model.py` từ thư mục gốc. |
| Trả 400 | Gửi JPG/JPEG/PNG thật, MIME đúng, không rỗng và tối đa 10 MB. |
| Trả 422 không nhận diện | Chọn ảnh rõ, đủ sáng và chụp toàn thân. |
| `source` là `fallback` | Kiểm tra key, billing, quyền model, mạng và timeout; response vẫn hợp lệ. |
| Android Emulator không kết nối | Backend dùng `--host 0.0.0.0`; Flutter dùng `http://10.0.2.2:8000`. |
