import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/v7.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import 'streak_visuals.dart';

/// A missed day can be covered until this hour the next morning.
const kCoverClosesHour = 10;

/// The day the partner could be covered for, or null when they cannot: they missed yesterday
/// (not counted, frozen, away or repaired), hold no freeze of their own, and I hold one.
///
/// The server has the last word and refuses what is closed, so this only hides the action when
/// it plainly cannot work.
String? coverableDate({
  required BoardUser me,
  required BoardUser partner,
  required String localToday,
  required DateTime now,
}) {
  if (now.hour >= kCoverClosesHour) return null;
  if (me.freezes.held < 1 || partner.freezes.held > 0) return null;
  final yesterday = previousDate(localToday);
  final mark = partner.last7.where((d) => d.date == yesterday).firstOrNull;
  if (mark == null) return null;
  final handled = mark.counted || mark.frozen || mark.away || mark.repaired;
  return handled ? null : yesterday;
}

/// "that day can no longer be covered" as a sentence.
String sentenceCase(String s) {
  if (s.isEmpty) return s;
  final cased = s[0].toUpperCase() + s.substring(1);
  return cased.endsWith('.') ? cased : '$cased.';
}

String coverError(Object e) {
  if (e is ApiException) {
    return switch (e.code) {
      'no_freeze' => 'You have no freeze to spend.',
      'cover_closed' => sentenceCase(e.message),
      _ => errorCopy(e),
    };
  }
  return errorCopy(e);
}

/// "Cover Nadia": spends one of my freezes on the partner's missed day, in one tap.
class CoverCard extends ConsumerStatefulWidget {
  const CoverCard({super.key, required this.partner, required this.date});

  final BoardUser partner;

  /// The partner's missed day, yyyy-MM-dd.
  final String date;

  @override
  ConsumerState<CoverCard> createState() => _CoverCardState();
}

class _CoverCardState extends ConsumerState<CoverCard> {
  bool _busy = false;
  String? _error;

  Future<void> _cover() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(streakActionsProvider).cover(widget.date);
      HapticFeedback.mediumImpact();
    } on Object catch (e) {
      if (mounted) setState(() => _error = coverError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.partner.name;
    final palette = accentById(widget.partner.color);
    return AppCard(
      color: kFreezeWash,
      borderColor: kFreezeFill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: kSurface, shape: BoxShape.circle),
                child: Icon(Icons.ac_unit_rounded, size: 24, color: palette.lip),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('$name missed yesterday', style: AppText.headline)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Spend one of your freezes to keep your streaks going. It is open until 10:00.',
            style: AppText.label.copyWith(color: kInkSecondary),
          ),
          const SizedBox(height: 12),
          ChunkyButton(
            label: 'Cover $name',
            icon: Icons.ac_unit_rounded,
            busy: _busy,
            onPressed: _cover,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppText.label.copyWith(color: kDangerText)),
          ],
        ],
      ),
    );
  }
}
