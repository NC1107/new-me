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

/// One quest: category icon, plain title, a thick bar, and on the right a chunky + for quests logged by
/// hand. Progress is spoken, and written only when the title does not state the target. Completing it pops a check
/// badge, throws confetti from the badge and gives a medium haptic.
class QuestCard extends StatefulWidget {
  const QuestCard({
    super.key,
    required this.quest,
    required this.onTap,
    this.onAdd,
    this.listeningMinutes = 0,
    this.listeningNote,
  });

  final Quest quest;
  final VoidCallback onTap;

  /// Null for quests the app cannot log by hand.
  final VoidCallback? onAdd;

  /// Audiobook minutes already counted in this quest; shown under the progress when above zero.
  final int listeningMinutes;

  /// "Listening synced 3 min ago"; only passed on the reading quest of a linked person.
  final String? listeningNote;

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
                      if (q.bonusPoints > 0) _BonusChip(bonus: q.bonusPoints),
                      // Exercise is fed by Health but also takes a hand-logged activity.
                      if (widget.onAdd != null && (!automatic || q.key == 'exercise'))
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: ChunkyIconButton(
                            icon: Icons.add_rounded,
                            semanticLabel: q.key == 'exercise'
                                ? 'Log an activity'
                                : 'Add entry for ${questTitle(q)}',
                            onPressed: widget.onAdd,
                          ),
                        ),
                    ],
                  ),
                ),
                if (titleStatesTarget(q))
                  // Spoken only: the title and bar show the target, a screen reader still hears progress.
                  Semantics(label: questProgress(q), child: const SizedBox.shrink())
                else
                  Text(
                    questProgress(q),
                    style: AppText.tabular(AppText.caption.copyWith(color: kInkSecondary)),
                  ),
                if (q.doneBy case final by?)
                  _NoteLine(
                    icon: Icons.fitness_center_rounded,
                    color: category.lip,
                    text: doneByLabel(by),
                  ),
                if (widget.listeningMinutes > 0)
                  _NoteLine(
                    icon: Icons.headphones_rounded,
                    color: category.lip,
                    text: '${widget.listeningMinutes} min listened',
                  ),
                if (widget.listeningNote case final note?)
                  _NoteLine(icon: Icons.sync_rounded, color: category.lip, text: note),
                const SizedBox(height: 8),
                _BarWithAmount(
                  value: questFraction(q),
                  color: q.done ? person.fill : category.fill,
                  amount: titleStatesTarget(q) ? questActualLabel(q) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One small line under a quest's progress: an icon and what is worth knowing.
class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(text, style: AppText.caption.copyWith(color: kInkSecondary)),
        ),
      ],
    ),
  );
}

/// Said once under the quest list: which quests Apple Health fills in.
class HealthNote extends StatelessWidget {
  const HealthNote({super.key});

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.favorite_rounded, size: 13, color: kDanger),
      SizedBox(width: 6),
      Flexible(child: Text('From Apple Health', style: AppText.caption)),
    ],
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

/// The quest bar with the amount so far beside it, or under it when large text leaves no room.
class _BarWithAmount extends StatelessWidget {
  const _BarWithAmount({required this.value, required this.color, required this.amount});

  final double value;
  final Color color;
  final String? amount;

  @override
  Widget build(BuildContext context) {
    final bar = ThickProgressBar(value: value, color: color);
    final text = amount;
    if (text == null) return bar;
    // The card's spoken label already carries the progress.
    final label = ExcludeSemantics(
      child: Text(text, style: AppText.tabular(AppText.caption.copyWith(color: kInkSecondary))),
    );
    if (MediaQuery.textScalerOf(context).scale(10) > 13) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [bar, const SizedBox(height: 4), label],
      );
    }
    return Row(
      children: [
        Expanded(child: bar),
        const SizedBox(width: 10),
        label,
      ],
    );
  }
}
