import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/right_now.dart';
import '../../state/together.dart';
import '../../theme/tokens.dart';
import '../../util/errors.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pop_in.dart';
import '../recap/recap_cards.dart';
import '../recap/recap_screen.dart';
import '../together/cheer_chip.dart';
import 'goals_card.dart';
import 'plan_sheet.dart';
import 'readiness_card.dart';

/// Readiness is a morning card; it goes at noon even if nobody dismissed it.
const kReadinessUntilHour = 12;

sealed class RightNow {
  const RightNow();
}

class RightNowCheers extends RightNow {
  const RightNowCheers(this.cheers);

  final List<Cheer> cheers;
}

class RightNowReadiness extends RightNow {
  const RightNowReadiness(this.readiness);

  final Readiness readiness;
}

class RightNowGoals extends RightNow {
  const RightNowGoals(this.proposals);

  final List<GoalProposal> proposals;
}

class RightNowRecap extends RightNow {
  const RightNowRecap(this.recap);

  final Recap recap;
}

/// The one card Today shows under the day card, or null for none. The first match wins:
/// a cheer that just arrived, then readiness until noon, then Monday's goal proposals, then the
/// recap on Sunday evening and Monday. A dismissed card falls through to the next.
///
/// [cheers] are the ones not yet dismissed. [now] is the phone's local time.
RightNow? pickRightNow({
  required DateTime now,
  List<Cheer> cheers = const [],
  Readiness? readiness,
  bool readinessDismissed = false,
  List<GoalProposal> proposals = const [],
  Recap? recap,
  bool recapDismissed = false,
}) {
  if (cheers.isNotEmpty) return RightNowCheers(cheers);
  if (readiness != null && !readinessDismissed && now.hour < kReadinessUntilHour) {
    return RightNowReadiness(readiness);
  }
  if (isMonday(now) && proposals.isNotEmpty) return RightNowGoals(proposals);
  if (recap != null && !recapDismissed && recapWindow(now)) return RightNowRecap(recap);
  return null;
}

/// The slot itself: gathers what each candidate card needs and draws the winner.
class RightNowSlot extends ConsumerWidget {
  const RightNowSlot({super.key, required this.today});

  final Today today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final memory = ref.watch(rightNowMemoryProvider);
    final cheerMemory = ref.watch(cheerMemoryProvider);
    final proposals = ref.watch(goalProposalsProvider).value?.proposals ?? const [];
    final recap = recapWindow(now) ? ref.watch(recapProvider(null)).value : null;
    final picked = pickRightNow(
      now: now,
      cheers: cheerMemory.loaded
          ? [
              for (final c in today.cheers)
                if (!cheerMemory.isDismissed(today.localToday, c)) c,
            ]
          : const [],
      readiness: today.readiness,
      readinessDismissed: !memory.loaded || memory.has(readinessDismissKey(today.localToday)),
      proposals: proposals,
      recap: recap,
      recapDismissed: !memory.loaded || (recap != null && memory.has(recapDismissKey(recap.week))),
    );
    if (picked == null) return const SizedBox.shrink();
    final card = switch (picked) {
      RightNowCheers(:final cheers) => CheerChip(cheers: cheers, date: today.localToday),
      RightNowReadiness(:final readiness) => ReadinessCard(
        readiness: readiness,
        onTap: () => _openReadiness(context, readiness),
        onDismiss: () => ref
            .read(rightNowMemoryProvider.notifier)
            .dismiss(readinessDismissKey(today.localToday)),
      ),
      RightNowGoals(:final proposals) => GoalsCard(
        proposals: proposals,
        onAccept: (p) =>
            _decide(context, ref, () => ref.read(goalProposalsProvider.notifier).accept(p.key)),
        onDismiss: (p) =>
            _decide(context, ref, () => ref.read(goalProposalsProvider.notifier).dismiss(p.key)),
      ),
      RightNowRecap(:final recap) => RecapNowCard(
        recap: recap,
        onTap: () => pushPage(context, RecapScreen(week: recap.week)),
        onDismiss: () =>
            ref.read(rightNowMemoryProvider.notifier).dismiss(recapDismissKey(recap.week)),
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: kCardGap),
      child: PopIn(key: ValueKey(picked.runtimeType), child: card),
    );
  }

  void _openReadiness(BuildContext context, Readiness readiness) {
    final plan = today.plan;
    showReadinessSheet(
      context,
      readiness: readiness,
      onOpenPlan: plan == null
          ? null
          : () {
              Navigator.of(context).pop();
              showPlanSheet(context, plan: plan, readiness: readiness);
            },
    );
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, Future<void> Function() call) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call();
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is Exception ? errorCopy(e) : 'Could not save that')),
      );
    }
  }
}
