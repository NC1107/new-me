import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../breathing/breathing_pace.dart';
import '../breathing/breathing_session_page.dart';
import 'big_number_stepper.dart';
import 'log_chip.dart';
import 'log_panes.dart';

/// Breathe: start the guided 5-minute session, or log minutes breathed somewhere else. A finished
/// session logs its minutes as an ordinary breathing entry.
class BreathingPane extends StatefulWidget {
  const BreathingPane({super.key, required this.busy, required this.failed, required this.onLog});

  final bool busy;
  final bool failed;
  final LogCallback onLog;

  @override
  State<BreathingPane> createState() => _BreathingPaneState();
}

class _BreathingPaneState extends State<BreathingPane> {
  BreathingPace _pace = kCyclicSighing;
  final _field = TextEditingController(text: '${kBreathingSession.inMinutes}');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  int? get _minutes => int.tryParse(_field.text);

  String? get _fieldError {
    final m = _minutes;
    return m != null && m > kMaxBreathingMinutes ? 'At most $kMaxBreathingMinutes minutes' : null;
  }

  bool get _valid => (_minutes ?? 0) > 0 && _fieldError == null;

  void _set(int value) => setState(() => _field.text = '${value.clamp(0, kMaxBreathingMinutes)}');

  void _log(int minutes) {
    widget.onLog(
      (id, date) => ActivityDraft(
        clientOpId: id,
        type: 'breathing',
        quantity: minutes,
        unit: 'minutes',
        date: date,
      ),
      added: 'Added $minutes ${minutes == 1 ? 'minute' : 'minutes'} of breathing',
    );
  }

  Future<void> _start() async {
    final minutes = await pushPage<int>(context, BreathingSessionPage(pace: _pace));
    if (minutes != null && minutes > 0 && mounted) _log(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final q = _minutes ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final p in kBreathingPaces)
              LogChip(
                label: p == kSlowBreathing ? 'Slow, 6 a minute' : p.name,
                semanticLabel: p.name,
                selected: p == _pace,
                onTap: () => setState(() => _pace = p),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _pace.blurb,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
        const SizedBox(height: 16),
        ChunkyButton(
          label: 'Start ${kBreathingSession.inMinutes}-minute session',
          icon: Icons.play_arrow_rounded,
          onPressed: widget.busy ? null : _start,
        ),
        const SizedBox(height: 28),
        const Text(
          'Or log minutes you breathed elsewhere',
          textAlign: TextAlign.center,
          style: AppText.caption,
        ),
        const SizedBox(height: 12),
        BigNumberStepper(
          controller: _field,
          unitLabel: 'minutes',
          errorText: _fieldError,
          onChanged: (_) => setState(() {}),
          onMinus: q > 0 && !widget.busy ? () => _set(q - 1) : null,
          onPlus: q < kMaxBreathingMinutes && !widget.busy ? () => _set(q + 1) : null,
        ),
        const SizedBox(height: 24),
        ChunkyButton.secondary(
          label: widget.failed ? 'Try again' : 'Save',
          busy: widget.busy,
          onPressed: _valid && !widget.busy ? () => _log(_minutes!) : null,
        ),
      ],
    );
  }
}
