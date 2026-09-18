import 'package:flutter/material.dart';

import '../models/outfit_analysis_result.dart';

class OutfitSuggestionCard extends StatelessWidget {
  const OutfitSuggestionCard({super.key, required this.evaluation});

  final OutfitEvaluation evaluation;

  @override
  Widget build(BuildContext context) {
    final suggestion = evaluation.suggestedOutfit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TextListCard(
          title: 'Điểm mạnh',
          icon: Icons.check_circle_outline,
          items: evaluation.strengths,
          emptyText: 'Chưa có điểm mạnh nổi bật được ghi nhận.',
        ),
        _TextListCard(
          title: 'Điểm cần điều chỉnh',
          icon: Icons.tune,
          items: evaluation.problems,
          emptyText: 'Không có vấn đề đáng kể.',
        ),
        _TextListCard(
          title: 'Khuyến nghị',
          icon: Icons.lightbulb_outline,
          items: evaluation.recommendations,
          emptyText: 'Chưa có khuyến nghị bổ sung.',
        ),
        Card(
          key: const Key('suggested_outfit_card'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Bộ đồ được đề xuất',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (suggestion.top != null) _line('Áo', suggestion.top!),
                if (suggestion.bottom != null)
                  _line('Quần / váy', suggestion.bottom!),
                if (suggestion.outerwear != null)
                  _line('Áo khoác', suggestion.outerwear!),
                if (suggestion.shoes != null) _line('Giày', suggestion.shoes!),
                const Divider(height: 24),
                Text(suggestion.reason),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $value'),
    );
  }
}

class _TextListCard extends StatelessWidget {
  const _TextListCard({
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyText,
  });

  final String title;
  final IconData icon;
  final List<String> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              Text(emptyText)
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text('• $item'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
