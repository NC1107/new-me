import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/session.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pop_in.dart';
import '../../widgets/pressable.dart';
import 'me_support.dart';
import '../../util/time_format.dart';

/// Admin only: mint a one-time code for the person you are inviting.
class PairingPage extends ConsumerStatefulWidget {
  const PairingPage({super.key});

  @override
  ConsumerState<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends ConsumerState<PairingPage> {
  Invite? _invite;
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invite = await client.createInvite();
      HapticFeedback.lightImpact();
      if (mounted) {
        setState(() {
          _invite = invite;
          _busy = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorCopy(e);
        });
      }
    }
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Code copied')));
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    return PageScaffold(
      title: 'Pairing code',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) SaveError(_error!),
          ChunkyButton(
            label: invite == null ? 'Create pairing code' : 'Create a new code',
            busy: _busy,
            onPressed: _create,
          ),
        ],
      ),
      children: [
        Center(
          child: Mascot(size: 96, state: invite == null ? MascotState.idle : MascotState.cheer),
        ),
        const SizedBox(height: 16),
        Text(
          'Give this code to the person you are inviting. It works once.',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
        if (invite != null) ...[
          const SizedBox(height: 20),
          PopIn(
            child: AppCard(
              borderColor: context.accent,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: SelectableText(
                            invite.code,
                            maxLines: 1,
                            style: AppText.tabular(
                              AppText.display.copyWith(letterSpacing: 2, color: context.accentLip),
                            ),
                          ),
                        ),
                      ),
                      Pressable(
                        onTap: () => _copy(invite.code),
                        child: Semantics(
                          button: true,
                          label: 'Copy code',
                          excludeSemantics: true,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(Icons.copy_rounded, color: context.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Expires at ${formatClock(invite.expiresAt.toLocal())}',
                      style: AppText.caption,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
