import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';

/// How each reaction looks. Material icons rather than emoji, so they follow the app's colours
/// and render the same everywhere.
extension CheerKindStyle on CheerKind {
  IconData get icon => switch (this) {
    CheerKind.clap => Icons.waving_hand_rounded,
    CheerKind.fire => Icons.local_fire_department_rounded,
    CheerKind.flex => Icons.fitness_center_rounded,
    CheerKind.heart => Icons.favorite_rounded,
  };

  String get label => switch (this) {
    CheerKind.clap => 'Clap',
    CheerKind.fire => 'Fire',
    CheerKind.flex => 'Flex',
    CheerKind.heart => 'Heart',
  };

  AccentPalette get palette => switch (this) {
    CheerKind.clap => accentById('amber'),
    CheerKind.fire => _fire,
    CheerKind.flex => accentById('violet'),
    CheerKind.heart => accentById('rose'),
  };
}

final _fire = AccentPalette.of('fire', 'Fire', 0xFFF08A24, 0xFFB8601A, 0xFFFDEEDC);
