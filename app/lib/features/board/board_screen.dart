import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/board.dart';
import '../../state/clock.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/dashed_border.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/skeletons.dart';

/// A day counts for the streak at this percent, the same line Today draws on the ring.
const _kCountedPercent = 70;

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
        errorTitle: 'Could not load the board',
        onRetry: notifier.refresh,
        builder: (context, board, offline) => RefreshIndicator(
          color: context.accent,
          backgroundColor: kBgSurface,
          onRefresh: notifier.refresh,
          child: _BoardBody(board: board),
        ),
      ),
    );
  }
}

class _BoardBody extends ConsumerWidget {
  const _BoardBody({required this.board});

  final Board board;

  bool get _dayOne => board.users.every((u) => u.today.points == 0 && u.week == 0 && u.season == 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final users = board.users;
    final ends = board.season.endsOn;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
      children: [
        const Text(
          'Board',
          style: TextStyle(color: kFgPrimary, fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          ends == null
              ? board.season.name
              : '${board.season.name} - ends ${DateFormat.MMMd().format(parseLocalDate(ends))}',
          style: const TextStyle(color: kFgMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (users.isNotEmpty)
                Expanded(
                  child: _UserColumn(user: users[0], now: now),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: users.length > 1
                    ? _UserColumn(user: users[1], now: now)
                    : const _WaitingColumn(),
              ),
            ],
          ),
        ),
        if (_dayOne) ...[
          const SizedBox(height: 20),
          const Center(
            child: Text('Nobody has moved yet.', style: TextStyle(color: kFgMuted, fontSize: 13)),
          ),
        ],
      ],
    );
  }
}

class _UserColumn extends StatelessWidget {
  const _UserColumn({required this.user, required this.now});

  final BoardUser user;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(extensions: [accentById(user.color)]),
      child: Builder(
        builder: (context) {
          final rests = user.last7.where((d) => d.rest).length;
          return OnyxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: context.accent,
                      child: Text(
                        user.name.isEmpty ? '?' : user.name.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: context.onAccent,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kFgPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _Caption('Today'),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    user.today.points.formatted,
                    style: TextStyle(
                      color: context.accent,
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
                Text(
                  '${user.today.percent}%${user.today.counted ? ' - counted' : ''}',
                  style: const TextStyle(
                    color: kFgSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.local_fire_department_outlined, size: 16, color: context.accent),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${user.streak}-day streak',
                        style: const TextStyle(
                          color: kFgPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (rests > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 20),
                    child: Text(
                      rests == 1 ? '1 rest day' : '$rests rest days',
                      style: const TextStyle(color: kFgMuted, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 14),
                _StatRow(label: 'Week', value: user.week),
                const SizedBox(height: 6),
                _StatRow(label: 'Season', value: user.season),
                const SizedBox(height: 16),
                _Strip(days: user.last7),
                const SizedBox(height: 14),
                Text(
                  user.syncedAt == null
                      ? 'Health not synced'
                      : 'synced ${relativeTime(user.syncedAt!, now)}',
                  style: const TextStyle(color: kFgMuted, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: kFgMuted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(color: kFgSecondary, fontSize: 13)),
      ),
      Text(
        value.formatted,
        style: const TextStyle(color: kFgPrimary, fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

/// Seven dots, oldest first: filled for a counted day, hollow for a rest day, dim for a miss.
class _Strip extends StatelessWidget {
  const _Strip({required this.days});

  final List<DayMark> days;

  @override
  Widget build(BuildContext context) {
    final shown = days.length > 7 ? days.sublist(days.length - 7) : days;
    final slots = <DayMark?>[for (var i = shown.length; i < 7; i++) null, ...shown];
    return Semantics(
      label:
          'Last 7 days: ${shown.where((d) => !d.rest && d.percent >= _kCountedPercent).length} '
          'counted, ${shown.where((d) => d.rest).length} rest',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final day in slots)
            Column(
              children: [
                _Dot(day: day),
                const SizedBox(height: 4),
                Text(
                  day == null ? '' : weekdayShort(day.date).substring(0, 1),
                  style: const TextStyle(color: kFgMuted, fontSize: 10, height: 1),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.day});

  final DayMark? day;

  @override
  Widget build(BuildContext context) {
    final mark = day;
    final Color? fill;
    final Border? border;
    if (mark == null) {
      fill = kBgSurfaceHover.withValues(alpha: 0.5);
      border = null;
    } else if (mark.rest) {
      fill = null;
      border = Border.all(color: context.accent, width: 1.5);
    } else if (mark.percent >= _kCountedPercent) {
      fill = context.accent;
      border = null;
    } else {
      fill = kBgSurfaceHover;
      border = Border.all(color: kBorder);
    }
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fill, border: border),
    );
  }
}

class _WaitingColumn extends StatelessWidget {
  const _WaitingColumn();

  @override
  Widget build(BuildContext context) {
    return DashedBorder(
      color: kFgMuted.withValues(alpha: 0.6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showAppSheet<void>(context, builder: (_) => const _HowTheyJoinSheet()),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add_alt_outlined, size: 28, color: kFgMuted),
                SizedBox(height: 12),
                Text(
                  'Waiting for your partner',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kFgSecondary, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6),
                Text(
                  'How they join',
                  style: TextStyle(
                    color: kFgMuted,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HowTheyJoinSheet extends StatelessWidget {
  const _HowTheyJoinSheet();

  static const _steps = [
    'Send them the TestFlight invite for New Me.',
    'They install it and open the app.',
    'Create a pairing code in Me and give it to them. They enter it when New Me asks.',
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How they join',
            style: TextStyle(color: kFgPrimary, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: context.accentLight, shape: BoxShape.circle),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: context.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _steps[i],
                        style: const TextStyle(color: kFgSecondary, fontSize: 14, height: 1.45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
