import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/weather_snapshot.dart';

class WeatherException implements Exception {
  const WeatherException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CurrentLocation {
  const CurrentLocation(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class WeatherCity {
  const WeatherCity(this.id, this.name, this.location);

  final String id;
  final String name;
  final CurrentLocation location;
}

const weatherCities = <WeatherCity>[
  WeatherCity('hanoi', 'Hà Nội', CurrentLocation(21.03, 105.85)),
  WeatherCity('danang', 'Đà Nẵng', CurrentLocation(16.05, 108.20)),
  WeatherCity('hue', 'Huế', CurrentLocation(16.46, 107.59)),
  WeatherCity('hcmc', 'TP. Hồ Chí Minh', CurrentLocation(10.82, 106.63)),
  WeatherCity('cantho', 'Cần Thơ', CurrentLocation(10.05, 105.75)),
];

abstract interface class CurrentLocationService {
  Future<CurrentLocation> current();
}

class DeviceLocationService implements CurrentLocationService {
  @override
  Future<CurrentLocation> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const WeatherException(
          'Hãy bật Vị trí trên điện thoại để lấy thời tiết hiện tại.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const WeatherException(
          'Quyền vị trí đã bị chặn. Hãy bật lại trong Cài đặt ứng dụng.',
        );
      }
      if (permission == LocationPermission.denied) {
        throw const WeatherException(
          'Bạn chưa cấp quyền vị trí. Có thể dùng chế độ thủ công.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return CurrentLocation(position.latitude, position.longitude);
    } on WeatherException {
      rethrow;
    } catch (_) {
      throw const WeatherException(
        'Không lấy được vị trí hiện tại. Hãy thử lại hoặc dùng chế độ thủ công.',
      );
    }
  }
}

abstract interface class WeatherService {
  Future<WeatherSnapshot> currentAt(CurrentLocation location);
}

class BackendWeatherService implements WeatherService {
  BackendWeatherService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<WeatherSnapshot> currentAt(CurrentLocation location) async {
    final uri = ApiConfig.weatherCurrentUri();
    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, double>{
              'latitude': double.parse(location.latitude.toStringAsFixed(2)),
              'longitude': double.parse(location.longitude.toStringAsFixed(2)),
            }),
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const WeatherException(
        'Backend thời tiết phản hồi quá chậm. Hãy thử lại.',
      );
    } on http.ClientException {
      throw const WeatherException(
        'Không kết nối được backend thời tiết. Kiểm tra USB/Wi-Fi và thử lại.',
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        final detail = decoded is Map ? decoded['detail'] : null;
        throw WeatherException(
          detail is String
              ? detail
              : 'Không lấy được thời tiết từ Open-Meteo. Vui lòng thử lại.',
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw const WeatherException('Dữ liệu thời tiết không hợp lệ.');
      }
      return WeatherSnapshot.fromJson(decoded);
    } on WeatherException {
      rethrow;
    } on FormatException {
      throw const WeatherException('Dữ liệu thời tiết không hợp lệ.');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
