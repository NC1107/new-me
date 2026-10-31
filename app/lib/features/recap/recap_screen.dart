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
import '../../util/people.dart';
import '../../widgets/app_card.dart';
import '../../widgets/avatar.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import '../together/challenge_card.dart';
import 'recap_logic.dart';

String _day(String date) => DateFormat.MMMd().format(parseLocalDate(date));

/// The week in review, in the order a person reads it: the couple's headline, what went well,
/// what to work on, then each person's own numbers, listed one after the other and never ranked.
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
            SkeletonBlock(height: 150, radius: kRadiusCard),
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
    final quiet = statsEmpty(r.pair.thisWeek);
    // The headline card already says how the points moved, so the first row is left out here.
    final gains = r.complete
        ? recapGains(recapRows(r.pair.thisWeek, r.pair.previous, pair: true).skip(1))
        : const <RecapRow>[];
    final challenge = r.challenge;
    final challengeDone = challenge?.completed ?? false;
    final mine = r.people.where((p) => p.userId == me).firstOrNull;
    final partner = r.people.where((p) => p.userId != me).firstOrNull;
    // A running week's suggestion is only a pep line, which says nothing the headline does not.
    final suggestions = [
      if (r.complete && mine != null && mine.suggestion.isNotEmpty) ('For you', mine.suggestion),
      if (r.complete &&
          partner != null &&
          partner.suggestion.isNotEmpty &&
          partner.suggestion != mine?.suggestion)
        ('For ${partner.name}', partner.suggestion),
    ];
    final openChallenge = challenge != null && !challengeDone;
    return [
      if (quiet) _QuietWeek(complete: r.complete) else _HeadlineCard(recap: r),
      if (gains.isNotEmpty || challengeDone) ...[
        const _Heading('What went well'),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              for (final row in gains) _StatLine(row: row),
              if (challenge != null && challengeDone) _ChallengeLine(challenge: challenge),
            ],
          ),
        ),
        const SizedBox(height: kCardGap),
      ],
      if (suggestions.isNotEmpty || openChallenge) ...[
        _Heading(r.complete ? 'To work on' : 'Challenge'),
        const SizedBox(height: 10),
        for (final (who, text) in suggestions) ...[
          _SuggestionCard(who: who, text: text),
          const SizedBox(height: kCardGap),
        ],
        if (challenge != null && openChallenge) ...[
          _OpenChallenge(challenge: challenge, complete: r.complete),
          const SizedBox(height: kCardGap),
        ],
      ],
      if (!quiet && r.people.isNotEmpty) ...[
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

/// A section title. Sections sit 24 apart from the card above, and cards 12 apart from each
/// other, so the headings are what group the page.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(header: true, child: Text(text, style: AppText.headline)),
  );
}

/// The couple's week in one glance: the points, how they moved, and the best day.
class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.recap});

  final Recap recap;

  @override
  Widget build(BuildContext context) {
    final points = recap.pair.thisWeek.points;
    final delta = recapDelta(recap);
    final first = recap.complete && statsEmpty(recap.pair.previous);
    final best = recap.pair.bestDay;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.favorite_rounded, size: 20, color: kFlame),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: const Text('Together', style: AppText.headline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              container: true,
              label: '${points.formatted} ${points == 1 ? 'point' : 'points'}',
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(child: Text(points.formatted, style: AppText.tabular(AppText.display))),
                  const SizedBox(width: 8),
                  Text(
                    points == 1 ? 'point' : 'points',
                    style: AppText.body.copyWith(color: kInkSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            if (!recap.complete) const Text('This week is still running.', style: AppText.caption),
            if (delta != null)
              Text(delta, style: AppText.label.copyWith(color: kInkSecondary))
            else if (first)
              const Text(
                'Your first week, so there is nothing to compare it with.',
                style: AppText.label,
              ),
            if (best != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: kBorderWidth, color: kBorder),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.star_rounded, size: 20, color: kFlame),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Best day ${DateFormat.MMMEd().format(parseLocalDate(best.date))}',
                      style: AppText.label.copyWith(color: kInkSecondary),
                    ),
                  ),
                  Text(
                    '${best.points.formatted} points',
                    style: AppText.tabular(AppText.label.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A week with nothing recorded: say so plainly instead of a card of zeros.
class _QuietWeek extends StatelessWidget {
  const _QuietWeek({required this.complete});

  final bool complete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppCard(
      child: Column(
        children: [
          const Mascot(size: 88, state: MascotState.sleepy),
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text(
              complete ? 'A quiet week' : 'The week has only just begun',
              style: AppText.headline,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            complete
                ? 'Nothing was logged this week, so there is nothing to read or compare.'
                : 'Your numbers show up here as you log them.',
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: kInkSecondary),
          ),
        ],
      ),
    ),
  );
}

