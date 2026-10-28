import 'package:flutter/material.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';

/// The one switch: a white thumb in both states, a track in the person's colour (or [palette])
/// when on and the neutral lip colour when off.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged, this.palette});

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// The on-track colour; the person's colour from the theme when null.
  final AccentPalette? palette;

  @override
  Widget build(BuildContext context) => Switch(
    value: value,
    onChanged: onChanged,
    activeThumbColor: kSurface,
    activeTrackColor: palette?.fill ?? context.accent,
    inactiveThumbColor: kSurface,
    inactiveTrackColor: kLip,
    trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
  );
}
