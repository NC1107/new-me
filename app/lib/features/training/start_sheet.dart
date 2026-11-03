import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import 'calisthenics_page.dart';
import 'mobility_page.dart';
import 'session_page.dart';
import 'yoga_page.dart';

/// The one way into a workout: today's planned session when there is one, then the guided kinds.
Future<void> showStartSheet(BuildContext context, {TrainingSession? session}) {
  return showAppSheet<void>(
    context,
    builder: (_) => _StartSheet(host: context, session: session),
  );
}

class _StartSheet extends StatelessWidget {
  const _StartSheet({required this.host, required this.session});

  /// The Train screen's context: the sheet's own dies on pop, before the page is pushed.
  final BuildContext host;
  final TrainingSession? session;

  @override
  Widget build(BuildContext context) {
    final today = session;
    final strength = today != null && !today.completed ? today : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: const Text('Start a workout', style: AppText.title)),
          const SizedBox(height: 12),
          if (strength != null)
            _StartRow(
              host: host,
              title: strength.label,
              caption: strength.setsLogged == 0 ? "Today's session" : 'Continue today',
              icon: Icons.fitness_center_rounded,
              colorId: 'teal',
              page: const SessionPage(),
            ),
          _StartRow(
            host: host,
            title: 'Yoga',
            caption: '10 to 30 min flows',
            icon: Icons.spa_rounded,
            colorId: 'violet',
            page: const YogaPage(),
          ),
          _StartRow(
            host: host,
            title: 'Calisthenics',
            caption: 'No equipment',
            icon: Icons.sports_gymnastics_rounded,
            colorId: 'amber',
            page: const CalisthenicsPage(),
          ),
          _StartRow(
            host: host,
            title: 'Mobility',
            caption: '10 stretches, 11 min',
            icon: Icons.self_improvement_rounded,
            colorId: 'rose',
            page: const MobilityPage(),
          ),
        ],
      ),
    );
  }
}

class _StartRow extends StatelessWidget {
  const _StartRow({
    required this.host,
    required this.title,
    required this.caption,
    required this.icon,
    required this.colorId,
    required this.page,
  });

  final BuildContext host;
  final String title;
  final String caption;
  final IconData icon;
  final String colorId;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final accent = accentById(colorId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop();
          pushPage(host, page);
        },
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.tint,
                borderRadius: BorderRadius.circular(kRadiusField),
              ),
              child: Icon(icon, color: accent.lip, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.headline),
                  Text(caption, style: AppText.caption.copyWith(color: kInkSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kInkMuted),
          ],
        ),
      ),
    );
  }
}
