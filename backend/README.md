# Backend YOLO + đánh giá trang phục + MediaPipe Pose

FastAPI dùng một instance Ultralytics YOLO được tải khi module khởi động. Model
21 lớp (nếu có) được chuẩn hóa về tám nhóm `tshirt`, `shirt`, `jacket`, `pants`,
`shorts`, `skirt`, `dress`, `shoes`. Endpoint phân tích dùng metadata nhận diện
để gọi Gemini; khi Gemini lỗi vẫn trả kết quả YOLO, không tạo gợi ý giả.
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
Pose Full chính thức vào `backend/models/pose_landmarker_full.task`; backend
không tự tải model khi khởi động. Nếu chưa có Full, backend dùng model Lite
đang có. Có thể dùng `POSE_MODEL_PATH` để chọn model khác.

`backend/.env`:

```dotenv
OPENAI_API_KEY=
OPENAI_MODEL=gpt-5.6-luna
OPENAI_TIMEOUT_SECONDS=12
GEMINI_API_KEY=
GEMINI_MODEL=gemini-3.5-flash-lite
GEMINI_TIMEOUT_SECONDS=45
```

Không có key hoặc lỗi 429/quota/timeout/network/model/schema sẽ trả
`source: unavailable`, `evaluation: null` và thông báo lỗi; nhãn YOLO vẫn có.
Không log API key và không dùng gợi ý dự phòng. `gemini-2.5-flash-lite` có thể
không còn khả dụng cho API key mới, nên cấu hình mặc định là 3.5 Flash-Lite.
Backend chờ tối đa 45 giây; yêu cầu dùng mức suy luận tối thiểu và giới hạn số
token đầu ra để giảm độ trễ và chi phí.

Endpoint thời tiết dùng Open-Meteo miễn phí, không cần API key. Backend gọi API
bất đồng bộ với timeout; lỗi upstream được trả rõ ràng, không tạo số liệu giả.

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

Giữ `--host 0.0.0.0` để backend nhận kết nối qua các địa chỉ mạng của máy tính.
Trong `lib/config/api_config.dart`, dùng IP Wi-Fi thật của máy tính (không dùng
`0.0.0.0` làm URL của app). `127.0.0.1`
chỉ cho phép máy tính tự kết nối, không dùng được trực tiếp từ điện thoại.
Kiểm tra `http://IP_WIFI_MAY_TINH:8000/health` trong trình duyệt điện thoại.

Android Studio: cấu hình `main.dart` có bước **Before launch → Start local
backend**. Bước này gọi `scripts/ensure_dev_backend.py`, dùng lại backend đang
sẵn sàng hoặc chạy nền bằng Python trong `.venv`, đợi `/health` tối đa 90 giây
rồi mới chạy Flutter. Nếu lỗi, IDE dừng bước chạy và chỉ ra log
`.dart_tool/backend/server.log` ở thư mục gốc. Backend tiếp tục chạy khi dừng
Flutter; không tự nạp lại mã Python. Sau khi sửa backend, dừng tiến trình backend
cũ rồi bấm Run lại. Cấu hình này dành cho Android Studio trên Windows và yêu
cầu plugin Shell Script có sẵn được bật.

Các route:

- `GET /health`: trạng thái model, device và đường dẫn model.
- `GET /api/v1/classes`: lớp model và kết quả chuẩn hóa.
- `POST /api/v1/detect`: endpoint YOLO cũ, nhận JPEG/PNG/WebP.
- `POST /api/v1/outfit/analyze`: multipart YOLO + đánh giá, chỉ nhận JPEG/PNG.
- `POST /api/v1/weather/current`: nhận latitude/longitude trong JSON body, gọi
  Open-Meteo và trả `temperature_c`, `apparent_temperature_c`,
  `precipitation_mm_current_interval`, `precipitation_interval_minutes`,
  `weather_code`, `temperature_max_c_today`, `temperature_min_c_today`,
  `precipitation_probability_max_percent_today`, thời điểm và nguồn. Lượng mưa
  hiện tại (mm) khác với xác suất mưa cao nhất trong ngày (%).
