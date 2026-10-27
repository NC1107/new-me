import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/app_widgets.dart';

/// The Save button of a Me section with the error from the last attempt above it.
class SaveBar extends StatelessWidget {
  const SaveBar({
    super.key,
    required this.enabled,
    required this.saving,
    required this.onSave,
    this.error,
    this.label = 'Save',
  });

  final bool enabled;
  final bool saving;
  final VoidCallback onSave;
  final String? error;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 16, color: kDanger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  error!,
                  style: const TextStyle(color: kDanger, fontSize: 13, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      PrimaryButton(
        label: error != null ? 'Try again' : label,
        enabled: enabled && !saving,
        busy: saving,
        onTap: onSave,
      ),
    ],
  );
}
