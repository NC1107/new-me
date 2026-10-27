import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'accent.dart';
import 'tokens.dart';
import 'typography.dart';

/// One row of accent swatches, a slot each so the six always fit. Colors in [taken] belong to someone else and cannot be chosen.
class AccentPicker extends StatelessWidget {
  const AccentPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.taken = const {},
    this.swatchSize = 44,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final Set<String> taken;
  final double swatchSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in kAccentPresets)
          Expanded(
            child: _Swatch(
              palette: p,
              selected: p.id == selected,
              taken: taken.contains(p.id),
              size: swatchSize,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(p.id);
              },
            ),
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
                color: taken ? palette.tint : palette.fill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? kInk : (taken ? kBorder : palette.lip),
                  width: selected ? 3 : 2,
                ),
              ),
              child: taken
                  ? const Icon(Icons.block_rounded, color: kInkMuted, size: 20)
                  : selected
                  ? Icon(Icons.check_rounded, color: palette.onFill, size: size * 0.45)
                  : null,
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                palette.name,
                style: AppText.caption.copyWith(
                  color: taken ? kInkMuted : (selected ? kInk : kInkSecondary),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
