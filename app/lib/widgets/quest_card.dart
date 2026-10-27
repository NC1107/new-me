import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../theme/accent.dart';
import '../theme/quest_style.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'accent_text.dart';
import 'app_card.dart';
import 'chunky_icon_button.dart';
import 'confetti.dart';
import 'pop_in.dart';
import 'quest_copy.dart';
import 'thick_progress_bar.dart';

const _kBurstLifetime = Duration(milliseconds: 1400);

/// One quest: category icon, plain title, progress, a thick bar, and on the right a chunky + for
/// quests logged by hand or an Apple Health chip for automatic ones. Completing it pops a check
/// badge, throws confetti from the badge and gives a medium haptic.
class QuestCard extends StatefulWidget {
  const QuestCard({super.key, required this.quest, required this.onTap, this.onAdd});

  final Quest quest;
  final VoidCallback onTap;

  /// Null for quests the app cannot log by hand.
  final VoidCallback? onAdd;

  @override
  State<QuestCard> createState() => _QuestCardState();
}

class _QuestCardState extends State<QuestCard> {
  final _iconKey = GlobalKey();
  bool _justDone = false;

  @override
  void didUpdateWidget(QuestCard old) {
    super.didUpdateWidget(old);
    final done = widget.quest.done;
    if (done == old.quest.done) return;
    setState(() => _justDone = done);
    if (!done) return;
    HapticFeedback.mediumImpact();
    if (!MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _burst());
    }
  }

  /// The burst lives in the root overlay so the cards below cannot paint over it.
  void _burst() {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    final iconBox = _iconKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || overlayBox == null || iconBox == null || !iconBox.attached) return;
    final centre = iconBox.localToGlobal(iconBox.size.center(Offset.zero), ancestor: overlayBox);
    final size = overlayBox.size;
    final person = context.accentPalette;
    final category = questPalette(widget.quest.key);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Confetti(
          origin: Alignment(centre.dx / size.width * 2 - 1, centre.dy / size.height * 2 - 1),
          colors: [person.fill, category.fill, kFlame, person.tint, category.tint],
          particles: 38,
          spread: 0.5,
          duration: const Duration(milliseconds: 1200),
        ),
      ),
    );
    overlay.insert(entry);
    Timer(_kBurstLifetime, entry.remove);
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quest;
    final person = context.accentPalette;
    final category = questPalette(q.key);
    final automatic = isAutomaticQuest(q.key);

    final badge = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: person.fill,
        shape: BoxShape.circle,
        border: Border.all(color: kSurface, width: 2),
      ),
      child: Semantics(
        label: 'Done',
        child: Icon(Icons.check_rounded, size: 14, color: person.onFill),
      ),
    );

    return AppCard(
      onTap: widget.onTap,
      padding: const EdgeInsets.all(14),
      // A full-strength coloured border read as an error state; a soft mix reads as done.
      borderColor: q.done ? Color.lerp(kBorder, person.fill, 0.45)! : kBorder,
      child: Row(
        children: [
          Stack(
            key: _iconKey,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: category.tint, shape: BoxShape.circle),
                child: Icon(questIcon(q.key), size: 26, color: category.lip),
              ),
              if (q.done)
                Positioned(right: -4, bottom: -4, child: _justDone ? PopIn(child: badge) : badge),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          questTitle(q),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.headline.copyWith(fontSize: 17),
                        ),
                      ),
                      if (automatic) ...[
                        if (q.bonusPoints > 0) _BonusChip(bonus: q.bonusPoints),
                      ] else if (widget.onAdd != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: ChunkyIconButton(
                            icon: Icons.add_rounded,
                            semanticLabel: 'Add entry for ${questTitle(q)}',
                            onPressed: widget.onAdd,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        questProgress(q),
                        style: AppText.tabular(AppText.caption.copyWith(color: kInkSecondary)),
                      ),
                    ),
                    if (automatic)
                      const Padding(padding: EdgeInsets.only(left: 8), child: HealthChip())
                    else if (q.bonusPoints > 0)
                      _BonusChip(bonus: q.bonusPoints),
                  ],
                ),
                const SizedBox(height: 8),
                ThickProgressBar(
                  value: questFraction(q),
                  color: q.done ? person.fill : category.fill,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks a quest that Apple Health fills in. Its label stays at a size that fits beside a title.
class HealthChip extends StatelessWidget {
  const HealthChip({super.key});

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.2,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: kSunken,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: kBorder, width: kBorderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_rounded, size: 13, color: kDanger),
          const SizedBox(width: 4),
          Text(
            'Apple Health',
            style: AppText.caption.copyWith(
              color: kInkSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}

class _BonusChip extends StatelessWidget {
  const _BonusChip({required this.bonus});

  final int bonus;

  @override
  Widget build(BuildContext context) {
    final person = context.accentPalette;
    final ink = context.accentText;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: person.tint, borderRadius: BorderRadius.circular(9999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.diamond_rounded, size: 12, color: ink),
          const SizedBox(width: 3),
          Text(
            '+$bonus',
            style: AppText.caption.copyWith(color: ink, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
