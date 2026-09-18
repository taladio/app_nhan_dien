# Nhận diện, phân tích và thử đồ ảo realtime

Ứng dụng Flutter cho phép người dùng đăng nhập bằng Firebase Authentication,
chụp/chọn ảnh trang phục và gửi ảnh trực tiếp trong một request tới FastAPI.
Backend chạy YOLO `best.pt`, nhận diện loại đồ, màu và bounding box, sau đó chỉ
gửi **metadata** sang OpenAI để đánh giá. Ảnh không được lưu trên backend,
Firestore, Firebase Storage hay `shared_preferences`.

Nếu OpenAI chưa được cấu hình, hết credit, timeout hoặc trả dữ liệu sai schema,
backend tự chuyển sang bộ quy tắc cục bộ và Flutter hiển thị nhãn **Đánh giá cơ
bản**. Luồng nhận diện YOLO cũ `/api/v1/detect` và camera realtime vẫn được giữ.
Mục **Thử đồ ảo** dùng Camera + WebSocket + MediaPipe Pose để ghép PNG cục bộ
theo vai, hông, đầu gối và bàn chân; luồng này không gọi OpenAI hoặc Firebase.

## 1. Chuẩn bị model và backend

Môi trường đã kiểm thử dùng **Python 3.13.7** và `mediapipe 1.0.1`. Đặt file
trọng số YOLO thật đúng tại:

```text
backend/models/best.pt
```

Từ thư mục gốc repository, chạy PowerShell:

```powershell
python -m venv backend\.venv
.\backend\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r backend\requirements.txt
Copy-Item backend\.env.example backend\.env
python backend\scripts\download_pose_model.py
```

Sửa `backend/.env`:

```dotenv
OPENAI_API_KEY=
OPENAI_MODEL=gpt-5.6-luna
OPENAI_TIMEOUT_SECONDS=30
```

- Điền một API key mới nếu muốn dùng OpenAI; không đưa key vào Flutter hoặc Git.
- Để trống `OPENAI_API_KEY` để chạy hoàn toàn bằng fallback, không mất phí API.
- Nếu tài khoản không truy cập được model mặc định, đổi `OPENAI_MODEL` trong
  `.env` mà không sửa code.
- ChatGPT Plus không bao gồm chi phí OpenAI API; API có billing/credit riêng.

Tệp `.env` đã được git-ignore. Khởi chạy backend:

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Kiểm tra trên máy tính:

- Health: <http://127.0.0.1:8000/health>
- Swagger: <http://127.0.0.1:8000/docs>
- Danh sách lớp: <http://127.0.0.1:8000/api/v1/classes>
- Thử đồ realtime: `ws://127.0.0.1:8000/api/v1/pose/ws`

Trong `/docs`, mở `POST /api/v1/outfit/analyze`, chọn **Try it out**, nhập form
và chọn JPG/JPEG/PNG tối đa 10 MB để thử API.

## 2. Endpoint phân tích mới

```http
POST /api/v1/outfit/analyze
Content-Type: multipart/form-data
```

Các trường multipart:

| Trường | Ví dụ | Ghi chú |
|---|---:|---|
| `file` | `outfit.jpg` | JPG/JPEG/PNG, không rỗng, tối đa 10 MB |
| `height_cm` | `170` | Lớn hơn 0, tối đa 300 |
| `weight_kg` | `65` | Lớn hơn 0, tối đa 500 |
| `season` | `summer` | `spring`, `summer`, `autumn`, `winter`, `rainy` |
| `temperature_c` | `32` | Từ -100 đến 100 |
| `style` | `casual` | Giá trị dropdown của ứng dụng |
| `occasion` | `school` | Giá trị dropdown của ứng dụng |
| `confidence` | `0.25` | Ngưỡng YOLO từ 0 đến 1 |

Response thành công có dạng rút gọn:

