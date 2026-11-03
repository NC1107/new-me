import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pressable.dart';

/// A quiet "Sources and safety" row that opens the research, citations and cautions in a sheet,
/// so training pages stay short enough to act on.
class InfoNote extends StatelessWidget {
  const InfoNote({super.key, required this.paragraphs, this.label = 'Sources and safety'});

  final String label;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: () => _open(context),
      child: Pressable(
        scale: 0.98,
        onTap: () => _open(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 20, color: kInkMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: AppText.caption.copyWith(color: kInkMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) => showAppSheet<void>(
    context,
    builder: (_) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(label, style: AppText.title)),
          for (final p in paragraphs) ...[const SizedBox(height: 12), Text(p, style: AppText.body)],
        ],
      ),
    ),
  );
}
