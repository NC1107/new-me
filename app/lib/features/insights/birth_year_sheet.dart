import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';

const kEarliestBirthYear = 1900;
const _kDefaultYear = 1990;
const _kItem = 48.0;

/// Asks for a birth year. Resolves null when dismissed, a record with a year when saved, and a
/// record with a null year when the person chose to forget it.
Future<({int? year})?> showBirthYearSheet(
  BuildContext context, {
  required int currentYear,
  int? initial,
}) => showAppSheet<({int? year})>(
  context,
  builder: (_) => BirthYearSheet(currentYear: currentYear, initial: initial),
);

class BirthYearSheet extends StatefulWidget {
  const BirthYearSheet({super.key, required this.currentYear, this.initial});

  /// The latest year that can be picked, which is this year.
  final int currentYear;
  final int? initial;

  @override
  State<BirthYearSheet> createState() => _BirthYearSheetState();
}

class _BirthYearSheetState extends State<BirthYearSheet> {
  late int _year = (widget.initial ?? _kDefaultYear).clamp(kEarliestBirthYear, widget.currentYear);
  late final FixedExtentScrollController _controller = FixedExtentScrollController(
    initialItem: widget.currentYear - _year,
  );

  int get _count => widget.currentYear - kEarliestBirthYear + 1;

  // Newest year first, so the common ages sit near the top of the wheel.
  int _yearAt(int index) => widget.currentYear - index;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _step(int by) {
    final index = (_controller.selectedItem + by).clamp(0, _count - 1);
    _controller.jumpToItem(index);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Your birth year', style: AppText.title),
            const SizedBox(height: 6),
            Text(
              'Only your age sets the step range, never your height or weight. It stays private '
              'to you and you can remove it any time.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Birth year $_year',
              value: '$_year',
              increasedValue: '${_year + 1}',
              decreasedValue: '${_year - 1}',
              onIncrease: _year < widget.currentYear ? () => _step(-1) : null,
              onDecrease: _year > kEarliestBirthYear ? () => _step(1) : null,
              child: ExcludeSemantics(
                child: Container(
                  height: _kItem * 5,
                  decoration: BoxDecoration(
                    color: kSunken,
                    borderRadius: BorderRadius.circular(kRadiusButton),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: _kItem,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(kRadiusField),
                          border: Border.all(color: kBorder, width: kBorderWidth),
                        ),
                      ),
                      ListWheelScrollView.useDelegate(
                        controller: _controller,
                        itemExtent: _kItem,
                        diameterRatio: 1.8,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (i) {
                          HapticFeedback.selectionClick();
                          setState(() => _year = _yearAt(i));
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: _count,
                          builder: (context, i) => Center(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => reduce
                                  ? _controller.jumpToItem(i)
                                  : _controller.animateToItem(
                                      i,
                                      duration: kMotionDuration,
                                      curve: Curves.easeOut,
                                    ),
                              child: Text(
                                '${_yearAt(i)}',
                                style: AppText.tabular(
                                  AppText.headline.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: _yearAt(i) == _year ? kInk : kInkMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ChunkyButton(label: 'Save', onPressed: () => Navigator.pop(context, (year: _year))),
            if (widget.initial != null) ...[
              const SizedBox(height: 8),
              ChunkyButton.secondary(
                label: 'Remove birth year',
                onPressed: () => Navigator.pop(context, (year: null)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
