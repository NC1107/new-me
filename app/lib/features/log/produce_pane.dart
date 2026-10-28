import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import 'log_chip.dart';
import 'log_panes.dart';

/// What counts as one serving of fruit or vegetables: 80 g, per the NHS 5 A Day portion guide
/// (nhs.uk/live-well/eat-well/5-a-day/portion-sizes). The list is short on purpose, so two
/// people count the same plate the same way.
const kServingExamples = [
  '1 medium fruit: an apple, banana, pear or orange',
  '2 small fruit: plums, satsumas or kiwi fruit',
  '7 strawberries or 14 cherries',
  '3 heaped tablespoons of cooked vegetables, such as carrots, peas or sweetcorn',
  '3 celery sticks, a 5 cm piece of cucumber or 1 medium tomato',
  '1 heaped tablespoon of dried fruit, about 30 g',
  'Anything else: about 80 g',
];

/// Beans and juice are capped by the guide, and potatoes are starch rather than a vegetable.
const kServingFootnote =
    'Beans and pulses count once a day. Juice and smoothies count once however much you have. '
    'Potatoes do not count.';

/// Log fruit and vegetables: tap to add one serving at once, or a few at a time. The pane never
/// guesses servings from meals.
class ProducePane extends StatelessWidget {
  const ProducePane({super.key, required this.busy, required this.failed, required this.onLog});

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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyButton(
          label: failed ? 'Try again' : 'Add 1 serving',
          icon: Icons.add_rounded,
          busy: busy,
          onPressed: busy ? null : () => _log(1),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final n in const [2, 3, 4])
              LogChip(
                label: '+$n',
                semanticLabel: 'Add $n servings',
                enabled: !busy,
                onTap: () => _log(n),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const _ServingGuide(),
      ],
    );
  }
}

class _ServingGuide extends StatelessWidget {
  const _ServingGuide();

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: const Text('One serving is about 80 g', style: AppText.headline),
        ),
        const SizedBox(height: 8),
        for (final line in kServingExamples)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 7, right: 10),
                  child: SizedBox(
                    width: 6,
                    height: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: kInkMuted, shape: BoxShape.circle),
                    ),
                  ),
                ),
                Expanded(child: Text(line, style: AppText.body)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(kServingFootnote, style: AppText.caption.copyWith(color: kInkSecondary)),
        const SizedBox(height: 4),
        const Text('From the NHS 5 A Day portion guide.', style: AppText.caption),
      ],
    ),
  );
}
