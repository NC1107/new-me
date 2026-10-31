import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';

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
                  'Estimate, ${confidenceLabel(estimate.confidence).toLowerCase()}',
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
