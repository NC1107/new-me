import 'package:flutter/material.dart';

import 'guided_page.dart';
import 'mobility_session.dart';

/// Mobility 10's words and holds on the shared runner.
final mobilityRoutine = GuidedRoutine(
  title: 'Mobility',
  stepNoun: 'stretch',
  stepNounPlural: 'stretches',
  activity: 'stretching',
  doneNoun: 'mobility',
  fallbackIntro: 'Guided stretching, one stretch at a time.',
  introFor: (steps, minutes) => '$steps stretches, about $minutes minutes, timed for you.',
  notes: const [kMobilityOrderNote, kMobilityCitation],
  emptyCopy: 'This server has no stretches yet. Update the server to use Mobility.',
  footnote: 'Stretch to a mild pull, never pain. Counts toward yoga.',
  build: buildMobilityHolds,
);

/// Mobility 10: a guided stretching routine on the shared guided runner.
class MobilityPage extends StatelessWidget {
  const MobilityPage({super.key, this.now = DateTime.now});

  /// The wall clock, read only to measure time spent in the background.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) => GuidedPage(routine: mobilityRoutine, now: now);
}
