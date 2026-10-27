import 'package:flutter/material.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/dismiss_x.dart';
import 'about_you.dart';

const _names = {
  AboutQuestion.birthYear: 'birth year',
  AboutQuestion.sex: 'sex',
  AboutQuestion.height: 'height',
  AboutQuestion.weight: 'weight',
};

/// "birth year, sex and weight" for the questions still open, in the order they are asked.
String missingList(List<AboutQuestion> missing) {
  final names = [for (final q in missing) ?_names[q]];
  if (names.length <= 1) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// The Today "right now" card that asks for what the targets still need.
class SetupNowCard extends StatelessWidget {
  const SetupNowCard({
    super.key,
    required this.missing,
    required this.onTap,
    required this.onDismiss,
  });

  final List<AboutQuestion> missing;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = accentById('teal');
    final line = 'Add your ${missingList(missing)} so your targets can be worked out.';
    return AppCard(
      onTap: onTap,
      semanticLabel: 'Finish your setup. $line',
      padding: const EdgeInsets.fromLTRB(14, 6, 2, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
              child: Icon(Icons.person_rounded, size: 24, color: palette.lip),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Finish your setup', style: AppText.headline.copyWith(fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(line, style: AppText.label.copyWith(color: kInkSecondary)),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Open About you',
                            style: AppText.label.copyWith(color: context.accentText),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: context.accentText),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          DismissX(label: 'Dismiss setup for a week', onPressed: onDismiss),
        ],
      ),
    );
  }
}
