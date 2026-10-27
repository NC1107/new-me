import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A two-button confirmation on a white card. Resolves true only when confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: kBgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: kBorder),
      ),
      title: Text(
        title,
        style: const TextStyle(color: kFgPrimary, fontWeight: FontWeight.w700, fontSize: 18),
      ),
      content: Text(
        message,
        style: const TextStyle(color: kFgSecondary, fontSize: 14, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: kFgSecondary),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: destructive ? kDanger : null),
          child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// A modal bottom sheet in the app's shape: surface fill, 22px top radius, keyboard aware.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kBgSurface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: builder,
  );
}
