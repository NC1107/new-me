import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';

/// Ice blue for freezes. The text shade clears 4.5:1 on white and on the canvas.
const kFreezeFill = Color(0xFF4DA3E0);
const kFreezeWash = Color(0xFFE3F1FC);
const kFreezeText = Color(0xFF2468A0);

/// What a day in a streak strip stands for. Precedence runs from the top: a counted day is
/// always a counted day, whatever else the server also flagged.
enum DayStatus { counted, repaired, frozen, away, rest, none }

DayStatus dayStatus(DayMark mark, {bool? counted}) {
  if (counted ?? mark.counted) return DayStatus.counted;
  if (mark.repaired) return DayStatus.repaired;
  if (mark.frozen) return DayStatus.frozen;
  if (mark.away) return DayStatus.away;
  if (mark.rest) return DayStatus.rest;
  return DayStatus.none;
}

extension DayStatusLook on DayStatus {
  IconData? get icon => switch (this) {
    DayStatus.counted => Icons.local_fire_department_rounded,
    DayStatus.repaired => Icons.healing_rounded,
    DayStatus.frozen => Icons.ac_unit_rounded,
    DayStatus.away => Icons.pause_circle_rounded,
    DayStatus.rest => Icons.bedtime_rounded,
    DayStatus.none => null,
  };

  /// The words for screen readers and legends.
  String get label => switch (this) {
    DayStatus.counted => 'streak day counted',
    DayStatus.repaired => 'repaired day',
    DayStatus.frozen => 'frozen day',
    DayStatus.away => 'away day',
    DayStatus.rest => 'rest day',
    DayStatus.none => 'not counted',
  };
}

/// The two freeze slots as snowflakes: held ones in ice blue, empty ones outlined and dim.
class FreezeFlakes extends StatelessWidget {
  const FreezeFlakes({super.key, required this.held, this.size = 20, this.max = kMaxFreezes});

  final int held;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = held.clamp(0, max);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < max; i++)
            Icon(Icons.ac_unit_rounded, size: size, color: i < shown ? kFreezeFill : kBorder),
        ],
      ),
    );
  }
}

String freezesLabel(int held) => held == 1 ? '1 streak freeze' : '$held streak freezes';
