import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import 'big_number_stepper.dart';
import 'log_chip.dart';
import 'log_panes.dart';

const kMaxActivityNameLength = 60;
const kActivityIntensities = [
  (value: 'easy', label: 'Easy', hint: 'Easy minutes count half toward your exercise goal.'),
  (value: 'moderate', label: 'Moderate', hint: 'Moderate minutes count in full.'),
  (value: 'hard', label: 'Hard', hint: 'Hard minutes count in full.'),
];
const kActivitySuggestions = ['Walk', 'Run', 'Ride', 'Gym'];

/// "Added 30 min of Running" for the snackbar after a save.
String activityAddedLabel(String name, int minutes) => 'Added $minutes min of $name';

/// Log activity: a free name, minutes and how hard it was. It counts toward exercise minutes, so
/// it covers whatever Health does not see.
class ActivityPane extends StatefulWidget {
  const ActivityPane({super.key, required this.busy, required this.failed, required this.onLog});

  final bool busy;
  final bool failed;
  final LogCallback onLog;

  @override
  State<ActivityPane> createState() => _ActivityPaneState();
}

class _ActivityPaneState extends State<ActivityPane> {
  final _name = TextEditingController();
  final _minutes = TextEditingController(text: '30');
  String _intensity = 'moderate';

  @override
  void dispose() {
    _name.dispose();
    _minutes.dispose();
    super.dispose();
  }

  int? get _quantity => int.tryParse(_minutes.text);

  String get _trimmedName => _name.text.trim();

  String? get _minutesError {
    final q = _quantity;
    if (q == null) return null;
    return q > kMaxMinutes ? 'At most ${kMaxMinutes.formatted} minutes' : null;
  }

  bool get _valid => _trimmedName.isNotEmpty && (_quantity ?? 0) > 0 && _minutesError == null;

  void _setMinutes(int value) => setState(() => _minutes.text = '${value.clamp(0, kMaxMinutes)}');

  void _log() {
    final name = _trimmedName;
    final minutes = _quantity!;
    final intensity = _intensity;
    widget.onLog(
      (id, date) => ActivityDraft.other(
        clientOpId: id,
        name: name,
        minutes: minutes,
        intensity: intensity,
        date: date,
      ),
      added: activityAddedLabel(name, minutes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _quantity ?? 0;
    final hint = kActivityIntensities.firstWhere((i) => i.value == _intensity).hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('What did you do?'),
        AppTextField(
          controller: _name,
          hint: 'Swimming, tennis, a long hike...',
          semanticLabel: 'Activity name',
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(kMaxActivityNameLength)],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in kActivitySuggestions)
              LogChip(
                label: s,
                selected: _trimmedName == s,
                onTap: () => setState(() => _name.text = s),
              ),
          ],
        ),
        const SizedBox(height: 20),
        BigNumberStepper(
          controller: _minutes,
          unitLabel: 'minutes',
          errorText: _minutesError,
          onChanged: (_) => setState(() {}),
          onMinus: q > 0 && !widget.busy ? () => _setMinutes(q - 5) : null,
          onPlus: q < kMaxMinutes && !widget.busy ? () => _setMinutes(q + 5) : null,
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final v in const [10, 15, 30])
              LogChip(
                label: '+$v',
                enabled: !widget.busy && q < kMaxMinutes,
                onTap: () => _setMinutes(q + v),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const FieldLabel('How hard was it?'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final i in kActivityIntensities)
              LogChip(
                label: i.label,
                selected: i.value == _intensity,
                onTap: () => setState(() => _intensity = i.value),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(hint, style: AppText.caption.copyWith(color: kInkSecondary)),
        const SizedBox(height: 24),
        ChunkyButton(
          label: widget.failed ? 'Try again' : 'Save',
          busy: widget.busy,
          onPressed: _valid && !widget.busy ? _log : null,
        ),
      ],
    );
  }
}
