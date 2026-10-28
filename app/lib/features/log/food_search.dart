import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/models.dart';
import '../../state/log_actions.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/pressable.dart';

/// Saved foods are searched on every keystroke; the databases wait for a pause in typing.
const _remoteDelay = Duration(milliseconds: 500);
const _remoteMinChars = 3;

/// "Search foods": the household library first, most used first, then USDA and Open Food Facts
/// results under their own heading once typing pauses. Tapping a food hands it to [onPick].
class FoodSearchBox extends ConsumerStatefulWidget {
  const FoodSearchBox({
    super.key,
    required this.onPick,
    this.enabled = true,
    this.autofocus = false,
    this.browseOnFocus = true,
    this.remoteDelay = _remoteDelay,
  });

  final ValueChanged<SavedFood> onPick;
  final bool enabled;

  /// Puts the cursor in the field as soon as it appears.
  final bool autofocus;

  /// Lists the most used saved foods when the field is focused and still empty.
  final bool browseOnFocus;

  final Duration remoteDelay;

  @override
  ConsumerState<FoodSearchBox> createState() => _FoodSearchBoxState();
}

class _FoodSearchBoxState extends ConsumerState<FoodSearchBox> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  Timer? _remoteTimer;
  int _savedGeneration = 0;
  int _remoteGeneration = 0;
  List<SavedFood> _saved = const [];
  List<SavedFood> _candidates = const [];
  bool _remotePending = false;
  bool _remoteDone = false;
  bool _failed = false;
  bool _remoteFailed = false;

  String get _query => _text.text.trim();

  bool get _wantsRemote => _query.length >= _remoteMinChars;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus && widget.browseOnFocus && _saved.isEmpty && _query.isEmpty) {
        _searchSaved();
      }
      setState(() {});
    });
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _remoteTimer?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String _) {
    _remoteTimer?.cancel();
    _remoteGeneration++;
    setState(() {
      _candidates = const [];
      _remoteDone = false;
      _remoteFailed = false;
      _remotePending = _wantsRemote;
    });
    if (_query.isEmpty && !widget.browseOnFocus) {
      _savedGeneration++;
      setState(() => _saved = const []);
    } else {
      _searchSaved();
    }
    if (_wantsRemote) _remoteTimer = Timer(widget.remoteDelay, _searchDatabases);
  }

  Future<void> _searchSaved() async {
    final generation = ++_savedGeneration;
    try {
      final result = await ref.read(logActionsProvider).searchFoods(_query);
      if (!mounted || generation != _savedGeneration) return;
      setState(() {
        _saved = result.foods;
        _failed = false;
      });
    } on Object {
      if (!mounted || generation != _savedGeneration) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _searchDatabases() async {
    final generation = ++_remoteGeneration;
    final query = _query;
    try {
      final result = await ref.read(logActionsProvider).searchFoods(query, remote: true);
      if (!mounted || generation != _remoteGeneration) return;
      setState(() {
        _candidates = result.candidates;
        _remotePending = false;
        _remoteDone = true;
        _remoteFailed = false;
      });
    } on Object {
      if (!mounted || generation != _remoteGeneration) return;
      setState(() {
        _remotePending = false;
        _remoteDone = true;
        _remoteFailed = true;
      });
    }
  }

  void _pick(SavedFood food) {
    widget.onPick(food);
    _remoteTimer?.cancel();
    _savedGeneration++;
    _remoteGeneration++;
    _text.clear();
    _focus.unfocus();
    setState(() {
      _saved = const [];
      _candidates = const [];
      _remotePending = false;
      _remoteDone = false;
    });
  }

  Widget _note(String text, {bool danger = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: AppText.label.copyWith(
        color: danger ? kDangerText : kInkSecondary,
        fontWeight: danger ? FontWeight.w700 : null,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final open = _focus.hasFocus || _query.isNotEmpty;
    final showHeading = _remotePending || _remoteDone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _text,
          hint: 'Search foods',
          semanticLabel: 'Search foods',
          onChanged: _typed,
          focusNode: _focus,
        ),
        if (open) ...[
          const SizedBox(height: 8),
          for (final food in _saved.take(6))
            FoodTile(food: food, enabled: widget.enabled, onTap: () => _pick(food)),
          if (_saved.isEmpty && !_failed && (widget.browseOnFocus || _query.isNotEmpty))
            _note(_query.isEmpty ? 'Foods you save will show up here.' : 'Nothing saved matches.'),
          if (_failed) _note('Could not search right now.', danger: true),
          if (showHeading) ...[const SizedBox(height: 8), const FieldLabel('From the databases')],
          if (_remotePending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: kInkSecondary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Searching USDA and Open Food Facts',
                      style: AppText.label.copyWith(color: kInkSecondary),
                    ),
                  ),
                ],
              ),
            ),
          if (_remoteFailed) _note('Could not search the databases right now.', danger: true),
          for (final food in _candidates)
            FoodTile(
              food: food,
              enabled: widget.enabled,
              onTap: () => _pick(food),
              reserveThumbnail: _candidates.any((c) => c.imageUrl != null),
            ),
          if (_remoteDone && !_remoteFailed && _candidates.isEmpty)
            _note('Nothing found in the databases.'),
        ],
      ],
    );
  }
}

