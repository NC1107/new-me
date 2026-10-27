import '../../api/models.dart';

/// The sentence under a milestone's title. The server sends only the title, so the app words
/// the rest from the kind.
String milestoneBody(Milestone m) => switch (m.kind) {
  'streak' => '${m.value} days in a row. That is real consistency.',
  'shared_streak' => 'You have both counted for ${m.value} days running.',
  _ => 'A first, and now it is yours.',
};

/// The big mark of a celebration: the streak length, or a star for a first.
String? milestoneNumber(Milestone m) =>
    m.kind == 'streak' || m.kind == 'shared_streak' ? '${m.value}' : null;

/// Who it belongs to, for the small label above the title.
String milestoneOwner(Milestone m) => m.shared ? 'Together' : 'You';
