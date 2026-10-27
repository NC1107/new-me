import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/together.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/pop_in.dart';
import 'cheer_style.dart';

/// "Nadia cheered your day" with the reactions, until it is dismissed. A dismissal is
/// remembered for the day, and a new kind arriving later brings the chip back.
class CheerChip extends ConsumerWidget {
  const CheerChip({super.key, required this.cheers, required this.date});

  final List<Cheer> cheers;
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(cheerMemoryProvider);
    final visible = [
      for (final c in cheers)
        if (!memory.isDismissed(date, c)) c,
    ];
    if (!memory.loaded || visible.isEmpty) return const SizedBox.shrink();
    final names = <String>{
      for (final c in visible) c.fromName.isEmpty ? 'Your partner' : c.fromName,
    }.toList();
    final who = names.length == 1 ? names.first : '${names.first} and ${names.last}';
    final kinds = {for (final c in visible) c.kind}.toList()..sort((a, b) => a.index - b.index);
    final amber = accentById('amber');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: PopIn(
        child: AppCard(
          color: amber.tint,
          borderColor: amber.fill,
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          child: Row(
            children: [
              Wrap(
                spacing: 4,
                children: [
                  for (final k in kinds)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(color: kSurface, shape: BoxShape.circle),
                      child: Icon(k.icon, size: 19, color: k.palette.lip),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '$who cheered your day',
                    style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Dismiss cheer',
                excludeSemantics: true,
                onTap: () => ref.read(cheerMemoryProvider.notifier).dismiss(date, visible),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ref.read(cheerMemoryProvider.notifier).dismiss(date, visible);
                  },
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.close_rounded, size: 22, color: kInkSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
