import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'app_widgets.dart';

const _kCheckMotion = Duration(milliseconds: 220);

/// "2,000 / 8,000 steps", or "12 min + 5 pages" for the two-part reading quest.
String questProgressLabel(Quest q) {
  final alt = q.unitAlt;
  if (alt != null) {
    return '${q.actual.formatted} ${shortUnit(q.unit)} + ${(q.actualAlt ?? 0).formatted} '
        '${shortUnit(alt)}';
  }
  return '${q.actual.formatted} / ${q.target.formatted} ${shortUnit(q.unit)}';
}

String _goalLabel(Quest q) =>
    'Goal: ${q.target.formatted} ${shortUnit(q.unit)} or ${(q.targetAlt ?? 0).formatted} '
    '${shortUnit(q.unitAlt ?? '')}';

double questFraction(Quest q) {
  if (q.done) return 1;
  return q.points == 0 ? 0 : q.basePoints / q.points;
}

/// One quest: title, progress, and a "+" that opens the log sheet on its metric.
class QuestCard extends StatefulWidget {
  const QuestCard({super.key, required this.quest, required this.onTap, this.onAdd});

  final Quest quest;
  final VoidCallback onTap;

  /// Null for quests the app cannot log by hand, such as steps.
  final VoidCallback? onAdd;

  @override
  State<QuestCard> createState() => _QuestCardState();
}

class _QuestCardState extends State<QuestCard> with SingleTickerProviderStateMixin {
  late final AnimationController _check = AnimationController(
    vsync: this,
    duration: _kCheckMotion,
    value: widget.quest.done ? 1 : 0,
  );

  late final Animation<double> _checkCurve = CurvedAnimation(parent: _check, curve: Curves.easeOut);

  @override
  void didUpdateWidget(QuestCard old) {
    super.didUpdateWidget(old);
    final done = widget.quest.done;
    if (done == old.quest.done) return;
    if (!done) {
      _check.value = 0;
      return;
    }
    HapticFeedback.mediumImpact();
    if (MediaQuery.disableAnimationsOf(context)) {
      _check.value = 1;
    } else {
      _check.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _check.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quest;
    return OnyxCard(
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _check,
                  builder: (context, _) => _check.value == 0
                      ? const SizedBox.shrink()
                      : SizeTransition(
                          axis: Axis.horizontal,
                          alignment: Alignment.centerLeft,
                          sizeFactor: _checkCurve,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ScaleTransition(
                              scale: _checkCurve,
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: context.accent,
                              ),
                            ),
                          ),
                        ),
                ),
                Expanded(
                  child: Text(
                    q.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kFgPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (q.bonusPoints > 0) ...[
                  const SizedBox(width: 8),
                  _BonusChip(bonus: q.bonusPoints),
                ],
                if (widget.onAdd != null) ...[
                  const SizedBox(width: 8),
                  _AddButton(label: 'Log ${q.title}', onTap: widget.onAdd!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          ProgressBar(value: questFraction(q)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  questProgressLabel(q),
                  style: const TextStyle(
                    color: kFgSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${q.basePoints} / ${q.points} pts',
                style: const TextStyle(color: kFgMuted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (q.unitAlt != null) ...[
            const SizedBox(height: 4),
            Text(_goalLabel(q), style: const TextStyle(color: kFgMuted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _BonusChip extends StatelessWidget {
  const _BonusChip({required this.bonus});

  final int bonus;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.accentLight,
      borderRadius: BorderRadius.circular(9999),
    ),
    child: Text(
      '+$bonus',
      style: TextStyle(color: context.accent, fontSize: 12, fontWeight: FontWeight.w800),
    ),
  );
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.accent),
            ),
            child: Icon(Icons.add_rounded, size: 18, color: context.accent),
          ),
        ),
      ),
    ),
  );
}

/// The steps card before Health has ever delivered a row: it replaces the quest card.
class ConnectHealthCard extends StatelessWidget {
  const ConnectHealthCard({super.key, required this.prompted, required this.onConnect});

  final bool prompted;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return OnyxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_outline_rounded, size: 18, color: kFgSecondary),
              SizedBox(width: 8),
              Text(
                'Steps',
                style: TextStyle(color: kFgPrimary, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (prompted)
            const Text(
              'No steps yet. Open Health > Sharing > Apps > New Me and allow Steps.',
              style: TextStyle(color: kFgSecondary, fontSize: 13, height: 1.4),
            )
          else ...[
            const Text(
              'Connect Health to count your steps. They are left out of today until the first '
              'sync.',
              style: TextStyle(color: kFgSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onConnect();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.accent,
                  side: BorderSide(color: context.accent),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Connect Health', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
