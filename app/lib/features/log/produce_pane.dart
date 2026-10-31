import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import 'log_chip.dart';
import 'log_panes.dart';

/// Grams in one serving of fruit or vegetables, per the NHS 5 A Day portion guide
/// (nhs.uk/live-well/eat-well/5-a-day/portion-sizes).
const kServingGrams = 80;

/// What counts as one serving, grouped the way the NHS guide groups it. The list is short on
/// purpose, so two people count the same plate the same way.
const kServingGroups = [
  (
    'Fruit',
    [
      '1 medium fruit: an apple, banana, pear or orange',
      '2 small fruit: plums, satsumas or kiwi fruit',
      '7 strawberries or 14 cherries',
    ],
  ),
  (
    'Vegetables',
    [
      '3 heaped tablespoons of cooked vegetables, peas, sweetcorn or pulses',
      'A cereal bowl of salad',
      '3 celery sticks, a 5 cm piece of cucumber or 1 medium tomato',
    ],
  ),
  ('Dried fruit', ['1 heaped tablespoon of raisins or other dried fruit, about 30 g']),
];

/// Beans and juice are capped by the guide, and potatoes are starch rather than a vegetable.
const kServingFootnote =
    'Beans and pulses count once a day. Juice and smoothies count once however much you have. '
    'Potatoes do not count.';

/// Log fruit and vegetables: tap to add one serving at once, or a few at a time. The pane never
/// guesses servings from meals.
class ProducePane extends StatelessWidget {
  const ProducePane({
    super.key,
    required this.busy,
    required this.failed,
    required this.onLog,
    this.servingsToday,
  });

  /// Servings logged so far today, when Today is loaded.
  final num? servingsToday;

  final bool busy;
  final bool failed;
  final LogCallback onLog;

  void _log(int servings) {
    onLog(
      (id, date) => ActivityDraft(
        clientOpId: id,
        type: 'produce',
        quantity: servings,
        unit: 'servings',
        date: date,
      ),
      added: 'Added $servings ${servings == 1 ? 'serving' : 'servings'} of fruit and veg',
    );
  }

  Widget _chips(BuildContext context) {
    final chips = [
      for (final n in const [2, 3, 4])
        LogChip(
          label: '+$n (${n * kServingGrams} g)',
          semanticLabel: 'Add $n servings',
          enabled: !busy,
          compact: true,
          onTap: () => _log(n),
        ),
    ];
    // Three chips share one row until Dynamic Type makes them too wide for it.
    final fitsInRow = MediaQuery.textScalerOf(context).scale(15) <= 19;
    if (!fitsInRow) {
      return Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: chips);
    }
    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: chips[i]),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (servingsToday case final n?) ...[
          Text(
            'Today so far: ${_servings(n)} (${(n * kServingGrams).round()} g)',
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(color: kInkSecondary),
          ),
          const SizedBox(height: 16),
        ],
        ChunkyButton(
          label: failed ? 'Try again' : 'Add 1 serving ($kServingGrams g)',
          icon: Icons.add_rounded,
          busy: busy,
          onPressed: busy ? null : () => _log(1),
        ),
        const SizedBox(height: 12),
        _chips(context),
        const SizedBox(height: 24),
        const _ServingGuide(),
      ],
    );
  }
}

String _servings(num n) => '${n.formatted} ${n == 1 ? 'serving' : 'servings'}';

class _ServingGuide extends StatelessWidget {
  const _ServingGuide();

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: const Text('One serving is 80 g', style: AppText.headline)),
        const Text('About a handful of fruit or vegetables.', style: AppText.caption),
        for (final (group, lines) in kServingGroups) ...[
          const SizedBox(height: 12),
          Text(group, style: AppText.label.copyWith(color: kInkSecondary)),
          const SizedBox(height: 2),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A text bullet sits on the line's baseline at any text size.
                  ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('•', style: AppText.body.copyWith(color: kInkMuted)),
                    ),
                  ),
                  Expanded(child: Text(line, style: AppText.body)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
        Text(kServingFootnote, style: AppText.caption.copyWith(color: kInkSecondary)),
        const SizedBox(height: 4),
        const Text('From the NHS 5 A Day portion guide.', style: AppText.caption),
      ],
    ),
  );
}