```json
{
  "filename": "outfit.jpg",
  "image_width": 1080,
  "image_height": 1920,
  "source": "openai",
  "detected_items": [
    {
      "detection_id": "det_1",
      "class_id": 0,
      "raw_class_name": "T-Shirt",
      "class_name": "tshirt",
      "class_name_vi": "Áo thun",
      "primary_color": "Trắng",
      "secondary_colors": [],
      "confidence": 0.91,
      "bbox": {"x1": 220, "y1": 300, "x2": 820, "y2": 950}
    }
  ],
  "evaluation": {
    "overall_score": 82.5,
    "rating": "Phù hợp",
    "color_score": 90,
    "season_temperature_score": 85,
    "body_proportion_score": 75,
    "style_score": 80,
    "occasion_score": 80,
    "summary": "Bộ đồ hài hòa và phù hợp mức nhiệt.",
    "strengths": ["Bảng màu cân bằng."],
    "problems": [],
    "recommendations": ["Giữ một màu trung tính làm nền."],
    "suggested_outfit": {
      "top": "Áo thun trắng",
      "bottom": "Quần short màu be",
      "outerwear": null,
      "shoes": "Giày trắng",
      "reason": "Phù hợp mùa hè và hoàn cảnh đã chọn."
    }
  }
}
```

`overall_score` được backend tính lại, làm tròn một chữ số, theo công thức:

```text
color × 0.30 + season_temperature × 0.30 + body_proportion × 0.20
+ style × 0.10 + occasion × 0.10
```

Khi YOLO không thấy trang phục, endpoint trả HTTP 422 với hướng dẫn chụp ảnh rõ
hơn. Khi thiếu `best.pt`, endpoint trả HTTP 503. Lỗi OpenAI không làm request
crash mà trả response bình thường với `source: "fallback"`.

## 3. Chạy Flutter

```powershell
flutter pub get
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Hoặc dùng thiết bị Android mặc định:

```powershell
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` là địa chỉ của máy tính host nhìn từ Android Emulator; không dùng
`127.0.0.1` trong emulator vì địa chỉ đó trỏ về chính emulator. Với điện thoại
thật, dùng `http://IP_MAY_TINH:8000`, bảo đảm cùng Wi-Fi và cho phép port 8000
trong firewall. Với Windows/Web local, truyền
`--dart-define=API_BASE_URL=http://127.0.0.1:8000`.

Khi điện thoại thật kết nối bằng USB, có thể tránh phụ thuộc Wi-Fi/firewall bằng
`adb reverse`. Thay `DEVICE_ID` bằng ID từ `flutter devices`:

```powershell
H:\Android\Sdk\platform-tools\adb.exe -s DEVICE_ID reverse tcp:8000 tcp:8000
flutter run -d DEVICE_ID "--dart-define=API_BASE_URL=http://127.0.0.1:8000"
```

Nếu vừa đổi `API_BASE_URL` nhưng Flutter tái sử dụng artifact debug cũ, chạy
`flutter build apk --debug` với cùng `--dart-define` rồi cài/chạy lại ứng dụng.

HTTP cleartext chỉ được bật trong Android debug manifest. Bản release không hạ
bảo mật và nên gọi backend qua HTTPS.

## 4. Thử đồ ảo realtime

Mở **Thử đồ ảo** trên màn hình phân tích. Flutter lấy image stream camera, xoay
đúng chiều, resize tối đa 640 px, nén JPEG quality 68 trong isolate rồi gửi
khoảng 8 FPS. Chỉ có một frame đang chờ; frame đến trong lúc backend bận bị bỏ
để ưu tiên hình mới và tránh độ trễ tích lũy.

Địa chỉ WebSocket được sinh tập trung từ `API_BASE_URL`: `http` đổi thành `ws`,
`https` đổi thành `wss`, sau đó nối `/api/v1/pose/ws`. Thông điệp đầu tiên là:

```json
{
  "type": "config",
  "camera": "front",
  "mirrored": true,
  "rotation_degrees": 0,
  "frame_width": 480,
  "frame_height": 640
}
```

