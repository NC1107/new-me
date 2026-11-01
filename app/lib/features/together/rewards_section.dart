import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/habit_proposals.dart';
import '../../state/session.dart';
import '../../state/together.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pressable.dart';
import 'reward_card.dart';
import 'reward_sheet.dart';

String _newRequestId() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Rewards on Us, shared and solo in one place: the gems each of you holds, the shared focus
/// reward, one list of everything else with Redeem on my solo rewards I can afford, and what
/// was earned. Shared rewards come out of the bank, solo ones out of their owner's own gems.
class RewardsSection extends ConsumerStatefulWidget {
  const RewardsSection({
    super.key,
    required this.board,
    required this.claiming,
    required this.claimError,
    required this.onClaim,
  });

  final Board board;
  final bool claiming;
  final String? claimError;
  final void Function(Reward reward) onClaim;

  @override
  ConsumerState<RewardsSection> createState() => _RewardsSectionState();
}

class _RewardsSectionState extends ConsumerState<RewardsSection> {
  // One id per solo reward for as long as its redemption is unanswered, so a retry after a lost
  // response is the same request to the server.
  final _requestIds = <int, String>{};
  int? _redeeming;
  String? _error;

  Future<void> _redeem(Reward reward, int balance) async {
    if (_redeeming != null) return;
    final ok = await confirmDialog(
      context,
      title: 'Redeem ${reward.name}?',
      message:
          '${reward.price.formatted} gems come out of your own ${balance.formatted}. '
          'You will have ${(balance - reward.price).formatted} left.',
      confirmLabel: 'Redeem',
    );
    if (!ok || !mounted || _redeeming != null) return;
    unawaited(HapticFeedback.mediumImpact());
    final requestId = _requestIds.putIfAbsent(reward.id, _newRequestId);
    setState(() {
      _redeeming = reward.id;
      _error = null;
    });
    try {
      await ref.read(rewardsProvider.notifier).redeem(reward.id, requestId: requestId);
      _requestIds.remove(reward.id);
    } on ApiException catch (e) {
      _requestIds.remove(reward.id);
      if (mounted) setState(() => _error = errorCopy(e));
    } on Object {
      if (mounted) setState(() => _error = 'Could not save that. Try again.');
    }
    if (mounted) setState(() => _redeeming = null);
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final partner = ref.watch(partnerNameProvider);
    final list = ref.watch(rewardsProvider).value;
    final focus = widget.board.reward;
    final people = [for (final u in widget.board.users) accentById(u.color)];
    final balance = list?.balanceOf(userId)?.balance ?? 0;

    final rows = <Widget>[
      if (list != null) ...[
        for (final r in list.queued)
          _RewardRow(
            key: ValueKey(r.id),
            icon: r.ready ? Icons.emoji_events_rounded : Icons.people_alt_rounded,
            iconColor: r.ready ? kFlame : kInkSecondary,
            name: r.name,
            detail: 'Shared · ${r.price.formatted} gems${r.ready ? ' · ready' : ''}',
            onTap: () => showRewardSheet(context, reward: r),
          ),
        for (final r in list.myTreats(userId))
          _RewardRow(
            key: ValueKey(r.id),
            icon: Icons.person_rounded,
            iconColor: balance >= r.price ? context.accentLip : kInkSecondary,
            name: r.name,
            detail: balance >= r.price
                ? 'Solo · ${r.price.formatted} gems'
                : 'Solo · ${r.price.formatted} gems · ${(r.price - balance).formatted} to go',
            onTap: () => showRewardSheet(context, reward: r),
            redeem: balance >= r.price
                ? _Redeem(
                    name: r.name,
                    busy: _redeeming == r.id,
                    onPressed: _redeeming != null ? null : () => _redeem(r, balance),
                  )
                : null,
          ),
        for (final r in list.partnerTreats(userId))
          _RewardRow(
            key: ValueKey(r.id),
            icon: Icons.person_outline_rounded,
            iconColor: kInkSecondary,
            name: r.name,
            detail: "${r.ownerName}'s · ${r.price.formatted} gems",
          ),
        for (final r in [...list.mineOpen(userId), ...list.treatsWaiting(userId)])
          _RewardRow(
            key: ValueKey(r.id),
            icon: r.declined ? Icons.block_rounded : Icons.hourglass_top_rounded,
            iconColor: r.declined ? kDangerText : kInkSecondary,
            name: r.name,
            detail:
                '${r.isTreat ? 'Solo' : 'Shared'} · ${r.price.formatted} gems · '
                '${r.declined ? 'declined' : 'waiting for ${partner ?? 'an answer'}'}',
            onTap: () => showRewardSheet(context, reward: r),
          ),
      ],
    ];
    final earned = list == null ? const <_Earned>[] : _earned(list, focus, userId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: const Text('Rewards', style: AppText.headline)),
        const SizedBox(height: 4),
        const Text(
          'Shared rewards come out of the bank you both fill, solo ones out of your own gems.',
          style: AppText.caption,
        ),
        const SizedBox(height: 10),
        if (list != null && list.balances.isNotEmpty) ...[
          _Balances(list: list, userId: userId, users: widget.board.users),
          const SizedBox(height: kCardGap),
        ],
        if (focus != null || rows.isEmpty) ...[
          RewardCard(
            reward: focus,
            people: people,
            claiming: widget.claiming,
            error: widget.claimError,
            onAdd: () => showRewardSheet(context),
            onClaim: () => widget.onClaim(focus!),
          ),
        ],
        if (rows.isNotEmpty) ...[
          if (focus != null) const SizedBox(height: kCardGap),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in rows) ...[row, const _Rule()],
                _AddRow(onTap: () => showRewardSheet(context)),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: AppText.label.copyWith(
                        color: kDangerText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (earned.isNotEmpty) ...[
          const SizedBox(height: 28),
          Semantics(header: true, child: const Text('Rewards earned', style: AppText.headline)),
          const SizedBox(height: 10),
          _EarnedList(items: earned.take(5).toList()),
        ],
      ],
    );
  }
}

