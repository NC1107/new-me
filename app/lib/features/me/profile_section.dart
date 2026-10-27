import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/board.dart';
import '../../state/me.dart';
import '../../state/timezone.dart';
import '../../theme/accent.dart';
import '../../theme/accent_picker.dart';
import '../../theme/tokens.dart';
import '../../util/errors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/dialogs.dart';
import 'save_bar.dart';

const _kMaxName = 40;

class ProfileSection extends ConsumerStatefulWidget {
  const ProfileSection({super.key, required this.me, required this.editable});

  final Me me;
  final bool editable;

  @override
  ConsumerState<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<ProfileSection> {
  late final TextEditingController _name = TextEditingController(text: widget.me.user.name);
  late String _color = widget.me.user.color;
  bool _saving = false;
  String? _error;

  @override
  void didUpdateWidget(ProfileSection old) {
    super.didUpdateWidget(old);
    if (!identical(old.me, widget.me)) {
      _name.text = widget.me.user.name;
      _color = widget.me.user.color;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _trimmed => _name.text.trim();

  bool get _nameChanged => _trimmed != widget.me.user.name;
  bool get _dirty => _nameChanged || _color != widget.me.user.color;
  bool get _valid => _trimmed.isNotEmpty && _trimmed.length <= _kMaxName;

  Set<String> get _taken {
    final users = ref.watch(boardProvider).value?.data.users ?? const <BoardUser>[];
    return {
      for (final u in users)
        if (u.id != widget.me.user.id) u.color,
    };
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(meProvider.notifier)
          .save(
            MePatch(
              name: _nameChanged ? _trimmed : null,
              color: _color != widget.me.user.color ? _color : null,
            ),
          );
      HapticFeedback.lightImpact();
      if (mounted) setState(() => _saving = false);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorCopy(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentById(_color);
    final initial = _trimmed.isEmpty ? '?' : _trimmed.substring(0, 1).toUpperCase();
    return OnyxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: accent.base,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: accent.onAccent,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.me.user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kFgPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const FieldLabel('Name'),
          IgnorePointer(
            ignoring: !widget.editable,
            child: AppTextField(
              controller: _name,
              hint: 'Your name',
              onChanged: (_) => setState(() {}),
              inputFormatters: [LengthLimitingTextInputFormatter(_kMaxName)],
            ),
          ),
          const SizedBox(height: 18),
          const FieldLabel('Color'),
          IgnorePointer(
            ignoring: !widget.editable,
            child: AccentPicker(
              selected: _color,
              taken: _taken,
              swatchSize: 40,
              onChanged: (id) => setState(() => _color = id),
            ),
          ),
          const SizedBox(height: 18),
          SaveBar(
            enabled: widget.editable && _dirty && _valid,
            saving: _saving,
            error: _error,
            onSave: _save,
          ),
        ],
      ),
    );
  }
}

/// Short list of common zones; anything else goes in the free text field and the server checks it.
const _kZones = [
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'Asia/Tokyo',
  'Australia/Sydney',
  'UTC',
];

class TimezoneSection extends ConsumerWidget {
  const TimezoneSection({super.key, required this.me, required this.editable});

  final Me me;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OnyxCard(
      onTap: editable
          ? () => showAppSheet<void>(context, builder: (_) => _TimezoneSheet(current: me.timezone))
          : null,
      child: Row(
        children: [
          const Icon(Icons.public_outlined, size: 20, color: kFgSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Time zone',
                  style: TextStyle(color: kFgPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(me.timezone, style: const TextStyle(color: kFgSecondary, fontSize: 13)),
              ],
            ),
          ),
          if (editable) const Icon(Icons.chevron_right_rounded, color: kFgMuted),
        ],
      ),
    );
  }
}

class _TimezoneSheet extends ConsumerStatefulWidget {
  const _TimezoneSheet({required this.current});

  final String current;

  @override
  ConsumerState<_TimezoneSheet> createState() => _TimezoneSheetState();
}

class _TimezoneSheetState extends ConsumerState<_TimezoneSheet> {
  final _custom = TextEditingController();
  String? _device;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(deviceTimezoneProvider)().then((zone) {
      if (mounted) setState(() => _device = zone);
    });
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _use(String zone) async {
    if (_saving) return;
    if (zone == widget.current) return Navigator.of(context).pop();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(meProvider.notifier).save(MePatch(timezone: zone));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.code == 'invalid_timezone'
              ? 'The server does not know "$zone".'
              : errorCopy(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = [?_device, ..._kZones.where((z) => z != _device)];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Time zone',
                  style: TextStyle(color: kFgPrimary, fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'A new zone applies from the next day.',
                  style: TextStyle(color: kFgMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                for (final zone in zones)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(zone, style: const TextStyle(color: kFgPrimary, fontSize: 15)),
                    subtitle: zone == _device
                        ? const Text('This phone', style: TextStyle(color: kFgMuted, fontSize: 12))
                        : null,
                    trailing: zone == widget.current
                        ? Icon(Icons.check_rounded, color: context.accent)
                        : null,
                    onTap: () => _use(zone),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: kDanger, fontSize: 13)),
                ],
                const SizedBox(height: 12),
                const FieldLabel('Other (for example Pacific/Auckland)'),
                AppTextField(
                  controller: _custom,
                  hint: 'Region/City',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'Use this zone',
                  enabled: _custom.text.trim().isNotEmpty,
                  busy: _saving,
                  onTap: () => _use(_custom.text.trim()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
