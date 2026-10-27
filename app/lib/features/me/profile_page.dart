import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/board.dart';
import '../../state/clock.dart';
import '../../state/me.dart';
import '../../theme/accent.dart';
import '../../theme/accent_picker.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/pressable.dart';
import '../../widgets/avatar.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../insights/birth_year_sheet.dart';
import 'me_support.dart';

const _kMaxName = 40;

/// Name and colour. A colour the other person has is shown as taken.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> with MeSaving {
  final _name = TextEditingController();
  String _color = 'green';
  int? _birthYear;
  AccountUser? _server;

  @override
  void initState() {
    super.initState();
    // Only a changed field replaces what is typed, so saving another page keeps the edits.
    ref.listenManual(meProvider, (_, next) {
      final user = next.value?.data.user;
      if (user == null) return;
      final before = _server;
      _server = user;
      if (before == null || before.name != user.name) _name.text = user.name;
      if (before == null || before.color != user.color) _color = user.color;
      if (before == null || before.birthYear != user.birthYear) _birthYear = user.birthYear;
      setState(() {});
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _trimmed => _name.text.trim();
  bool get _nameChanged => _trimmed != _server?.name;
  bool get _birthChanged => _birthYear != _server?.birthYear;
  bool get _dirty => _nameChanged || _color != _server?.color || _birthChanged;
  bool get _valid => _trimmed.isNotEmpty && _trimmed.length <= _kMaxName;

  Set<String> get _taken {
    final users = ref.watch(boardProvider).value?.data.users ?? const <BoardUser>[];
    return {
      for (final u in users)
        if (u.id != _server?.id) u.color,
    };
  }

  Future<void> _save() async {
    final ok = await saveMe(
      MePatch(
        name: _nameChanged ? _trimmed : null,
        color: _color != _server?.color ? _color : null,
        birthYear: _birthChanged ? _birthYear : null,
        clearBirthYear: _birthChanged && _birthYear == null,
      ),
    );
    if (ok && mounted) {
      toast('Saved');
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _pickBirthYear() async {
    final choice = await showBirthYearSheet(
      context,
      currentYear: ref.read(clockProvider)().year,
      initial: _birthYear,
    );
    if (choice != null && mounted) setState(() => _birthYear = choice.year);
  }

  @override
  Widget build(BuildContext context) {
    final view = readMe(ref, title: 'Profile');
    if (view.placeholder != null) return view.placeholder!;
    final editable = view.editable;
    final palette = accentById(_color);
    return PageScaffold(
      title: 'Profile',
      banner: view.banner,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saveError != null) SaveError(saveError!),
          ChunkyButton(
            palette: palette,
            label: saveError != null ? 'Try again' : 'Save',
            busy: saving,
            onPressed: editable && _dirty && _valid ? _save : null,
          ),
        ],
      ),
      children: [
        Center(
          child: Avatar(name: _trimmed.isEmpty ? '?' : _trimmed, palette: palette, size: 88),
        ),
        const SizedBox(height: 24),
        const FieldLabel('Name'),
        IgnorePointer(
          ignoring: !editable,
          child: AppTextField(
            controller: _name,
            hint: 'Your name',
            onChanged: (_) => setState(() {}),
            inputFormatters: [LengthLimitingTextInputFormatter(_kMaxName)],
          ),
        ),
        const SizedBox(height: 24),
        const FieldLabel('Colour'),
        IgnorePointer(
          ignoring: !editable,
          child: AccentPicker(
            selected: _color,
            taken: _taken,
            swatchSize: 44,
            onChanged: (id) => setState(() => _color = id),
          ),
        ),
        const SizedBox(height: 24),
        const FieldLabel('Birth year (optional)'),
        IgnorePointer(
          ignoring: !editable,
          child: _BirthYearRow(year: _birthYear, onTap: _pickBirthYear),
        ),
        const SizedBox(height: 6),
        const Text(
          'Only used to suggest a step range for your age. It is never shown to anyone else.',
          style: AppText.caption,
        ),
      ],
    );
  }
}

class _BirthYearRow extends StatelessWidget {
  const _BirthYearRow({required this.year, required this.onTap});

  final int? year;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    excludeSemantics: true,
    label: year == null ? 'Birth year, not set' : 'Birth year, $year',
    onTap: onTap,
    child: Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusField),
          border: Border.all(color: kBorder, width: kBorderWidth),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                year == null ? 'Not set' : '$year',
                style: AppText.body.copyWith(color: year == null ? kInkMuted : kInk),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kInkMuted),
          ],
        ),
      ),
    ),
  );
}