- `POST /api/v1/outfit/suggest`: tạo bộ đồ mới chỉ từ hồ sơ, giới tính, thời tiết
  hoặc mùa, phong cách và hoàn cảnh. Không dùng ảnh/YOLO; metadata `items` từ
  client cũ bị loại bỏ và `color_score` luôn là `null`.
- `POST /api/v1/outfit/chat`: hỏi tiếp với cùng bối cảnh không ảnh và tối đa 12
  lượt lịch sử từ ứng dụng (chỉ gửi sáu lượt gần nhất sang Gemini). Metadata
  quần áo từ client cũ cũng bị loại bỏ. Hai endpoint dùng `store=False`.
- `WS /api/v1/pose/ws`: binary JPEG → MediaPipe Pose landmark/anchor.
- `GET /docs`: Swagger UI để thử cả hai endpoint.

Endpoint phân tích nhận `file`, `height_cm`, `weight_kg`, `season`,
`temperature_c`, `style`, `occasion`, `confidence` và tùy chọn `weather_json`
chứa dữ liệu Open-Meteo có cấu trúc. Ảnh tối đa 10 MB và chỉ tồn
tại trong request. Gemini chỉ nhận loại đồ, màu, confidence, profile và context;
không nhận bytes/base64/path/URL ảnh.
Khi có `weather_json`, backend dùng nhiệt độ Open-Meteo và bỏ `season` thủ công;
`season`, `temperature_c`, `height_cm`, `weight_kg` đều cho phép bỏ trống.
Không có thời tiết/mùa/nhiệt độ thì `season_temperature_score=null`; thiếu
chiều cao hoặc cân nặng thì `body_proportion_score=null`. Các điểm thiếu không
bị tính là 0: điểm tổng được chuẩn hóa theo những tiêu chí còn lại. Dữ liệu có
gửi vẫn phải đúng giới hạn. Gợi ý/chat nhận thêm `style` và `occasion`, không
tự suy mùa từ nhiệt độ.

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
├── routers/weather.py              # proxy Open-Meteo bất đồng bộ
├── schemas/outfit_analysis.py      # request/response/Structured Output
├── schemas/pose_result.py          # config và pose response
├── services/color_detector.py      # màu chính + tối đa hai màu phụ
├── services/gemini_fashion_service.py  # đánh giá, gợi ý và chatbot
├── services/openai_outfit_service.py   # mã cũ, không còn nối vào endpoint
├── services/rule_based_outfit_service.py # mã cũ, không còn nối vào endpoint
├── services/pose_anchor_service.py
├── services/pose_landmarker_service.py
├── scripts/download_pose_model.py
└── tests/
```

## Kiểm thử

```powershell
.\backend\.venv\Scripts\python.exe -m pytest backend\tests -v
```

Test mock YOLO, Gemini và MediaPipe; kiểm tra ảnh, anchor, visibility, WebSocket
config/frame lỗi, trường hợp không thấy người và không lưu frame. Không phát
sinh chi phí API.

## Lỗi thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| `/health` báo `model_loaded: false` | Kiểm tra `backend/models/best.pt`, Ultralytics/PyTorch và `MODEL_PATH`. |
| `/api/v1/outfit/analyze` trả 503 | Model chưa tải được; xem `/health` và log server. |
| WebSocket báo không tìm thấy model pose | Chạy `python backend/scripts/download_pose_model.py` từ thư mục gốc. |
| Trả 400 | Gửi JPG/JPEG/PNG thật, MIME đúng, không rỗng và tối đa 10 MB. |
| Trả 422 không nhận diện | Chọn ảnh rõ, đủ sáng và chụp toàn thân. |
| `source` là `unavailable` | Nhãn YOLO vẫn có; kiểm tra key, quyền model, hạn mức, mạng rồi thử lại. Không có đánh giá giả. |
| Android Emulator không kết nối | Backend dùng `--host 0.0.0.0`; Flutter dùng `http://10.0.2.2:8000`. |
| Điện thoại thật cùng Wi-Fi không kết nối | Kiểm tra IP Wi-Fi của máy tính, chạy backend với `--host 0.0.0.0`, mở `/health` từ điện thoại và kiểm tra tường lửa TCP 8000. Không cần `adb reverse`. |
