import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/board.dart';
import '../../state/clock.dart';
import '../../state/me.dart';
import '../../theme/accent.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/avatar.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import '../health/health_metrics.dart';
import '../me/pairing_page.dart';
import 'person_card.dart';
import 'week_chart.dart';

/// Us: the two of you side by side. A shared scoreboard, so nothing here ranks anyone.
class BoardScreen extends ConsumerWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(boardProvider.notifier);
    return SafeArea(
      bottom: false,
      child: CachedView<Board>(
        value: ref.watch(boardProvider),
        skeleton: const BoardSkeleton(),
        errorTitle: 'Could not load Us',
        onRetry: notifier.refresh,
        builder: (context, board, offline) => RefreshIndicator(
          color: context.accent,
          backgroundColor: kSurface,
          onRefresh: notifier.refresh,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
              child: _UsBody(board: board),
            ),
          ),
        ),
      ),
    );
  }
}

class _UsBody extends ConsumerWidget {
  const _UsBody({required this.board});

  final Board board;

  bool get _dayOne => board.users.every((u) => u.today.points == 0 && u.week == 0 && u.season == 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final users = board.users;
    final ends = board.season.endsOn;
    final isAdmin = ref.watch(meProvider.select((m) => m.value?.data.user.isAdmin)) ?? false;
    final paired = users.length > 1;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 96),
      children: [
        Semantics(header: true, child: const Text('Us', style: AppText.display)),
        Text(
          ends == null
              ? board.season.name
              : '${board.season.name} - ends ${DateFormat.MMMd().format(parseLocalDate(ends))}',
          style: AppText.caption,
        ),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (users.isNotEmpty)
                Expanded(
                  child: PersonCard(user: users[0], now: now),
                ),
              const SizedBox(width: kCardGap),
              Expanded(
                child: paired ? PersonCard(user: users[1], now: now) : const _WaitingCard(),
              ),
            ],
          ),
        ),
        if (paired) ...[
          const SizedBox(height: kCardGap),
          _Together(users: users),
        ] else ...[
          const SizedBox(height: kCardGap),
          _InviteCard(isAdmin: isAdmin),
        ],
        if (_dayOne) ...[
          const SizedBox(height: kCardGap),
          Center(
            child: Text(
              'Nobody has moved yet. A fresh start for both of you.',
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: kInkSecondary),
            ),
          ),
        ],
        const SizedBox(height: 28),
        const _SectionTitle('This week'),
        const SizedBox(height: 10),
        WeekChart(users: users),
        const SizedBox(height: 28),
        const _SectionTitle("Today's highlights"),
        const SizedBox(height: 10),
        _Highlights(users: users),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text, style: AppText.headline));
}

class _Together extends StatelessWidget {
  const _Together({required this.users});

  final List<BoardUser> users;

  @override
  Widget build(BuildContext context) {
    final points = users.fold<int>(0, (sum, u) => sum + u.week);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.favorite_rounded, size: 22, color: kFlame),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Together: ${points.formatted} points this week',
              style: AppText.label.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard();

  @override
  Widget build(BuildContext context) => AppCard(
    color: kSunken,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Mascot(size: 76, state: MascotState.sleepy, palette: null),
        const SizedBox(height: 10),
        Text(
          'Waiting for your partner',
          textAlign: TextAlign.center,
          style: AppText.label.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isAdmin
              ? 'Send them the TestFlight invite, then give them a pairing code. They enter it '
                    'when New Me asks.'
              : 'Your partner joins with a pairing code from whoever set up New Me.',
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
        if (isAdmin) ...[
          const SizedBox(height: 14),
          ChunkyButton(
            label: 'Create pairing code',
            icon: Icons.group_add_rounded,
            onPressed: () => pushPage(context, const PairingPage()),
          ),
        ],
      ],
    ),
  );
}

class _Highlights extends StatelessWidget {
  const _Highlights({required this.users});

  final List<BoardUser> users;

  static final _rows = [
    (key: 'steps', label: 'Steps', quest: 'steps', metric: 'steps'),
    (key: 'exercise', label: 'Exercise', quest: 'exercise', metric: 'exercise_minutes'),
    (key: 'sleep', label: 'Sleep', quest: 'sleep', metric: 'sleep_minutes'),
  ];

  static num? _value(BoardHighlights h, String key) => switch (key) {
    'steps' => h.steps,
    'exercise' => h.exerciseMinutes,
    _ => h.sleepMinutes,
  };

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final (i, row) in _rows.indexed) ...[
            if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: questPalette(row.quest).tint,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          questIcon(row.quest),
                          size: 18,
                          color: questPalette(row.quest).lip,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          row.label,
                          style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final (j, user) in users.indexed) ...[
                        if (j > 0) const SizedBox(width: kCardGap),
                        Expanded(
                          child: _HighlightValue(
                            user: user,
                            what: row.label,
                            text: _value(user.highlights, row.key) == null
                                ? null
                                : healthMetricSpec(row.metric)!
                                      .format(_value(user.highlights, row.key)!),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HighlightValue extends StatelessWidget {
  const _HighlightValue({required this.user, required this.what, required this.text});

  final BoardUser user;
  final String what;
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${user.name}, $what: ${text ?? 'no data yet'}',
      excludeSemantics: true,
      child: Row(
        children: [
          Avatar(name: user.name, palette: accentById(user.color), size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                text ?? '-',
                maxLines: 1,
                style: AppText.tabular(
                  AppText.body.copyWith(
                    fontWeight: FontWeight.w800,
                    color: text == null ? kInkMuted : kInk,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
