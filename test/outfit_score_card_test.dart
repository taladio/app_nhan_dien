import 'package:app_nhan_dien/models/outfit_analysis_result.dart';
import 'package:app_nhan_dien/widgets/outfit_score_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OutfitEvaluation _evaluation() => OutfitEvaluation(
  overallScore: 82.5,
  rating: 'Phù hợp',
  colorScore: 90,
  seasonTemperatureScore: 85,
  bodyProportionScore: 75,
  styleScore: 80,
  occasionScore: 80,
  summary: 'Bộ đồ hài hòa và phù hợp thời tiết.',
  strengths: <String>['Màu cân bằng.'],
  problems: <String>[],
  recommendations: <String>['Giữ cách phối.'],
  suggestedOutfit: SuggestedOutfit(
    top: 'Áo trắng',
    bottom: 'Quần be',
    outerwear: null,
    shoes: 'Giày trắng',
    reason: 'Phù hợp.',
  ),
);

void main() {
  testWidgets('hiển thị tổng điểm, xếp loại và năm điểm thành phần', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OutfitScoreCard(evaluation: _evaluation()),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('outfit_score_card')), findsOneWidget);
    expect(find.text('82.5'), findsOneWidget);
    expect(find.text('Phù hợp'), findsOneWidget);
    expect(find.text('Màu sắc'), findsOneWidget);
    expect(find.text('Mùa và nhiệt độ'), findsOneWidget);
    expect(find.text('Tỷ lệ trang phục'), findsOneWidget);
    expect(find.text('Phong cách'), findsOneWidget);
    expect(find.text('Hoàn cảnh'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(5));
  });
}
