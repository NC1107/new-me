import 'package:flutter/material.dart';

import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';

/// Takes the place of the steps card until Health has delivered a first row.
class ConnectHealthCard extends StatelessWidget {
  const ConnectHealthCard({super.key, required this.prompted, required this.onConnect});

  final bool prompted;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('steps');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                child: Icon(questIcon('steps'), size: 26, color: palette.lip),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text('Steps', style: AppText.headline.copyWith(fontSize: 17))),
            ],
          ),
          const SizedBox(height: 10),
          if (prompted)
            Text(
              'No steps yet. Open Health > Sharing > Apps > New Me and allow Steps.',
              style: AppText.body.copyWith(fontSize: 15, color: kInkSecondary),
            )
          else ...[
            Text(
              'Connect Health to count your steps. They are left out of today until the first sync.',
              style: AppText.body.copyWith(fontSize: 15, color: kInkSecondary),
            ),
            const SizedBox(height: 14),
            ChunkyButton.secondary(
              label: 'Connect Health',
              icon: Icons.favorite_rounded,
              onPressed: onConnect,
            ),
          ],
        ],
      ),
    );
  }
}
