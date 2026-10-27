import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import 'onboarding_controller.dart';

/// The hidden way to point the app at another server, opened by holding the mascot.
/// Resolves with the address to use, or null when dismissed.
Future<String?> showServerSheet(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ServerSheet(current: current),
  );
}

class _ServerSheet extends StatefulWidget {
  const _ServerSheet({required this.current});

  final String current;

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(kGutter, 24, kGutter, kGutter + insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Server', style: AppText.headline),
          const SizedBox(height: 6),
          const Text('For testing builds. Most people never need this.', style: AppText.caption),
          const SizedBox(height: 16),
          AppTextField(
            controller: _controller,
            hint: kDefaultServer,
            semanticLabel: 'Server address',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          ChunkyButton(
            label: 'Connect',
            onPressed: () => Navigator.of(context).pop(_controller.text),
          ),
          const SizedBox(height: kCardGap),
          ChunkyButton.secondary(
            label: 'Use the default',
            onPressed: () => Navigator.of(context).pop(''),
          ),
        ],
      ),
    );
  }
}
