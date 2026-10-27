import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'accent.dart';
import 'tokens.dart';

/// A row of accent swatches. Colors in [taken] belong to someone else and cannot be chosen.
class AccentPicker extends StatelessWidget {
  const AccentPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.taken = const {},
    this.swatchSize = 48,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final Set<String> taken;
  final double swatchSize;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final p in kAccentPresets)
          _Swatch(
            palette: p,
            selected: p.id == selected,
            taken: taken.contains(p.id),
            size: swatchSize,
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(p.id);
            },
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.palette,
    required this.selected,
    required this.taken,
    required this.size,
    required this.onTap,
  });

  final AccentPalette palette;
  final bool selected;
  final bool taken;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = taken ? '${palette.name}, taken' : palette.name;
    return Semantics(
      button: true,
      enabled: !taken,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: taken ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: taken ? palette.base.withValues(alpha: 0.18) : palette.base,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? kFgPrimary : kBorder, width: selected ? 3 : 1),
              ),
              child: taken
                  ? const Icon(Icons.block, color: kFgMuted, size: 20)
                  : selected
                  ? Icon(Icons.check, color: palette.onAccent, size: size * 0.45)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              palette.name,
              style: TextStyle(
                color: taken ? kFgMuted : (selected ? kFgPrimary : kFgSecondary),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
