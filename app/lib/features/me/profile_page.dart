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
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/pressable.dart';
import '../../widgets/avatar.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../insights/birth_year_sheet.dart';
import '../log/log_chip.dart';
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
  final _height = TextEditingController();
  int? _birthYear;
  String? _sex;
  GoalKind _goalKind = GoalKind.maintain;
  double _pace = 0;
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
      if (before == null || before.heightCm != user.heightCm) {
        _height.text = user.heightCm == null ? '' : user.heightCm!.formatted;
      }
      if (before == null || before.sex != user.sex) _sex = user.sex;
      if (before == null || before.goalSetting != user.goalSetting) {
        _goalKind = user.goalSetting.kind;
        _pace = user.goalSetting.paceKgPerWeek;
      }
      setState(() {});
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    super.dispose();
  }

  String get _trimmed => _name.text.trim();
  bool get _nameChanged => _trimmed != _server?.name;
  bool get _birthChanged => _birthYear != _server?.birthYear;
  double? get _heightValue => double.tryParse(_height.text.trim().replaceAll(',', '.'));
  bool get _heightBlank => _height.text.trim().isEmpty;
  bool get _heightValid =>
      _heightBlank || (_heightValue != null && _heightValue! >= 100 && _heightValue! <= 250);
  bool get _heightChanged => _heightBlank
      ? _server?.heightCm != null
      : _heightValue != null && _heightValue != _server?.heightCm;
  bool get _sexChanged => _sex != _server?.sex;
  GoalSetting get _goal => GoalSetting(kind: _goalKind, paceKgPerWeek: _pace);
  bool get _goalChanged => _goal != _server?.goalSetting;
  bool get _dirty =>
      _nameChanged ||
      _color != _server?.color ||
      _birthChanged ||
      _heightChanged ||
      _sexChanged ||
      _goalChanged;
  bool get _valid => _trimmed.isNotEmpty && _trimmed.length <= _kMaxName && _heightValid;

  void _pickGoal(GoalKind kind) {
    if (kind == _goalKind) return;
    setState(() {
      _goalKind = kind;
      _pace = switch (kind) {
        GoalKind.lose => kLosePaces.first,
        GoalKind.gain => kGainPaces[1],
        GoalKind.maintain => 0,
      };
    });
  }

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
        heightCm: _heightChanged && !_heightBlank ? _heightValue : null,
        clearHeight: _heightChanged && _heightBlank,
        sex: _sexChanged ? _sex : null,
        clearSex: _sexChanged && _sex == null,
        goal: _goalChanged ? _goal : null,
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
        const SizedBox(height: 24),
        const FieldLabel('Height in cm (optional)'),
        IgnorePointer(
          ignoring: !editable,
          child: AppTextField(
            controller: _height,
            hint: 'For example 178',
            semanticLabel: 'Height in centimetres',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            errorText: _heightValid ? null : 'Between 100 and 250 cm',
            onChanged: (_) => setState(() {}),
            inputFormatters: [LengthLimitingTextInputFormatter(5)],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Used for your targets. Left empty, the height in Apple Health is used.',
          style: AppText.caption,
        ),
        const SizedBox(height: 24),
        const FieldLabel('Sex (optional)'),
        IgnorePointer(
          ignoring: !editable,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in const [('male', 'Male'), ('female', 'Female')])
                LogChip(
                  label: label,
                  selected: _sex == value,
                  onTap: () => setState(() => _sex = _sex == value ? null : value),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'The resting energy equation and the fiber and calorie floor tables differ by sex. '
          'Tap again to clear.',
          style: AppText.caption,
        ),
        const SizedBox(height: 24),
        const FieldLabel('Weight goal'),
        IgnorePointer(
          ignoring: !editable,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (kind, label) in const [
                (GoalKind.lose, 'Lose'),
                (GoalKind.maintain, 'Maintain'),
                (GoalKind.gain, 'Gain'),
              ])
                LogChip(label: label, selected: _goalKind == kind, onTap: () => _pickGoal(kind)),
            ],
          ),
        ),
        if (_goalKind != GoalKind.maintain) ...[
          const SizedBox(height: 12),
          const FieldLabel('Pace'),
          IgnorePointer(
            ignoring: !editable,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pace in _goalKind == GoalKind.lose ? kLosePaces : kGainPaces)
                  LogChip(
                    label: '$pace kg a week',
                    selected: _pace == pace,
                    onTap: () => setState(() => _pace = pace),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(switch (_goalKind) {
          GoalKind.lose => 'Never more than 1% of your body weight a week.',
          GoalKind.gain => 'Held to 0.5% of your body weight a week when the target is worked out.',
          GoalKind.maintain => 'Your calorie target keeps your weight where it is.',
        }, style: AppText.caption),
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
