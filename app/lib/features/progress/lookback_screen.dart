import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/v7.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/avatar.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../board/person_card.dart' show kSuccessText;
import '../training/training_copy.dart';
import 'progress_logic.dart';
import 'units_view.dart';
import '../../widgets/units_scope.dart';

/// The monthly look-back: the three biggest improvements for the couple and for each person.
/// [month] is YYYY-MM; null opens the last completed month.
class LookbackScreen extends ConsumerStatefulWidget {
  const LookbackScreen({super.key, this.month});

  final String? month;

  @override
  ConsumerState<LookbackScreen> createState() => _LookbackScreenState();
}

class _LookbackScreenState extends ConsumerState<LookbackScreen> {
  late String? _month = widget.month;

  /// The latest month this screen may show: the one it first opened on.
  String? _newest;

  @override
  Widget build(BuildContext context) {
    final lookback = ref.watch(lookbackProvider(_month));
    final loaded = lookback.value;
    if (loaded != null) _newest ??= _month ?? loaded.month;
    final newest = _newest;
    return PageScaffold(
      title: 'Monthly look-back',
      subtitle: loaded?.label,
      children: lookback.when(
        data: (lb) => [
          _MonthBar(
            label: lb.label,
            onPrevious: () => setState(() => _month = shiftMonth(lb.month, -1)),
            onNext: newest != null && lb.month.compareTo(newest) < 0
                ? () => setState(() => _month = shiftMonth(lb.month, 1))
                : null,
          ),
          const SizedBox(height: 16),
          if (!lb.complete) ...[
            Text(
              'This month is still going, so these are the improvements so far.',
              style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
          ],
          ..._sections(lb),
        ],
        error: (e, _) => [
          ErrorBlock(
            title: 'Could not load the look-back',
            error: e,
            onRetry: () async => ref.invalidate(lookbackProvider(_month)),
          ),
        ],
        loading: () => const [Center(child: CircularProgressIndicator.adaptive())],
      ),
    );
  }

  List<Widget> _sections(Lookback lb) {
    final people = lb.people;
    return [
      if (people.length > 1) ...[
        _Section(
          title: 'Together',
          leading: const Icon(Icons.favorite_rounded, color: kFlame, size: 28),
          improvements: [
            for (final i in lb.couple.improvements) improvementInUnits(i, context.units),
          ],
          facts: _facts(points: lb.couple.points, days: lb.couple.bothCountedDays, both: true),
        ),
        const SizedBox(height: kCardGap),
      ],
      for (final (i, p) in people.indexed) ...[
        if (i > 0) const SizedBox(height: kCardGap),
        _Section(
          title: p.name,
          leading: Avatar(name: p.name, palette: accentById(p.color), size: 32),
          improvements: [for (final i in p.improvements) improvementInUnits(i, context.units)],
          lifts: p.lifts,
          facts: _facts(points: p.points, days: p.countedDays),
        ),
      ],
    ];
  }

  String _facts({required int points, required int days, bool both = false}) {
    final d = days == 1 ? '1 day' : '$days days';
    return '${points.formatted} points - ${both ? 'both counted on $d' : '$d counted'}';
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.label, required this.onPrevious, required this.onNext});

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _Arrow(icon: Icons.chevron_left_rounded, label: 'Previous month', onTap: onPrevious),
      Expanded(
        child: Text(label, textAlign: TextAlign.center, style: AppText.headline),
      ),
      _Arrow(icon: Icons.chevron_right_rounded, label: 'Next month', onTap: onNext),
    ],
  );
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(icon, size: 30, color: onTap == null ? kBorder : kInk),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.leading,
    required this.improvements,
    required this.facts,
    this.lifts = const [],
  });

  final String title;
  final Widget leading;
  final List<Improvement> improvements;
  final String facts;

  /// v9: the month's exercises, best set against the first month.
  final List<Lift> lifts;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(header: true, child: Text(title, style: AppText.headline)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 42),
          child: Text(facts, style: AppText.caption),
        ),
        const SizedBox(height: 12),
        if (improvements.isEmpty)
          Text(
            'No standout improvement this month. The next one starts today.',
            style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
          )
        else
          for (final (i, imp) in improvements.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            ImprovementRow(improvement: imp),
          ],
        if (lifts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Training', style: AppText.caption.copyWith(color: kInkMuted)),
          for (final l in lifts)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.fitness_center_rounded,
                      size: 16,
                      color: l.first != null && l.value > l.first! ? kSuccess : kInkMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      liftLine(l, context.units),
                      style: AppText.label.copyWith(color: kInk, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

class ImprovementRow extends StatelessWidget {
  const ImprovementRow({super.key, required this.improvement});

  final Improvement improvement;

  @override
  Widget build(BuildContext context) {
    final i = improvement;
    final sentence = improvementSentence(i);
    return Semantics(
      container: true,
      label: '$sentence, ${improvementPct(i)}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              // Better can mean down (resting heart rate), so the arrow follows the number.
              i.value >= i.previous ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 20,
              color: kSuccessText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(sentence, style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Text(
            improvementPct(i),
            style: AppText.tabular(
              AppText.label.copyWith(color: kSuccessText, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
