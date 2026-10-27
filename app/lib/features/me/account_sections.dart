import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/health_sync.dart';
import '../../state/me.dart';
import '../../state/session.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/dialogs.dart';

class HealthSection extends ConsumerWidget {
  const HealthSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthSyncProvider);
    final synced = health.lastSyncedAt;
    return OnyxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Reads your steps and active energy from Apple Health to score the day. New Me never '
            'writes to Health.',
            style: TextStyle(color: kFgSecondary, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 12),
          if (!health.prompted)
            PrimaryButton(
              label: 'Connect Health',
              enabled: !health.syncing,
              busy: health.syncing,
              onTap: () => ref.read(healthSyncProvider.notifier).connect(),
            )
          else ...[
            Row(
              children: [
                Icon(Icons.favorite_outline_rounded, size: 18, color: context.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    synced == null
                        ? 'Not synced yet'
                        : 'Last sync ${relativeTime(synced, ref.watch(clockProvider)())}',
                    style: const TextStyle(
                      color: kFgPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'To change what New Me can read, open Health > Sharing > Apps > New Me.',
              style: TextStyle(color: kFgMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class AdminSection extends ConsumerStatefulWidget {
  const AdminSection({super.key});

  @override
  ConsumerState<AdminSection> createState() => _AdminSectionState();
}

class _AdminSectionState extends ConsumerState<AdminSection> {
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
    return OnyxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Give this code to the person you are inviting. It works once.',
            style: TextStyle(color: kFgSecondary, fontSize: 13, height: 1.45),
          ),
          if (invite != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      invite.code,
                      maxLines: 1,
                      style: const TextStyle(
                        color: kFgPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _copy(invite.code),
                  tooltip: 'Copy code',
                  icon: Icon(Icons.copy_rounded, color: context.accent),
                ),
              ],
            ),
            Text(
              'Expires at ${DateFormat.Hm().format(invite.expiresAt.toLocal())}',
              style: const TextStyle(color: kFgMuted, fontSize: 12),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: kDanger, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          PrimaryButton(
            label: invite == null ? 'Create pairing code' : 'Create a new code',
            enabled: !_busy,
            busy: _busy,
            onTap: _create,
          ),
        ],
      ),
    );
  }
}

class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(sessionProvider.select((s) => s.session?.baseUrl)) ?? '';
    return OnyxCard(
      child: Column(
        children: [
          _row('Version', kClientVersion),
          const SizedBox(height: 10),
          _row('Server', server.replaceFirst('https://', '')),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Row(
    children: [
      Text(label, style: const TextStyle(color: kFgSecondary, fontSize: 14)),
      const SizedBox(width: 16),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(color: kFgPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class LeaveButton extends ConsumerWidget {
  const LeaveButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(meProvider.select((m) => m.value?.data.user.isAdmin)) ?? false;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () async {
          final confirmed = await confirmDialog(
            context,
            title: 'Leave this server?',
            message: isAdmin
                ? 'This phone is signed out. You are the admin, so a new pairing code can only come '
                      'from the server itself.'
                : 'This phone is signed out. Your scores stay on the server and a new pairing '
                      'code brings you back.',
            confirmLabel: 'Leave',
            destructive: true,
          );
          if (!confirmed) return;
          HapticFeedback.mediumImpact();
          await ref.read(sessionProvider.notifier).signOut();
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: kDanger,
          side: const BorderSide(color: kDanger),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text('Leave this server', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
