import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
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
import 'reward_sheet.dart';
import 'together_bar.dart';

String _newRequestId() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// The Treats half of Us: both people's own gem balances, my treats with a Redeem button once
/// my own gems cover one, my price proposals still waiting, my partner's treats read-only, and
/// the history of what was redeemed.
class TreatsSection extends ConsumerStatefulWidget {
  const TreatsSection({super.key, required this.users});

  final List<BoardUser> users;

  @override
  ConsumerState<TreatsSection> createState() => _TreatsSectionState();
}

class _TreatsSectionState extends ConsumerState<TreatsSection> {
  // One id per treat for as long as its redemption is unanswered, so a retry after a lost
  // response is the same request to the server.
  final _requestIds = <int, String>{};
  int? _redeeming;
  String? _error;

  Future<void> _redeem(Reward treat, int balance) async {
    if (_redeeming != null) return;
    final ok = await confirmDialog(
      context,
      title: 'Redeem ${treat.name}?',
      message:
          '${treat.price.formatted} gems come out of your own ${balance.formatted}. '
          'You will have ${(balance - treat.price).formatted} left.',
      confirmLabel: 'Redeem',
    );
    if (!ok || !mounted || _redeeming != null) return;
    unawaited(HapticFeedback.mediumImpact());
    final requestId = _requestIds.putIfAbsent(treat.id, _newRequestId);
    setState(() {
      _redeeming = treat.id;
      _error = null;
    });
    try {
      await ref.read(rewardsProvider.notifier).redeem(treat.id, requestId: requestId);
      _requestIds.remove(treat.id);
    } on ApiException catch (e) {
      _requestIds.remove(treat.id);
      if (mounted) setState(() => _error = errorCopy(e));
    } on Object {
      if (mounted) setState(() => _error = 'Could not save that. Try again.');
    }
    if (mounted) setState(() => _redeeming = null);
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final list = ref.watch(rewardsProvider).value;
    if (list == null) return const SizedBox.shrink();
    final mine = list.balanceOf(userId);
    final balance = mine?.balance ?? 0;
    final myTreats = list.myTreats(userId);
    final waiting = list.treatsWaiting(userId);
    final theirs = list.partnerTreats(userId);
    final partnerBalance = list.balances.where((b) => b.userId != userId).firstOrNull;
    // Once the cheapest treat is covered its row carries the Redeem button, so the progress
    // summary has nothing left to say.
    final cheapest = myTreats.isEmpty || balance >= myTreats.first.price ? null : myTreats.first;
    final palette = accentById(widget.users.where((u) => u.id == userId).firstOrNull?.color);
    final rows = <Widget>[
      for (final t in myTreats)
        _TreatRow(
          key: ValueKey(t.id),
          treat: t,
          balance: balance,
          busy: _redeeming == t.id,
          locked: _redeeming != null,
          onRedeem: () => _redeem(t, balance),
          onOpen: () => showRewardSheet(context, reward: t),
        ),
      for (final t in waiting)
        _WaitingRow(
          key: ValueKey(t.id),
          treat: t,
          partner: partnerBalance?.name,
          onTap: () => showRewardSheet(context, reward: t),
        ),
      _AddTreatRow(onTap: () => showRewardSheet(context, treat: true)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Balances(list: list, userId: userId, users: widget.users),
        const SizedBox(height: kCardGap),
        AppCard(
          padding: EdgeInsets.fromLTRB(16, cheapest == null ? 4 : 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cheapest != null) ...[
                _Cheapest(treat: cheapest, balance: balance, palette: palette),
                const SizedBox(height: 6),
              ],
              for (final (i, row) in rows.indexed) ...[
                if (i > 0 || cheapest != null) const _Rule(),
                row,
              ],
              if (_error != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (theirs.isNotEmpty && partnerBalance != null) ...[
          const SizedBox(height: kCardGap),
          _PartnerTreats(
            name: partnerBalance.name,
            treats: theirs,
            balance: partnerBalance.balance,
          ),
        ],
        if (list.treatHistory.isNotEmpty) ...[
          const SizedBox(height: 28),
          Semantics(header: true, child: const Text('Treats redeemed', style: AppText.headline)),
          const SizedBox(height: 10),
          _TreatHistory(items: list.treatHistory.take(5).toList(), myId: userId),
        ],
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => const Divider(height: 2, thickness: 2, color: kBorder);
}

/// Both balances side by side, mine first, plus the bank they add up to.
class _Balances extends StatelessWidget {
  const _Balances({required this.list, required this.userId, required this.users});

  final RewardList list;
  final int? userId;
  final List<BoardUser> users;

  @override
  Widget build(BuildContext context) {
    final mine = list.balanceOf(userId);
    final theirs = list.balances.where((b) => b.userId != userId).firstOrNull;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Balance(label: 'Your gems', balance: mine, users: users),
              ),
              if (theirs != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _Balance(label: "${theirs.name}'s gems", balance: theirs, users: users),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Treats come out of your own gems. Shared rewards come out of the bank, '
            '${list.bank.formatted} gems in all.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.label, required this.balance, required this.users});

  final String label;
  final GemBalance? balance;
  final List<BoardUser> users;

  @override
  Widget build(BuildContext context) {
    final palette = accentById(users.where((u) => u.id == balance?.userId).firstOrNull?.color);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: palette.fill, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
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
          Text(
            (balance?.balance ?? 0).formatted,
            style: AppText.tabular(AppText.title.copyWith(color: palette.lip)),
          ),
        ],
      ),
    );
  }
}

/// How far my own gems are toward my cheapest treat.
class _Cheapest extends StatelessWidget {
  const _Cheapest({required this.treat, required this.balance, required this.palette});

  final Reward treat;
  final int balance;
  final AccentPalette palette;

  @override
  Widget build(BuildContext context) {
    final ready = balance >= treat.price;
    final progress = balance.clamp(0, treat.price);
    final left = treat.price - progress;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ready ? '${treat.name} is within reach' : 'Next up: ${treat.name}',
            style: AppText.label.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          TogetherBar(value: progress / treat.price, from: palette.fill, to: palette.fill),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              Text(
                '${progress.formatted} of ${treat.price.formatted} gems',
                style: AppText.tabular(AppText.label.copyWith(fontWeight: FontWeight.w800)),
              ),
              Text(ready ? 'Ready to redeem' : '${left.formatted} to go', style: AppText.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _TreatRow extends StatelessWidget {
  const _TreatRow({
    super.key,
    required this.treat,
    required this.balance,
    required this.busy,
    required this.locked,
    required this.onRedeem,
    required this.onOpen,
  });

  final Reward treat;
  final int balance;
  final bool busy;
  final bool locked;
  final VoidCallback onRedeem;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final affordable = balance >= treat.price;
    final left = treat.price - balance;
    final detail = affordable
        ? '${treat.price.formatted} gems'
        : '${treat.price.formatted} gems · ${left.formatted} to go';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: '${treat.name}, $detail',
                excludeSemantics: true,
                onTap: onOpen,
                child: Pressable(
                  scale: 0.99,
                  onTap: onOpen,
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_cafe_rounded,
                        size: 22,
                        color: affordable ? context.accentLip : kInkSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              treat.name,
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
                    ],
                  ),
                ),
              ),
            ),
            if (affordable) ...[
              const SizedBox(width: 12),
              Semantics(
                container: true,
                label: 'Redeem ${treat.name}',
                child: SizedBox(
                  width: 120,
                  child: ChunkyButton(
                    label: 'Redeem',
                    busy: busy,
                    onPressed: locked ? null : onRedeem,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow({super.key, required this.treat, required this.partner, required this.onTap});

  final Reward treat;
  final String? partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = '${treat.price.formatted} gems';
    final (icon, color, detail) = treat.declined
        ? (Icons.block_rounded, kDangerText, '$price · declined')
        : (
            Icons.hourglass_top_rounded,
            kInkSecondary,
            '$price · waiting for ${partner ?? 'an answer'}',
          );
    return Semantics(
      button: true,
      label: '${treat.name}, $detail',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        scale: 0.99,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      treat.name,
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

class _AddTreatRow extends StatelessWidget {
  const _AddTreatRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Add a treat',
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
                'Add a treat',
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

/// My partner's agreed treats. They are theirs to redeem, so there is nothing to tap here.
class _PartnerTreats extends StatelessWidget {
  const _PartnerTreats({required this.name, required this.treats, required this.balance});

  final String name;
  final List<Reward> treats;
  final int balance;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text("$name's treats", style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        for (final (i, t) in treats.indexed) ...[
          if (i > 0) const _Rule(),
          MergeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${t.price.formatted} gems',
                    style: AppText.tabular(AppText.caption.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _TreatHistory extends StatelessWidget {
  const _TreatHistory({required this.items, required this.myId});

  final List<TreatRedemption> items;
  final int? myId;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Column(
      children: [
        for (final (i, r) in items.indexed) ...[
          if (i > 0) const _Rule(),
          Builder(
            builder: (context) {
              final at = r.redeemedAt;
              final who = r.userId == myId ? 'You' : r.userName;
              final when = at == null ? '' : ', ${DateFormat.MMMd().format(at.toLocal())}';
              final detail = '$who · ${r.price.formatted} gems$when';
              return ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Semantics(
                  container: true,
                  label: '${r.name}, $detail',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 22, color: kSuccess),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(detail, style: AppText.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    ),
  );
}
