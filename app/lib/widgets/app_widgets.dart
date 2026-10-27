import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';

/// A muted label shown above an input.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(color: kFgMuted, fontWeight: FontWeight.w600, fontSize: 12),
    ),
  );
}

/// The app's standard dark text field.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.obscure = false,
    this.onChanged,
    this.minLines,
    this.maxLines = 1,
    this.errorText,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final int? minLines;
  final int maxLines;

  /// When set, the field shows a red border and this message beneath it.
  final String? errorText;

  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  /// Names the field for screen readers when a separate label widget sits above it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    final textField = TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      minLines: obscure ? 1 : minLines,
      maxLines: obscure ? 1 : maxLines,
      style: const TextStyle(color: kFgPrimary, fontSize: 15),
      cursorColor: context.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: kFgMuted),
        filled: true,
        fillColor: kBgSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: hasError ? kDanger : kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: hasError ? kDanger : context.accent),
        ),
      ),
    );
    final field = semanticLabel == null
        ? textField
        : Semantics(label: semanticLabel, child: textField);
    // Keep the bare field when there's no error so existing layouts are unchanged.
    if (!hasError) return field;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 14, color: kDanger),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  errorText!,
                  style: const TextStyle(color: kDanger, fontSize: 12, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The app's full-width primary (filled, accent) button with a busy state.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          backgroundColor: context.accent,
          disabledBackgroundColor: kBgSurfaceHover,
          foregroundColor: context.onAccent,
          disabledForegroundColor: kFgMuted,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: busy
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: context.onAccent),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }
}

/// The app's one small pill-badge idiom: an icon and an all-caps label on an accent tint,
/// shared so every badge uses identical metrics.
class PillBadge extends StatelessWidget {
  const PillBadge({super.key, required this.icon, required this.label, required this.accent});

  final IconData icon;
  final String label;
  final AccentPalette accent;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: accent.light, borderRadius: BorderRadius.circular(9999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: accent.base),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: accent.base,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The hairline card every screen is built from: surface fill, 1px border, radius 14.
class OnyxCard extends StatelessWidget {
  const OnyxCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: kBorder),
    );
    return Material(
      color: kBgSurface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// A small section heading above a card.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: kFgMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    ),
  );
}

/// A thin progress track whose fill eases to a new value and does not animate on first build.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.color, this.height = 6});

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: value.clamp(0.0, 1.0)),
          duration: duration,
          curve: Curves.easeOut,
          builder: (context, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: height,
            backgroundColor: kBorder,
            color: color ?? context.accent,
          ),
        ),
      ),
    );
  }
}
