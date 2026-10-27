import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/habit_models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/chunky_icon_button.dart';
import '../../widgets/dialogs.dart';

/// A tiny sheet to set a count habit to an exact number. Resolves to the number, or null when
/// dismissed.
Future<int?> showCountSheet(BuildContext context, {required HabitState habit}) =>
    showAppSheet<int>(context, builder: (_) => _CountSheet(habit: habit));

class _CountSheet extends StatefulWidget {
  const _CountSheet({required this.habit});

  final HabitState habit;

  @override
  State<_CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends State<_CountSheet> {
  late int _value = widget.habit.count;

  void _set(int value) {
    HapticFeedback.selectionClick();
    setState(() => _value = value.clamp(0, kMaxMarkCount));
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final target = habit.target;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kGutter,
        4,
        kGutter,
        kGutter + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(habit.name, style: AppText.title, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ChunkyIconButton(
                icon: Icons.remove_rounded,
                semanticLabel: 'Less',
                size: 56,
                kind: ChunkyKind.secondary,
                onPressed: _value > 0 ? () => _set(_value - 1) : null,
              ),
              Expanded(
                child: MediaQuery.withNoTextScaling(
                  child: Text(
                    target == null ? '$_value' : '$_value / $target',
                    textAlign: TextAlign.center,
                    style: AppText.tabular(AppText.display.copyWith(fontSize: 44)),
                  ),
                ),
              ),
              ChunkyIconButton(
                icon: Icons.add_rounded,
                semanticLabel: 'More',
                size: 56,
                onPressed: _value < kMaxMarkCount ? () => _set(_value + 1) : null,
              ),
            ],
          ),
          const SizedBox(height: 20),
          ChunkyButton(
            label: 'Save',
            palette: context.accentPalette,
            onPressed: () => Navigator.of(context).pop(_value),
          ),
        ],
      ),
    );
  }
}
