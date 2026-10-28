import '../../util/people.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/right_now.dart';
import '../../state/session.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/avatar.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import '../together/challenge_card.dart';
import 'recap_logic.dart';

String _day(String date) => DateFormat.MMMd().format(parseLocalDate(date));

/// The week in review. The couple comes first; each person's own numbers follow, side by side
/// only in the sense of being listed one after the other, never ranked.
class RecapScreen extends ConsumerWidget {
  const RecapScreen({super.key, this.week});

  /// An ISO week like `2026-W44`; null asks for the server's default week.
  final String? week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = ref.watch(recapProvider(week));
    final me = ref.watch(sessionProvider.select((s) => s.session?.userId));
    return PageScaffold(
      title: 'Weekly recap',
      subtitle: recap.value == null ? null : recapRange(recap.value!, _day),
      children: [
        ...recap.when(
          data: (r) => _content(r, me),
          loading: () => const [
            SkeletonBlock(height: 170, radius: kRadiusCard),
            SizedBox(height: kCardGap),
            SkeletonBlock(height: 110, radius: kRadiusCard),
          ],
          error: (e, _) => [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(errorCopy(e), style: AppText.body),
                  const SizedBox(height: 12),
                  ChunkyButton.secondary(
                    label: 'Try again',
                    onPressed: () => ref.invalidate(recapProvider(week)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _content(Recap r, int? me) {
    final mine = r.people.where((p) => p.userId == me).firstOrNull;
    final partner = r.people.where((p) => p.userId != me).firstOrNull;
    final suggestions = [
      if (mine != null && mine.suggestion.isNotEmpty) ('For you', mine.suggestion),
      if (partner != null &&
          partner.suggestion.isNotEmpty &&
          partner.suggestion != mine?.suggestion)
        ('For ${partner.name}', partner.suggestion),
    ];
    return [
      if (!r.complete)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('This week is still running.', style: AppText.caption),
        ),
      _TogetherCard(recap: r),
      if (r.pair.bestDay case final best?) ...[
        const SizedBox(height: kCardGap),
        _BestDayCard(best: best),
      ],
      if (r.challenge case final challenge?) ...[
        const SizedBox(height: kCardGap),
        _ChallengeResult(challenge: challenge, complete: r.complete),
      ],
      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: 24),
        const _Heading('For next week'),
        const SizedBox(height: 10),
        for (final (who, text) in suggestions) ...[
          _SuggestionCard(who: who, text: text),
          const SizedBox(height: kCardGap),
        ],
      ],
      if (r.people.isNotEmpty) ...[
        const SizedBox(height: 12),
        const _Heading('Each of you'),
        const SizedBox(height: 10),
        for (final p in meFirst(r.people, me, (p) => p.userId)) ...[
          _PersonCard(person: p, complete: r.complete),
          const SizedBox(height: kCardGap),
        ],
      ],
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text, style: AppText.headline));
}

class _TogetherCard extends StatelessWidget {
  const _TogetherCard({required this.recap});

  final Recap recap;

  @override
  Widget build(BuildContext context) {
    final pair = recap.pair;
    final rows = recapRows(pair.thisWeek, pair.previous, complete: recap.complete);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded, size: 22, color: kFlame),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: const Text('Together', style: AppText.headline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(recapHeadline(recap), style: AppText.body.copyWith(color: kInkSecondary)),
          const SizedBox(height: 10),
          for (final row in rows) _StatLine(row: row),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.row});

  final RecapRow row;

  @override
  Widget build(BuildContext context) {
    final changeIcon = switch (row.direction) {
      1 => Icons.arrow_upward_rounded,
      -1 => Icons.arrow_downward_rounded,
      _ => Icons.remove_rounded,
    };
    final spoken = row.before != null
        ? '${row.label} ${row.value}, last week ${row.before}'
        : row.change == null
        ? '${row.label} ${row.value}'
        : '${row.label} ${row.value}, ${row.change == 'Same' ? 'same as' : '${row.change} against'} the week before';
    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Icon(row.icon, size: 20, color: kInkSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(row.label, style: AppText.label.copyWith(color: kInkSecondary)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                children: [
                  Text(
                    row.value,
                    style: AppText.tabular(AppText.body.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  if (row.change != null)
                    Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(changeIcon, size: 14, color: kInkSecondary),
                          ),
                          TextSpan(text: row.change),
                        ],
                      ),
                      style: AppText.tabular(AppText.caption),
                    )
                  else if (row.before != null)
                    Text('last week ${row.before}', style: AppText.tabular(AppText.caption)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BestDayCard extends StatelessWidget {
  const _BestDayCard({required this.best});

  final RecapBestDay best;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.MMMEd().format(parseLocalDate(best.date));
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.star_rounded, size: 26, color: kFlame),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Best day together', style: AppText.caption),
                Text(
                  '$date, ${best.points.formatted} points',
                  style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallengeResult extends StatelessWidget {
  const _ChallengeResult({required this.challenge, required this.complete});

  final RecapChallenge challenge;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final unit = challengeUnit(c.kind);
    final progress =
        '${c.progress.formatted} of ${c.target.formatted}${unit.isEmpty ? '' : ' $unit'}';
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            c.completed ? Icons.emoji_events_rounded : challengeIcon(c.kind),
            size: 26,
            color: c.completed ? kSuccess : kInkSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.completed
                      ? 'Challenge done'
                      : complete
                      ? 'Challenge: next time'
                      : 'Challenge so far',
                  style: AppText.caption,
                ),
                Text(c.title, style: AppText.body.copyWith(fontWeight: FontWeight.w800)),
                Text(
                  c.completed ? '$progress. +$kChallengeBonus points each' : progress,
                  style: AppText.label.copyWith(color: kInkSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.who, required this.text});

  final String who;
  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lightbulb_rounded, size: 24, color: kFlame),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(who, style: AppText.caption),
              Text(text, style: AppText.body),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.complete});

  final RecapPerson person;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final palette = accentById(person.color);
    final rows = recapRows(person.thisWeek, person.previous, complete: complete);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(name: person.name, palette: palette, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(person.name, style: AppText.headline.copyWith(fontSize: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final row in rows) _StatLine(row: row),
          if (person.bestDay case final best?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Best day ${DateFormat.E().format(parseLocalDate(best.date))}, ${best.points.formatted} points',
                style: AppText.caption,
              ),
            ),
        ],
      ),
    );
  }
}
