import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'dialogs.dart';
import 'pressable.dart';

/// The detail behind a short line: how a figure is worked out, and where it comes from.
class InfoContent {
  const InfoContent({required this.title, required this.paragraphs, this.source});

  final String title;
  final List<String> paragraphs;

  /// A citation, kept apart from the explanation so it reads as a reference.
  final String? source;
}

Future<void> showInfoSheet(BuildContext context, InfoContent info) => showAppSheet<void>(
  context,
  builder: (context) => Padding(
    padding: EdgeInsets.fromLTRB(
      kGutter,
      4,
      kGutter,
      kGutter + MediaQuery.paddingOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(info.title, style: AppText.title)),
          for (final p in info.paragraphs) ...[
            const SizedBox(height: 8),
            Text(p, style: AppText.body),
          ],
          if (info.source != null) ...[
            const SizedBox(height: 12),
            Text(info.source!, style: AppText.caption),
          ],
        ],
      ),
    ),
  ),
);

/// One short line with a small info icon; a tap opens the longer explanation and any citation in
/// a sheet. The icon sits inside a 44pt-high target.
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key, required this.info, this.style});

  /// A row that is only a label, for a page whose research and safety notes all sit behind it.
  InfoNote.label(String label, {Key? key, required List<String> paragraphs})
    : this(
        label,
        key: key,
        info: InfoContent(title: label, paragraphs: paragraphs),
      );

  final String text;
  final InfoContent info;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    void open() => showInfoSheet(context, info);
    return Semantics(
      button: true,
      label: text == info.title ? text : '$text. More about ${info.title}',
      excludeSemantics: true,
      onTap: open,
      child: Pressable(
        onTap: open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(text, style: style ?? AppText.caption)),
                const SizedBox(width: 6),
                const Icon(Icons.info_outline_rounded, size: 16, color: kInkSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
