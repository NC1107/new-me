import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/timezone.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/pressable.dart';

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

const _kZoneNames = {
  'America/New_York': 'Eastern Time (New York)',
  'America/Chicago': 'Central Time (Chicago)',
  'America/Denver': 'Mountain Time (Denver)',
  'America/Los_Angeles': 'Pacific Time (Los Angeles)',
  'Europe/London': 'London',
  'Europe/Paris': 'Central Europe (Paris)',
  'Europe/Berlin': 'Central Europe (Berlin)',
  'Asia/Tokyo': 'Japan (Tokyo)',
  'Australia/Sydney': 'Eastern Australia (Sydney)',
  'UTC': 'UTC',
};

/// A zone as people say it: "Eastern Time (New York)", or the city of an id with no name here,
/// so "Pacific/Auckland" reads "Auckland".
String zoneLabel(String zone) {
  final known = _kZoneNames[zone];
  if (known != null) return known;
  final city = zone.split('/').last.replaceAll('_', ' ');
  return city.isEmpty ? zone : city;
}

/// The zones to pick from, with this phone's first and a field for any other. It only reports the
/// choice; the Schedule page saves it with the rest.
class TimezonePicker extends ConsumerStatefulWidget {
  const TimezonePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  ConsumerState<TimezonePicker> createState() => _TimezonePickerState();
}

class _TimezonePickerState extends ConsumerState<TimezonePicker> {
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

  void _pick(String zone) {
    setState(_custom.clear);
    widget.onChanged(zone);
  }

  @override
  Widget build(BuildContext context) {
    final zones = [?_device, ..._kZones.where((z) => z != _device)];
    final custom = _custom.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, zone) in zones.indexed) ...[
                if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
                _ZoneRow(
                  zone: zone,
                  isDevice: zone == _device,
                  selected: custom.isEmpty && zone == widget.selected,
                  onTap: widget.enabled ? () => _pick(zone) : null,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Other (for example Pacific/Auckland)'),
        IgnorePointer(
          ignoring: !widget.enabled,
          child: AppTextField(
            controller: _custom,
            hint: 'Region/City',
            onChanged: (value) {
              setState(() {});
              if (value.trim().isNotEmpty) widget.onChanged(value.trim());
            },
          ),
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
    label: isDevice ? '${zoneLabel(zone)}, this phone' : zoneLabel(zone),
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
                    Text(
                      zoneLabel(zone),
                      style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                    ),
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
