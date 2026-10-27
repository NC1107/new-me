import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/me.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import 'me_support.dart';

/// Links Audiobookshelf so listening time counts toward the reading quest. The password is sent
/// once for the server to sign in with and is never kept, here or there.
class AudiobookshelfPage extends ConsumerStatefulWidget {
  const AudiobookshelfPage({super.key});

  @override
  ConsumerState<AudiobookshelfPage> createState() => _AudiobookshelfPageState();
}

class _AudiobookshelfPageState extends ConsumerState<AudiobookshelfPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _prefilled = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// A sign-in that needs renewing starts from the saved username, which is rarely what changed.
  void _prefill(AudiobookshelfLink? link) {
    if (_prefilled || link == null) return;
    _prefilled = true;
    if (link.needsSignIn) _username.text = link.username ?? '';
  }

  bool get _canSubmit => !_busy && _username.text.trim().isNotEmpty && _password.text.isNotEmpty;

  static String _copy(Object error) {
    if (error is ApiException) {
      switch (error.code) {
        case 'abs_login_failed':
          return 'Audiobookshelf did not accept that username and password.';
        case 'abs_unavailable':
          return 'Could not reach Audiobookshelf. Try again in a moment.';
        case 'abs_disabled':
          return 'Audiobookshelf is not set up on this server.';
        case 'rate_limited':
          return 'Too many tries. Wait a minute and try again.';
      }
    }
    return errorCopy(error);
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      HapticFeedback.lightImpact();
      if (!mounted) return;
      _password.clear();
      setState(() => _busy = false);
      if (done != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(done)));
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _copy(e);
        });
      }
    }
  }

  Future<void> _link() => _run(
    () => ref
        .read(meProvider.notifier)
        .linkAudiobookshelf(username: _username.text.trim(), password: _password.text),
    done: 'Audiobookshelf linked',
  );

  Future<void> _unlink() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Unlink Audiobookshelf?',
      message: 'Listening stops counting toward reading. Days that already ended keep their score.',
      confirmLabel: 'Unlink',
      destructive: true,
    );
    if (!confirmed) return;
    await _run(ref.read(meProvider.notifier).unlinkAudiobookshelf, done: 'Audiobookshelf unlinked');
  }

  @override
  Widget build(BuildContext context) {
    final view = readMe(ref, title: 'Audiobookshelf');
    if (view.placeholder != null) return view.placeholder!;
    final link = view.me!.audiobookshelf;
    _prefill(link);
    final linked = link?.linked ?? false;
    final renew = link?.needsSignIn ?? false;
    final editable = view.editable;
    final showForm = !linked || renew;
    return PageScaffold(
      title: 'Audiobookshelf',
      banner: view.banner,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) SaveError(_error!),
          if (showForm)
            ChunkyButton(
              label: renew ? 'Sign in again' : 'Link',
              busy: _busy,
              onPressed: editable && _canSubmit ? _link : null,
            ),
          if (showForm && linked) const SizedBox(height: 12),
          if (linked)
            ChunkyButton.secondary(
              label: 'Unlink',
              palette: _danger,
              onPressed: editable && !_busy ? _unlink : null,
            ),
        ],
      ),
      children: [
        Text(
          'Time you spend listening counts as reading minutes. New Me signs in once and does not '
          'keep your password.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        if (linked) ...[_AccountCard(link: link!), const SizedBox(height: 24)],
        if (showForm) ...[
          if (renew) ...[
            const _Note(
              icon: Icons.lock_reset_rounded,
              text:
                  'Audiobookshelf no longer accepts the saved sign-in, so listening is not being '
                  'counted. Sign in again to pick it back up.',
            ),
            const SizedBox(height: 20),
          ],
          const FieldLabel('Username'),
          IgnorePointer(
            ignoring: !editable,
            child: AppTextField(
              controller: _username,
              hint: 'Audiobookshelf username',
              onChanged: (_) => setState(() => _error = null),
              inputFormatters: [LengthLimitingTextInputFormatter(200)],
            ),
          ),
          const SizedBox(height: 16),
          const FieldLabel('Password'),
          IgnorePointer(
            ignoring: !editable,
            child: AppTextField(
              controller: _password,
              hint: 'Audiobookshelf password',
              obscure: true,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) {
                if (editable && _canSubmit) _link();
              },
            ),
          ),
        ],
      ],
    );
  }

  static final _danger = AccentPalette.of('danger', 'Danger', 0xFFD9534F, 0xFFB23C38, 0xFFFCE9E7);
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.link});

  final AudiobookshelfLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final synced = link.syncedAt;
    final palette = accentById('violet');
    final status = link.needsSignIn
        ? 'Sign-in expired'
        : synced == null
        ? 'Not synced yet'
        : 'Last sync ${relativeTime(synced, now)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                child: Icon(Icons.headphones_rounded, size: 24, color: palette.lip),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.username ?? 'Linked',
                      style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(status, style: AppText.caption.copyWith(color: kInkSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (link.lastError == 'unreachable') ...[
          const SizedBox(height: kCardGap),
          const _Note(
            icon: Icons.cloud_off_rounded,
            text: 'The last check could not reach Audiobookshelf. It tries again every 15 minutes.',
          ),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
    color: kSunken,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 20, color: kInkSecondary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