String _spoken(RecapRow row) => row.change == null
    ? '${row.label} ${row.value}'
    : '${row.label} ${row.value}, ${row.change == 'Same' ? 'same as' : '${row.change} against'} the week before';

/// One number and how it moved, on a line: icon, label, value, change.
class _StatLine extends StatelessWidget {
  const _StatLine({required this.row});

  final RecapRow row;

  @override
  Widget build(BuildContext context) => _Line(
    icon: row.icon,
    iconColor: kInkSecondary,
    label: row.label,
    value: row.value,
    trailing: row.change,
    spoken: _spoken(row),
  );
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.spoken,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? trailing;
  final String spoken;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: spoken,
    excludeSemantics: true,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      // The numbers take what they need up to this share of the line, so at large text sizes they
      // wrap instead of pushing the label out of the card.
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: AppText.label.copyWith(color: kInkSecondary)),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.65),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: AppText.tabular(AppText.body.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 72),
                      child: Text(
                        trailing ?? '',
                        textAlign: TextAlign.end,
                        style: AppText.tabular(AppText.caption),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChallengeLine extends StatelessWidget {
  const _ChallengeLine({required this.challenge});

  final RecapChallenge challenge;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Challenge done, ${challenge.title}, plus $kChallengeBonus points each',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, size: 20, color: kSuccess),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Challenge done', style: AppText.caption),
                Text(challenge.title, style: AppText.label),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('+$kChallengeBonus each', style: AppText.tabular(AppText.caption)),
        ],
      ),
    ),
  );
}

class _OpenChallenge extends StatelessWidget {
  const _OpenChallenge({required this.challenge, required this.complete});

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
          Icon(challengeIcon(c.kind), size: 24, color: kInkSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.missed
                      ? 'Challenge: missed, nothing lost'
                      : complete
                      ? 'Challenge: next time'
                      : 'Challenge so far',
                  style: AppText.caption,
                ),
                Text(c.title, style: AppText.body.copyWith(fontWeight: FontWeight.w800)),
                Text(progress, style: AppText.label.copyWith(color: kInkSecondary)),
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

/// One person's week: a name and points on top, the other numbers in a three-column grid.
class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.complete});

  final RecapPerson person;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final palette = accentById(person.color);
    final nothing = statsEmpty(person.thisWeek);
    final firstWeek = complete && !nothing && statsEmpty(person.previous);
    final rows = recapRows(person.thisWeek, person.previous, complete: complete);
    final points = rows.first;
    final best = person.bestDay;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                Avatar(name: person.name, palette: palette, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(person.name, style: AppText.headline.copyWith(fontSize: 18)),
                  ),
                ),
                if (!nothing)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
                    child: Semantics(
                      container: true,
                      label: _spoken(points),
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${points.value} points',
                            textAlign: TextAlign.end,
                            style: AppText.tabular(
                              AppText.body.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (points.change != null)
                            Text(points.change!, style: AppText.tabular(AppText.caption)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (nothing) ...[
            const SizedBox(height: 8),
            const Text('Nothing was logged this week.', style: AppText.caption),
          ] else ...[
            const SizedBox(height: 12),
            _Grid(
              tiles: [
                for (final row in rows.skip(1))
                  _Tile(
                    label: row.label,
                    value: row.value,
                    change: row.change,
                    spoken: _spoken(row),
                  ),
                if (best != null)
                  _Tile(
                    label: 'Best day',
                    value: DateFormat.E().format(parseLocalDate(best.date)),
                    change: '${best.points.formatted} points',
                    spoken:
                        'Best day ${DateFormat.EEEE().format(parseLocalDate(best.date))}, '
                        '${best.points.formatted} points',
                  ),
              ],
            ),
            if (firstWeek) ...[
              const SizedBox(height: 8),
              const Text('A first week, so nothing to compare yet.', style: AppText.caption),
            ],
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.spoken, this.change});

  final String label;
  final String value;
  final String? change;
  final String spoken;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: spoken,
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppText.tabular(AppText.body.copyWith(fontWeight: FontWeight.w800))),
        Text(label, style: AppText.caption),
        if (change != null) Text(change!, style: AppText.tabular(AppText.caption)),
      ],
    ),
  );
}

/// Three equal columns that wrap, so a row of tiles lines up with the one above it.
class _Grid extends StatelessWidget {
  const _Grid({required this.tiles});

  final List<Widget> tiles;

  static const _columns = 3;
  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = (box.maxWidth - _gap * (_columns - 1)) / _columns;
      return Wrap(
        spacing: _gap,
        runSpacing: 10,
        children: [for (final t in tiles) SizedBox(width: width, child: t)],
      );
    },
  );
}
