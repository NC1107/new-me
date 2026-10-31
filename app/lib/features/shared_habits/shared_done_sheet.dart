import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/shared_habit_models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pressable.dart';

/// Asks who did the chore: me, my partner or both of us. Answers a [SharedBy], or null when the
/// sheet is dismissed.
Future<String?> showSharedDoneSheet(BuildContext context, SharedHabit habit, String partner) =>
    showAppSheet<String>(
      context,
      builder: (_) => SharedDoneSheet(habit: habit, partner: partner),
    );

class SharedDoneSheet extends StatelessWidget {
  const SharedDoneSheet({super.key, required this.habit, required this.partner});

  final SharedHabit habit;
  final String partner;

  @override
  Widget build(BuildContext context) {
    final alone = sharedCredit(SharedBy.together, habit.gems);
    final pending = habit.proposedWorth;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kGutter,
        4,
        kGutter,
        kGutter + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Who did ${habit.name}?', style: AppText.title)),
          const SizedBox(height: 4),
          Text(
            pending == null
                ? 'It is worth ${plural(habit.gems, 'gem', 'gems')}.'
                : 'It pays ${plural(habit.gems, 'gem', 'gems')} until you agree on $pending.',
            style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _Choice(
            icon: Icons.person_rounded,
            title: 'Me',
            detail: 'You earn ${plural(habit.gems, 'gem', 'gems')}',
            onTap: () => _pick(context, SharedBy.self),
          ),
          const SizedBox(height: 10),
          _Choice(
            icon: Icons.person_outline_rounded,
            title: partner,
            detail: '$partner earns ${plural(habit.gems, 'gem', 'gems')}',
            onTap: () => _pick(context, SharedBy.partner),
          ),
          const SizedBox(height: 10),
          _Choice(
            icon: Icons.people_alt_rounded,
            title: 'Together',
            detail: '${alone.mine} for you, ${alone.theirs} for $partner',
            onTap: () => _pick(context, SharedBy.together),
          ),
        ],
      ),
    );
  }

  void _pick(BuildContext context, String by) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(by);
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    return Semantics(
      button: true,
      label: '$title, $detail',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder, width: kBorderWidth),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                child: Icon(icon, size: 22, color: palette.lip),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 22, color: kInkSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