Các thông điệp tiếp theo là binary JPEG. Backend trả `pose_result` gồm
`frame_id`, `timestamp_ms`, `processing_ms`, `pose_detected`, `body_visible`,
12 landmark từ vai đến bàn chân và các anchor
`shoulder_center/width/angle`, `hip_center/width/angle`, `torso_center/height`,
`left_leg_length`, `right_leg_length`. Khi thiếu điểm toàn thân, response có
`pose_detected: false` và hướng dẫn đứng lùi lại.

Pose Landmarker chạy `VIDEO`, `num_poses=1`, được tải đúng một lần và suy luận
ngoài event loop. Model chính thức nằm tại:

```text
backend/models/pose_landmarker_lite.task
```

Nếu cần tải lại model mà không tự tải mỗi lần server khởi động:

```powershell
.\backend\.venv\Scripts\python.exe backend\scripts\download_pose_model.py
```

Có thể điều chỉnh ngưỡng bằng biến môi trường
`POSE_MIN_DETECTION_CONFIDENCE`, `POSE_MIN_PRESENCE_CONFIDENCE`,
`POSE_MIN_TRACKING_CONFIDENCE`, `POSE_VISIBILITY_THRESHOLD` (mặc định `0.5`).

### Thêm PNG filter

Đặt ảnh không nền, không có người mẫu và được cắt sát vào thư mục phù hợp dưới
`assets/try_on/`, rồi thêm một `TryOnFilter` trong
`lib/models/try_on_filter.dart`. Metadata nằm ngoài widget:

```dart
TryOnFilter(
  id: 'shirt_new_01',
  name: 'Áo mới',
  category: TryOnFilterCategory.top,
  assetPath: 'assets/try_on/tops/shirt_new_01.png',
  widthMultiplier: 1.4,
  heightMultiplier: 1.35,
  offsetX: 0,
  offsetY: 0.03,
)
```

Tăng/giảm `widthMultiplier` và `heightMultiplier` để khớp kích thước cơ thể;
`offsetX`, `offsetY` dịch tâm theo tỷ lệ kích thước filter;
`defaultRotation` dùng radian. Người dùng vẫn có thể kéo, chụm và xoay từng
filter, hoặc nhấn reset để về transform tự động.

Camera trước được mirror, preview `BoxFit.cover` được bù phần crop và pose được
làm mượt EMA. WebSocket tự nối lại tối đa ba lần. Độ trễ thực tế còn phụ thuộc
Wi-Fi, CPU máy chạy FastAPI, camera và thiết bị; camera vẫn hiển thị nếu backend
mất kết nối nhưng filter tự động sẽ tạm dừng.

## 5. Quyền riêng tư và Firebase

- Firebase Authentication và hồ sơ đăng ký `users/{uid}` vẫn hoạt động.
- Tính năng phân tích không dùng `firebase_storage`, URL Storage, collection tủ
  đồ hoặc lịch sử ảnh trong Firestore.
- Backend đọc ảnh trong RAM để chạy YOLO rồi giải phóng sau request; không ghi
  file ảnh, không upload và không gửi ảnh gốc sang OpenAI.
- `shared_preferences` chỉ lưu chiều cao, cân nặng, mùa, nhiệt độ, phong cách và
  hoàn cảnh để điền lại form; không lưu bytes/path ảnh.
- Frame thử đồ chỉ tồn tại trong RAM đủ lâu để MediaPipe xử lý: không ghi file,
  không log binary, không gửi OpenAI, Firebase Storage hay Firestore.

## 6. Kiểm thử

```powershell
dart format .
flutter analyze
flutter test
.\backend\.venv\Scripts\python.exe -m pytest backend\tests -v
```

Test dùng YOLO/OpenAI/MediaPipe giả nên không gọi dịch vụ mất phí. Test Flutter
bao phủ parse pose JSON, mirror/rotation/crop `BoxFit.cover`, EMA, giới hạn
scale, trạng thái kết nối, cùng các test nhận diện/phân tích có sẵn. Chi tiết
backend và xử lý sự cố nằm tại [backend/README.md](backend/README.md).
