/// The exercise of the push-ups quest until the person picks another.
const kDefaultRepsExercise = 'push_up';

/// How the daily-reps exercises read in running text. The server sends the same names; this table
/// keeps a quest card readable before, or without, the setup page's own fetch.
const _nouns = {
  'knee_push_up': ('knee push-up', 'knee push-ups'),
  'incline_push_up': ('incline push-up', 'incline push-ups'),
  'push_up': ('push-up', 'push-ups'),
  'air_squat': ('squat', 'squats'),
  'lunge': ('lunge', 'lunges'),
  'glute_bridge': ('glute bridge', 'glute bridges'),
  'crunch': ('crunch', 'crunches'),
  'pull_up': ('pull-up', 'pull-ups'),
};

/// "squats", or "squat" for exactly one. An unknown or missing exercise reads as push-ups.
String repsNoun(String? exercise, num n) {
  final (one, many) = _nouns[exercise] ?? _nouns[kDefaultRepsExercise]!;
  return n == 1 ? one : many;
}

/// "Squats": the quest's title.
String repsTitle(String? exercise) {
  final plural = repsNoun(exercise, 2);
  return '${plural[0].toUpperCase()}${plural.substring(1)}';
}
