import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../util/errors.dart';
import '../../state/timezone.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import 'me_support.dart';

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

class TimezonePage extends ConsumerStatefulWidget {
  const TimezonePage({super.key});

  @override
  ConsumerState<TimezonePage> createState() => _TimezonePageState();
}

class _TimezonePageState extends ConsumerState<TimezonePage> with MeSaving {
  final _custom = TextEditingController();
  String? _device;

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

  Future<void> _use(String zone, String current) async {
    if (saving) return;
    if (zone == current) return Navigator.of(context).pop();
    final ok = await saveMe(
      MePatch(timezone: zone),
      copy: (e) =>
          e.code == 'invalid_timezone' ? 'The server does not know "$zone".' : errorCopy(e),
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final view = readMe(ref, title: 'Time zone');
    if (view.placeholder != null) return view.placeholder!;
    final current = view.me!.user.timezone;
    final editable = view.editable;
    final zones = [?_device, ..._kZones.where((z) => z != _device)];
    return PageScaffold(
      title: 'Time zone',
      banner: view.banner,
      children: [
        Text(
          'Your day runs on this clock. A new zone applies from the next day.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, zone) in zones.indexed) ...[
                if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
                _ZoneRow(
                  zone: zone,
                  isDevice: zone == _device,
                  selected: zone == current,
                  onTap: editable ? () => _use(zone, current) : null,
                ),
              ],
            ],
          ),
        ),
        if (saveError != null) ...[const SizedBox(height: 12), SaveError(saveError!)],
        const SizedBox(height: 24),
        const FieldLabel('Other (for example Pacific/Auckland)'),
        IgnorePointer(
          ignoring: !editable,
          child: AppTextField(
            controller: _custom,
            hint: 'Region/City',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 16),
        ChunkyButton(
          label: 'Use this zone',
          busy: saving,
          onPressed: editable && _custom.text.trim().isNotEmpty
              ? () => _use(_custom.text.trim(), current)
              : null,
        ),
      ],
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.zone,
    required this.isDevice,
    required this.selected,
    required this.onTap,
  });

  final String zone;
  final bool isDevice;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    excludeSemantics: true,
    label: isDevice ? '$zone, this phone' : zone,
    onTap: onTap,
    child: Pressable(
      scale: 0.99,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(zone, style: AppText.body.copyWith(fontWeight: FontWeight.w700)),
                    if (isDevice) const Text('This phone', style: AppText.caption),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle_rounded, color: context.accent),
            ],
          ),
        ),
      ),
    ),
  );
}