/// One line of the earned list: a shared reward reached or enjoyed, or a solo one redeemed.
class _Earned {
  const _Earned({required this.name, required this.detail, required this.done, this.at});

  final String name;
  final String detail;
  final bool done;
  final DateTime? at;
}

List<_Earned> _earned(RewardList list, Reward? focus, int? userId) {
  String when(DateTime? at) => at == null ? '' : DateFormat.MMMd().format(at.toLocal());
  final items = <_Earned>[
    for (final r in list.history)
      if (r.id != focus?.id)
        () {
          final at = r.claimedAt ?? r.reachedAt;
          final verb = r.claimed ? 'enjoyed' : 'reached';
          return _Earned(
            name: r.name,
            detail: 'Shared · ${r.price.formatted} gems${at == null ? '' : ', $verb ${when(at)}'}',
            done: r.claimed,
            at: at,
          );
        }(),
    for (final t in list.treatHistory)
      _Earned(
        name: t.name,
        detail:
            '${t.userId == userId ? 'You' : t.userName} · ${t.price.formatted} gems'
            '${t.redeemedAt == null ? '' : ', ${when(t.redeemedAt)}'}',
        done: true,
        at: t.redeemedAt,
      ),
  ];
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  return items..sort((a, b) => (b.at ?? epoch).compareTo(a.at ?? epoch));
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => const Divider(height: 2, thickness: 2, color: kBorder);
}

/// Each person's own gems and the bank they add up to, mine first.
class _Balances extends StatelessWidget {
  const _Balances({required this.list, required this.userId, required this.users});

  final RewardList list;
  final int? userId;
  final List<BoardUser> users;

  @override
  Widget build(BuildContext context) {
    final mine = list.balanceOf(userId);
    final theirs = list.balances.where((b) => b.userId != userId).firstOrNull;
    Color dot(GemBalance? b) =>
        accentById(users.where((u) => u.id == b?.userId).firstOrNull?.color).fill;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Figure(label: 'Your gems', value: mine?.balance ?? 0, dot: dot(mine)),
          ),
          if (theirs != null)
            Expanded(
              child: _Figure(
                label: "${theirs.name}'s gems",
                value: theirs.balance,
                dot: dot(theirs),
              ),
            ),
          Expanded(
            child: _Figure(label: 'Shared bank', value: list.bank),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.dot});

  final String label;
  final int value;
  final Color? dot;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (dot != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(value.formatted, style: AppText.tabular(AppText.title)),
      ],
    ),
  );
}

class _Redeem extends StatelessWidget {
  const _Redeem({required this.name, required this.busy, required this.onPressed});

  final String name;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Redeem $name',
    child: SizedBox(
      width: 112,
      child: ChunkyButton(label: 'Redeem', busy: busy, onPressed: onPressed),
    ),
  );
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.detail,
    this.onTap,
    this.redeem,
  });

  final IconData icon;
  final Color iconColor;
  final String name;
  final String detail;

  /// Opens the reward; null for my partner's solo rewards, which are theirs to change.
  final VoidCallback? onTap;
  final Widget? redeem;

  @override
  Widget build(BuildContext context) {
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.tabular(AppText.caption),
                  ),
                ],
              ),
            ),
            if (onTap != null && redeem == null)
              const Icon(Icons.chevron_right_rounded, size: 22, color: kInkSecondary),
          ],
        ),
      ),
    );
    final tap = onTap;
    final row = tap == null
        ? MergeSemantics(child: body)
        : Semantics(
            button: true,
            label: '$name, $detail',
            excludeSemantics: true,
            onTap: tap,
            child: Pressable(scale: 0.99, onTap: tap, child: body),
          );
    if (redeem == null) return row;
    return Row(
      children: [
        Expanded(child: row),
        const SizedBox(width: 12),
        redeem!,
      ],
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Add a reward',
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      scale: 0.99,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 22, color: context.accentLip),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Add a reward',
                style: AppText.label.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.accentLip,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EarnedList extends StatelessWidget {
  const _EarnedList({required this.items});

  final List<_Earned> items;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Column(
      children: [
        for (final (i, e) in items.indexed) ...[
          if (i > 0) const _Rule(),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Semantics(
              container: true,
              label: '${e.name}, ${e.detail}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      e.done ? Icons.check_circle_rounded : Icons.emoji_events_rounded,
                      size: 22,
                      color: e.done ? kSuccess : kFlame,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(e.detail, style: AppText.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
