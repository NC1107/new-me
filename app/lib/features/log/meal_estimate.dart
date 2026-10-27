import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/log_actions.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';

/// The words for a confidence level, as the estimate note shows it.
String confidenceLabel(EstimateConfidence c) => switch (c) {
  EstimateConfidence.high => 'High confidence',
  EstimateConfidence.medium => 'Medium confidence',
  EstimateConfidence.low => 'Low confidence',
};

/// What a failed estimate says. A refused or unavailable estimate always ends with the manual
/// form still there, so the copy points at it.
String estimateErrorCopy(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'rate_limited':
        return 'That is a lot of estimates for one hour. Enter this one by hand for now.';
      case 'estimate_unavailable':
        return 'Claude could not estimate that. Try again, or enter it by hand.';
      case 'estimate_disabled':
        return 'Meal estimates are switched off on this server.';
    }
  }
  return errorCopy(error);
}

/// "Describe it": splits a sentence into foods, looks each up and hands the items to the meal
/// sheet. It never logs anything itself.
class MealEstimateBar extends ConsumerStatefulWidget {
  const MealEstimateBar({super.key, required this.onEstimate, required this.onBusyChanged});

  final ValueChanged<MealBreakdown> onEstimate;
  final ValueChanged<bool> onBusyChanged;

  @override
  ConsumerState<MealEstimateBar> createState() => _MealEstimateBarState();
}

class _MealEstimateBarState extends ConsumerState<MealEstimateBar> {
  final _text = TextEditingController();
  bool _describing = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _setBusy(bool busy) {
    setState(() => _busy = busy);
    widget.onBusyChanged(busy);
  }

  Future<void> _run(Future<MealBreakdown> Function() call) async {
    setState(() => _error = null);
    _setBusy(true);
    try {
      final estimate = await call();
      if (!mounted) return;
      _setBusy(false);
      setState(() => _describing = false);
      _text.clear();
      widget.onEstimate(estimate);
    } on Object catch (e) {
      if (!mounted) return;
      _setBusy(false);
      setState(() => _error = estimateErrorCopy(e));
    }
  }

  void _describe() => setState(() {
    _describing = true;
    _error = null;
  });

  Future<void> _sendText() {
    final text = _text.text.trim();
    return _run(() => ref.read(logActionsProvider).estimateMeal(text));
  }

  @override
  Widget build(BuildContext context) {
    final describe = ChunkyButton.secondary(
      label: 'Describe it',
      icon: Icons.edit_note_rounded,
      onPressed: _busy ? null : _describe,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        describe,
        if (_describing && !_busy) ...[
          const SizedBox(height: 14),
          const FieldLabel('Describe the meal'),
          AppTextField(
            controller: _text,
            hint: 'An apple, a Chomps stick and a Hot Pocket',
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            minLines: 1,
            autofocus: true,
            semanticLabel: 'Describe the meal',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          ChunkyButton(label: 'Estimate', onPressed: _text.text.trim().isEmpty ? null : _sendText),
        ],
        if (_busy) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            label: 'Estimating the meal',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 3, color: context.accent),
                ),
                const SizedBox(width: 12),
                Text('Estimating...', style: AppText.label.copyWith(color: kInkSecondary)),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 18, color: kDangerText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The line that follows a pre-filled form: how sure the estimate is and what it assumed.
class EstimateNote extends StatelessWidget {
  const EstimateNote({super.key, required this.estimate});

  final MealEstimate estimate;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: kSunken, borderRadius: BorderRadius.circular(kRadiusField)),
    child: Semantics(
      container: true,
      label:
          'Estimate. ${confidenceLabel(estimate.confidence)}. ${estimate.notes} '
          'Check the numbers, then save.',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 20, color: kInkSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estimate - ${confidenceLabel(estimate.confidence)}',
                  style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                ),
                if (estimate.notes.isNotEmpty)
                  Text(estimate.notes, style: AppText.label.copyWith(color: kInkSecondary)),
                Text(
                  'Check the numbers, then save.',
                  style: AppText.caption.copyWith(color: kInkSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
