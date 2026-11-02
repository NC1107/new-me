import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../util/errors.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/me.dart';
import '../../state/session.dart';
import '../../state/together.dart';
import '../../state/together_prefs.dart';
import '../../state/together_seen.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../shell/home_tab.dart';
import 'celebration_sheet.dart';
import 'challenge_card.dart';
import 'reward_proposals_card.dart';
import 'rewards_section.dart';
import 'task_proposals_card.dart';
import 'tasks_section.dart';

/// Everything shared on Us below the two people: the weekly challenge, answers my partner waits
/// on, and the rewards. Also where the "we did it" celebrations play, once each.
class TogetherSection extends ConsumerStatefulWidget {
  const TogetherSection({super.key, required this.board});

  final Board board;

  @override
  ConsumerState<TogetherSection> createState() => _TogetherSectionState();
}

class _TogetherSectionState extends ConsumerState<TogetherSection> {
  bool _checking = false;
  bool _claiming = false;
  String? _claimError;

  Board get board => widget.board;

  bool get _wantsCelebration {
    final ch = board.challenge;
    final r = board.reward;
    return (ch != null && ch.done) || (r != null && r.ready);
  }

  void _maybeCelebrate(bool onUs) {
    if (!onUs || _checking || !_wantsCelebration) return;
    _checking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_celebrate()));
  }

  /// Waits for the Us tab and for any sheet that is still closing, then plays what has not
  /// played before: the challenge first, then the reward.
  Future<void> _celebrate() async {
    try {
      if (!await _settled()) return;
      final ch = board.challenge;
      if (ch != null && ch.done && await TogetherPrefs.celebratedChallenge() != ch.endsOn) {
        await ref.read(togetherSeenProvider.notifier).markChallenge(ch.endsOn);
        if (!mounted) return;
        await showCelebrationSheet(
          context,
          title: 'Challenge complete!',
          message: '${ch.title}\n+$kChallengeBonus gems each',
          users: board.users,
        );
        if (!await _settled()) return;
      }
      final r = board.reward;
      if (r != null && r.ready && await TogetherPrefs.celebratedReward() != r.id) {
        await ref.read(togetherSeenProvider.notifier).markReward(r.id);
        if (!mounted) return;
        await showCelebrationSheet(
          context,
          title: 'Reward ready!',
          message: r.name,
          users: board.users,
          buttonLabel: 'We did it',
          onPressed: () => ref.read(rewardsProvider.notifier).claim(r.id),
        );
      }
    } finally {
      _checking = false;
    }
  }

  Future<bool> _settled() async {
    for (var i = 0; i < 40; i++) {
      if (!mounted) return false;
      final route = ModalRoute.of(context);
      if (route == null || route.isCurrent) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<void> _claim(Reward reward) async {
    setState(() {
      _claiming = true;
      _claimError = null;
    });
    try {
      await ref.read(rewardsProvider.notifier).claim(reward.id);
    } on ApiException catch (e) {
      if (mounted) setState(() => _claimError = errorCopy(e));
    } on Object {
      if (mounted) setState(() => _claimError = 'Could not save that. Try again.');
    }
    if (mounted) setState(() => _claiming = false);
  }

  @override
  Widget build(BuildContext context) {
    _maybeCelebrate(ref.watch(homeTabProvider) == HomeTab.board);
    final people = [for (final u in board.users) accentById(u.color)];
    final today =
        ref.watch(meProvider.select((m) => m.value?.data.localToday)) ??
        formatDateKey(ref.watch(clockProvider)());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (board.challenge case final challenge?) ...[
          const SizedBox(height: kCardGap),
          ChallengeCard(
            challenge: challenge,
            today: today,
            people: people,
            myId: ref.watch(sessionProvider.select((s) => s.session?.userId)),
          ),
        ],
        if (board.lastChallenge case final last?) ...[
          const SizedBox(height: kCardGap),
          ChallengeCard(
            challenge: last,
            today: today,
            people: people,
            myId: ref.watch(sessionProvider.select((s) => s.session?.userId)),
          ),
        ],
        const SizedBox(height: kCardGap),
        const RewardProposalsCard(),
        const TaskProposalsCard(),
        const SizedBox(height: kCardGap),
        RewardsSection(board: board, claiming: _claiming, claimError: _claimError, onClaim: _claim),
        const SizedBox(height: 28),
        Semantics(header: true, child: const Text('Tasks', style: AppText.headline)),
        const SizedBox(height: 4),
        const Text(
          'A chore with gems on it. Finish it by the deadline to earn them, or they come off.',
          style: AppText.caption,
        ),
        const SizedBox(height: 10),
        const TasksSection(),
      ],
    );
  }
}
