import 'package:flutter/material.dart';

import '../models/outfit_analysis_result.dart';

class OutfitScoreCard extends StatelessWidget {
  const OutfitScoreCard({super.key, required this.evaluation});

  final OutfitEvaluation evaluation;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('outfit_score_card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    evaluation.overallScore.toStringAsFixed(1),
                    key: const Key('overall_score'),
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        evaluation.rating,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(evaluation.summary),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (evaluation.colorScore != null)
              _ScoreRow(label: 'Màu sắc', score: evaluation.colorScore!)
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('Màu sắc: chưa đủ dữ liệu để chấm điểm'),
              ),
            _ScoreRow(
              label: 'Mùa và nhiệt độ',
              score: evaluation.seasonTemperatureScore,
            ),
            _ScoreRow(
              label: 'Tỷ lệ trang phục',
              score: evaluation.bodyProportionScore,
            ),
            _ScoreRow(label: 'Phong cách', score: evaluation.styleScore),
            _ScoreRow(label: 'Hoàn cảnh', score: evaluation.occasionScore),
          ],
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.label, required this.score});

  final String label;
  final double? score;

  @override
  Widget build(BuildContext context) {
    final value = score;
    if (value == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text('$label: chưa đủ dữ liệu để chấm điểm'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          SizedBox(width: 128, child: Text(label)),
          Expanded(
            child: LinearProgressIndicator(
              value: value.clamp(0, 100) / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(
              value.toStringAsFixed(0),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
