import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/time_presets.dart';

const _kRowOne = [7 * 60, 8 * 60, 12 * 60];
const _kRowTwo = [18 * 60, 21 * 60, 22 * 60];

/// Picks a slot's time: a few common ones, any other time, or none. Resolves to a record whose
/// minutes are null for "no set time", or to null when the sheet is dismissed.
Future<({int? minutes})?> showSlotTimeSheet(BuildContext context, {int? current}) =>
    showAppSheet<({int? minutes})>(context, builder: (_) => _SlotTimeSheet(current: current));

class _SlotTimeSheet extends StatelessWidget {
  const _SlotTimeSheet({required this.current});

  final int? current;

  Future<void> _pickOther(BuildContext context) async {
    final base = current ?? 8 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base ~/ 60, minute: base % 60),
      helpText: 'Time',
    );
    if (picked != null && context.mounted) {
      Navigator.of(context).pop((minutes: picked.hour * 60 + picked.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    void choose(int minutes) {
      HapticFeedback.selectionClick();
      Navigator.of(context).pop((minutes: minutes));
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        kGutter,
        0,
        kGutter,
        kGutter + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: const Text('What time?', style: AppText.title)),
          const SizedBox(height: 16),
          TimePresets(selected: current ?? -1, minutes: _kRowOne, onChanged: choose),
          const SizedBox(height: kCardGap),
          TimePresets(selected: current ?? -1, minutes: _kRowTwo, onChanged: choose),
          const SizedBox(height: kCardGap),
          ChunkyButton.secondary(
            label: 'Pick another time',
            icon: Icons.schedule_rounded,
            onPressed: () => _pickOther(context),
          ),
          const SizedBox(height: kCardGap),
          ChunkyButton.secondary(
            label: 'No set time',
            onPressed: () => Navigator.of(context).pop((minutes: null)),
          ),
        ],
      ),
    );
  }
}
