import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// The close button on the corner of a dismissable card, 48 square so it is easy to hit.
class DismissX extends StatelessWidget {
  const DismissX({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onPressed,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onPressed();
      },
      child: const SizedBox(
        width: 48,
        height: 48,
        child: Icon(Icons.close_rounded, size: 22, color: kInkSecondary),
      ),
    ),
  );
}
