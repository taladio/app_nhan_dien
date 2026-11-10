import '../models/body_profile.dart';
import '../models/outfit_context_options.dart';
import '../models/outfit_analysis_result.dart';
import '../models/weather_snapshot.dart';

class OutfitSuggestion {
  const OutfitSuggestion({
    required this.title,
    required this.top,
    required this.bottom,
    required this.outerwear,
    required this.shoes,
    required this.fitTip,
    required this.reason,
  });

  final String title;
  final String top;
  final String bottom;
  final String outerwear;
  final String shoes;
  final String fitTip;
  final String reason;
}

OutfitSuggestion suggestOutfit({
  required BodyProfile profile,
  required String season,
  required double temperatureC,
  WeatherSnapshot? weather,
  List<DetectedOutfitItem> detectedItems = const <DetectedOutfitItem>[],
  String occasion = 'outing',
}) {
  final rainy =
      season == 'rainy' ||
      (weather?.isRainingNow ?? false) ||
      (weather?.rainLikelyToday ?? false);
  final cool = temperatureC < 18 || season == 'winter';
  final hot = temperatureC >= 28 || season == 'summer';
  final recognized = detectedItems.map((item) => item.className).toSet();
  final formal = occasion == 'work' || occasion == 'school';
  final active = occasion == 'sport' || occasion == 'travel';
  final recognizedNote = recognized.isEmpty
      ? 'Chưa có ảnh YOLO; đây là gợi ý từ hồ sơ và bối cảnh.'
      : 'Dựa thêm trên đồ YOLO nhận diện: ${detectedItems.map((item) => item.classNameVi).toSet().join(', ')}.';
  final occasionNote =
      'Hoàn cảnh ${occasionLabels[occasion] ?? occasion.toLowerCase()}. ';
  final fitRatio = profile.weightKg / profile.heightCm;
  final fitTip = fitRatio >= 0.43
      ? 'Với số đo ${profile.heightCm.toStringAsFixed(0)} cm / ${profile.weightKg.toStringAsFixed(0)} kg, thử phom regular hoặc relaxed và cạp điều chỉnh để dễ vận động; đối chiếu bảng size của từng hãng.'
      : fitRatio <= 0.32
      ? 'Với số đo ${profile.heightCm.toStringAsFixed(0)} cm / ${profile.weightKg.toStringAsFixed(0)} kg, có thể phối lớp mỏng và chọn áo dài vừa hông; đối chiếu bảng size của từng hãng.'
      : 'Với số đo ${profile.heightCm.toStringAsFixed(0)} cm / ${profile.weightKg.toStringAsFixed(0)} kg, ưu tiên phom vừa vai và cạp thoải mái; đối chiếu bảng size của từng hãng.';

  if (rainy) {
    return OutfitSuggestion(
      title: 'Gọn nhẹ khi trời mưa',
      top: cool
          ? 'Áo dài tay thoáng, dễ phối lớp'
          : recognized.contains('tshirt')
          ? 'Giữ áo thun đã nhận diện nếu thoáng, nhanh khô'
          : 'Áo thun hoặc sơ mi thoáng, nhanh khô',
      bottom: formal
          ? 'Quần dài ống gọn hoặc chân váy phù hợp nơi học/làm'
          : 'Quần ống gọn hoặc chân váy độ dài vừa phải',
      outerwear: recognized.contains('jacket')
          ? 'Kiểm tra áo khoác đang mặc có chống nước; nếu không, mang áo mưa mỏng'
          : 'Áo khoác chống mưa mỏng, dễ gấp',
      shoes: 'Giày đế bám, hạn chế chất liệu dễ thấm nước',
      fitTip: fitTip,
      reason:
          '$occasionNote${weather == null
              ? 'Mùa mưa đã chọn.'
              : weather.isRainingNow
              ? 'Open-Meteo ghi nhận ${weather.precipitationMmCurrentInterval.toStringAsFixed(1)} mm mưa trong ${weather.precipitationIntervalMinutes.toStringAsFixed(0)} phút gần nhất.'
              : 'Xác suất mưa cao nhất hôm nay ${weather.precipitationProbabilityMaxPercentToday}%.'} $recognizedNote',
    );
  }
  if (cool) {
    return OutfitSuggestion(
      title: 'Phối lớp giữ ấm',
      top: recognized.contains('shirt')
          ? 'Giữ áo sơ mi đã nhận diện và phối thêm lớp ấm'
          : 'Áo dài tay hoặc áo len mỏng',
      bottom: 'Quần dài ống suông hoặc chân váy phối tất',
      outerwear: recognized.contains('jacket')
          ? 'Giữ áo khoác đã nhận diện nếu đủ ấm'
          : 'Áo khoác vừa vặn, có thể cởi khi vào trong nhà',
      shoes: 'Giày kín mũi dễ đi',
      fitTip: fitTip,
      reason:
          '$occasionNote Mùa ${seasonLabels[season] ?? 'đã chọn'} và nhiệt độ ${temperatureC.toStringAsFixed(0)}°C phù hợp phối nhiều lớp. $recognizedNote',
    );
  }
  if (hot) {
    return OutfitSuggestion(
      title: 'Thoáng mát và linh hoạt',
      top: recognized.contains('jacket')
          ? 'Cân nhắc cởi áo khoác đã nhận diện; chọn áo mỏng, thoáng'
          : recognized.contains('tshirt')
          ? 'Giữ áo thun đã nhận diện nếu thoáng và vừa người'
          : 'Áo thun hoặc sơ mi chất liệu thoáng',
      bottom: formal
          ? 'Quần dáng nhẹ hoặc chân váy phù hợp nơi học/làm'
          : active
          ? 'Quần dễ vận động, thoáng'
          : 'Quần dáng nhẹ hoặc chân váy thoải mái',
      outerwear: 'Áo khoác chống nắng mỏng khi ra ngoài',
      shoes: 'Giày nhẹ, thoáng hoặc sandal phù hợp hoàn cảnh',
      fitTip: fitTip,
      reason:
          '$occasionNote Mùa ${seasonLabels[season] ?? 'đã chọn'} và nhiệt độ ${temperatureC.toStringAsFixed(0)}°C nên ưu tiên đồ thoáng. $recognizedNote',
    );
  }
  return OutfitSuggestion(
    title: 'Cân bằng cho thời tiết dịu',
    top: 'Sơ mi hoặc áo thun phom vừa',
    bottom: 'Quần dài thoải mái hoặc chân váy dễ phối',
    outerwear: 'Áo khoác nhẹ mang theo',
    shoes: 'Giày thể thao hoặc giày kín mũi đơn giản',
    fitTip: fitTip,
    reason:
        '$occasionNote Nhiệt độ ${temperatureC.toStringAsFixed(0)}°C phù hợp một lớp chính và một lớp dự phòng. $recognizedNote',
  );
}