const _thumbSize = 44.0;
const _thumbGap = 10.0;

Future<void> _openSource(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// One food in a search list. A food with a photo shows it; [reserveThumbnail] keeps its siblings
/// without one aligned with it.
class FoodTile extends StatelessWidget {
  const FoodTile({
    super.key,
    required this.food,
    required this.enabled,
    required this.onTap,
    this.reserveThumbnail = false,
    this.onOpenSource = _openSource,
  });

  final SavedFood food;
  final bool enabled;
  final VoidCallback onTap;
  final bool reserveThumbnail;
  final ValueChanged<String> onOpenSource;

  @override
  Widget build(BuildContext context) {
    final imageUrl = food.imageUrl;
    final sourceUrl = food.sourceUrl;
    final showThumb = imageUrl != null || reserveThumbnail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          enabled: enabled,
          label:
              '${food.title}, ${food.servingText}, ${food.kcal} kilocalories, ${food.source.chip}',
          excludeSemantics: true,
          onTap: enabled ? onTap : null,
          child: Pressable(
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: EdgeInsets.only(top: 6, bottom: sourceUrl == null ? 6 : 0),
                child: Row(
                  children: [
                    if (showThumb) ...[
                      FoodThumbnail(url: imageUrl),
                      const SizedBox(width: _thumbGap),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            food.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${food.servingText} · ${food.kcal.formatted} kcal · ${food.source.chip}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(color: kInkSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.add_circle_outline_rounded, color: kInkSecondary),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (sourceUrl != null)
          Padding(
            padding: EdgeInsets.only(left: showThumb ? _thumbSize + _thumbGap : 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                link: true,
                label: 'Open Food Facts page for ${food.title}',
                excludeSemantics: true,
                onTap: () => onOpenSource(sourceUrl),
                child: Pressable(
                  onTap: () => onOpenSource(sourceUrl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open Food Facts',
                          style: AppText.caption.copyWith(
                            color: kInkSecondary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.open_in_new_rounded, size: 12, color: kInkSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A rounded product photo that fades in, with the food icon behind it while it loads and in
/// its place when the photo is missing or fails.
class FoodThumbnail extends StatelessWidget {
  const FoodThumbnail({super.key, required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: kBorder,
      alignment: Alignment.center,
      child: const Icon(Icons.restaurant_rounded, size: 20, color: kInkSecondary),
    );
    final cacheWidth = (_thumbSize * MediaQuery.devicePixelRatioOf(context)).round();
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: _thumbSize,
          height: _thumbSize,
          child: url == null
              ? placeholder
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    placeholder,
                    Image.network(
                      url!,
                      fit: BoxFit.cover,
                      cacheWidth: cacheWidth,
                      gaplessPlayback: true,
                      frameBuilder: (context, child, frame, sync) => sync
                          ? child
                          : AnimatedOpacity(
                              opacity: frame == null ? 0 : 1,
                              duration: const Duration(milliseconds: 200),
                              child: child,
                            ),
                      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
