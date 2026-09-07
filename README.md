# Ứng dụng nhận diện trang phục

Ứng dụng Flutter chọn hoặc chụp ảnh, gửi ảnh đến FastAPI/YOLO, hiển thị kết quả
tiếng Việt và vẽ bounding box đúng theo `BoxFit.contain`. Ứng dụng còn có chế độ
camera realtime trên Android/iOS. Project hỗ trợ Android, Windows và Web; cấu
hình iOS cho chọn ảnh/camera cũng đã được bổ sung.

## Chuẩn bị

Từ thư mục gốc project:

```powershell
flutter pub get
```

## Đăng ký và đăng nhập

Ứng dụng khởi tạo Firebase trước khi hiển thị giao diện và dùng Email/Password
Authentication. Người dùng chưa đăng nhập sẽ thấy trang đăng nhập; phiên đã lưu
sẽ được khôi phục tự động. Khi đăng ký thành công, hồ sơ được tạo tại
`users/{uid}` trong Cloud Firestore với họ tên, email và thời gian từ máy chủ.

Tại màn hình nhận diện, nút đăng xuất nằm ở góc phải AppBar. Chức năng quên mật
khẩu gửi email đặt lại mật khẩu tới địa chỉ người dùng nhập.

Khi build Windows lần đầu, Windows có thể yêu cầu bật **Developer Mode** để các
Flutter plugin tạo symbolic link. Có thể mở phần cài đặt bằng:

```powershell
start ms-settings:developers
```

## Chạy Backend

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Kiểm tra:

- <http://127.0.0.1:8000/health>
- <http://127.0.0.1:8000/docs>

Chi tiết cài đặt Backend nằm trong [backend/README.md](backend/README.md).

## Cấu hình API_BASE_URL

Ứng dụng chỉ quản lý URL tại `lib/config/api_config.dart` và ưu tiên giá trị
compile-time:

```dart
const String.fromEnvironment('API_BASE_URL')
```

Khi không truyền `API_BASE_URL`, mặc định là:

```text
Flutter Windows/Web: http://127.0.0.1:8000
Android Emulator:    http://10.0.2.2:8000
```

Endpoint cuối cùng được chuẩn hóa thành `{baseUrl}/api/v1/detect`, không bị lặp
dấu `/`.

## Chạy Flutter

### Windows

```powershell
flutter run -d windows
```

### Web

```powershell
flutter run -d chrome
```

Backend Phần 3 đã bật CORS để Flutter Web gọi API.

### Android Emulator

```powershell
flutter run -d android
```

Android Emulator phải dùng `10.0.2.2`, không dùng `127.0.0.1`, vì localhost bên
trong emulator trỏ về chính emulator.

### Điện thoại Android thật

Tìm IPv4 của máy tính bằng `ipconfig`, sau đó chạy, ví dụ:

```powershell
flutter run --dart-define=API_BASE_URL=http://IP_MAY_TINH:8000
```

Điện thoại và máy tính phải cùng Wi-Fi. Uvicorn phải chạy với
`--host 0.0.0.0`; nếu không kết nối được, cho phép Python/Uvicorn qua Windows
Firewall trên mạng Private và kiểm tra TCP port 8000.

## Nhận diện camera realtime

Trên Android hoặc iOS, chọn **Nhận diện realtime**, cấp quyền camera rồi bấm
**Bắt đầu realtime**. Ứng dụng giữ camera preview hoạt động, lấy tối đa khoảng
1–2 khung hình mỗi giây và chỉ gửi frame mới khi request YOLO trước đó đã hoàn
tất. Cách này tránh gửi chồng request và phù hợp với backend đang chạy suy luận
tuần tự trên CPU/GPU.

Chế độ realtime không thu âm và không lưu tệp video. Nếu đổi ứng dụng, khóa màn
hình hoặc rời khỏi màn hình realtime, camera sẽ được dừng và giải phóng. Windows
và Flutter Web vẫn dùng luồng chọn ảnh hiện tại vì plugin camera chính thức đang
hỗ trợ image stream realtime trên Android/iOS trong project này.

## Kiểm thử

```powershell
flutter pub get
dart format .
flutter analyze
flutter test
```

Widget test dùng service giả, không yêu cầu Backend đang chạy. Test model kiểm tra
JSON thiếu `summary`/`bbox_normalized`; test painter kiểm tra đủ trường hợp ảnh
cùng tỉ lệ và có letterbox trên/dưới hoặc trái/phải.

## Ghi chú bảo mật

Android/iOS hiện cho phép HTTP để kết nối FastAPI trong mạng local khi phát triển.
Bản production phải dùng HTTPS và nên thu hẹp lại cấu hình cleartext/ATS thay vì
cho phép HTTP rộng rãi.
