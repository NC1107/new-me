import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/training.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/choice_card.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import 'exercises_page.dart';
import 'session_page.dart';
import 'training_copy.dart';

/// Offers the plan's sessions on a rest day, the next one first, and opens the one picked.
Future<void> showPullDaySheet(
  BuildContext context, {
  required TrainingPlan plan,
  required String date,
}) => showAppSheet<void>(
  context,
  builder: (_) => PullDaySheet(plan: plan, date: date),
);

class PullDaySheet extends ConsumerStatefulWidget {
  const PullDaySheet({super.key, required this.plan, required this.date});

  final TrainingPlan plan;

  /// Today, YYYY-MM-DD; the days are listed from tomorrow on.
  final String date;

  @override
  ConsumerState<PullDaySheet> createState() => _PullDaySheetState();
}

class _PullDaySheetState extends ConsumerState<PullDaySheet> {
  int? _busy;
  String? _error;

  /// Plan day indexes in the order they come up after today.
  List<int> get _order {
    final weekday = parseLocalDate(widget.date).weekday;
    final days = widget.plan.days;
    return [
      for (var i = 0; i < days.length; i++) i,
    ]..sort((a, b) => _ahead(weekday, days[a].weekday).compareTo(_ahead(weekday, days[b].weekday)));
  }

  static int _ahead(int from, int to) => (to - from + 6) % 7;

  Future<void> _pull(int index) async {
    if (_busy != null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _busy = index;
      _error = null;
    });
    try {
      await ref.read(trainingTodayProvider.notifier).pullDay(index);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      await pushPage(navigator.context, const SessionPage());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.plan.days;
    String count(int n) => '$n ${n == 1 ? 'exercise' : 'exercises'}';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: const Text('Train today', style: AppText.title)),
            const SizedBox(height: 6),
            Text(
              'Do one of your sessions now. It stays on its own day in the plan too.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
            const SizedBox(height: 16),
            for (final i in _order) ...[
              ChoiceCard(
                icon: Icons.fitness_center_rounded,
                title: days[i].label,
                subtitle: _busy == i
                    ? 'Starting…'
                    : '${weekdayLabel(days[i].weekday)} · ${count(days[i].exercises.length)}',
                onTap: _busy == null ? () => _pull(i) : null,
              ),
              const SizedBox(height: 10),
            ],
            if (_error case final error?) ...[
              Text(error, style: AppText.label.copyWith(color: kDangerText)),
              const SizedBox(height: 10),
            ],
            TextButton(
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                pushPage(navigator.context, const ExercisesPage());
              },
              child: const Text('Log single sets instead'),
            ),
          ],
        ),
      ),
    );
  }
}
