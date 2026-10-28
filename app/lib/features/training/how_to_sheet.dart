import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/models.dart';
import '../../state/training.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/skeletons.dart';

/// Opens the how-to of one exercise: start and end photos, numbered steps, form cues and the
/// muscles it works. Looks the exercise up in the catalog, so a session card needs only its key.
Future<void> showHowTo(BuildContext context, {required String exerciseKey, String? name}) =>
    showAppSheet<void>(
      context,
      builder: (_) => HowToSheet(exerciseKey: exerciseKey, name: name),
    );

/// The small "How to" button on an exercise card or page. At least 44 points square.
class HowToButton extends StatelessWidget {
  const HowToButton({super.key, required this.exerciseKey, required this.name});

  final String exerciseKey;
  final String name;

  @override
  Widget build(BuildContext context) {
    void open() => showHowTo(context, exerciseKey: exerciseKey, name: name);
    // Its own node, so VoiceOver reaches it apart from the row it sits in.
    return Semantics(
      container: true,
      button: true,
      label: 'How to do $name',
      excludeSemantics: true,
      onTap: open,
      child: InkResponse(
        onTap: open,
        radius: 24,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.info_outline_rounded, color: kInkSecondary, size: 24),
        ),
      ),
    );
  }
}

class HowToSheet extends ConsumerWidget {
  const HowToSheet({super.key, required this.exerciseKey, this.name});

  final String exerciseKey;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercise = ref.watch(exercisesProvider.select((v) => v.value?.data.byKey(exerciseKey)));
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(exercise?.name ?? name ?? 'How to', style: AppText.title),
            if (exercise == null) ...[
              const SizedBox(height: 16),
              const SkeletonBlock(height: 160, radius: kRadiusCard),
            ] else
              ..._content(context, exercise),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, Exercise e) {
    final muscles = e.primaryMuscles.map((m) => muscleLabel(m).toLowerCase()).join(', ');
    return [
      if (muscles.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('Works $muscles', style: AppText.caption.copyWith(color: kInkSecondary)),
      ],
      const SizedBox(height: 16),
      HowToDetails(exercise: e),
    ];
  }
}

/// Where the cautions on a yoga pose come from.
const kPoseCautionSource =
    'NCCIH, "Yoga: What You Need To Know"; Cramer et al., PLoS One 2013;8(10):e75515. '
    'Not medical advice.';

/// Photos, numbered steps and form cues of one exercise, in the how-to sheet and on the
/// exercise's own page.
class HowToDetails extends StatelessWidget {
  const HowToDetails({super.key, required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    final photos = e.imageUrls.isNotEmpty;
    final pose = e.pose;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pose != null && (pose.effect.isNotEmpty || pose.holdNote.isNotEmpty)) ...[
          if (pose.effect.isNotEmpty) Text(pose.effect, style: AppText.body),
          if (pose.holdNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(pose.holdNote, style: AppText.label.copyWith(color: kInkSecondary)),
          ],
          const SizedBox(height: 16),
        ],
        if (photos) HowToPhotosOf(exercise: e),
        if (e.steps.isNotEmpty) ...[
          if (photos) const SizedBox(height: 20),
          const Text('Steps', style: AppText.headline),
          const SizedBox(height: 8),
          for (final (i, step) in e.steps.indexed) HowToStep(number: i + 1, text: step),
        ],
        if (e.cues.isNotEmpty) ...[
          if (photos || e.steps.isNotEmpty) const SizedBox(height: 16),
          const Text('Form cues', style: AppText.headline),
          const SizedBox(height: 8),
          for (final cue in e.cues) HowToCue(text: cue),
        ],
        if (pose != null && pose.cautions.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Take care', style: AppText.headline),
          const SizedBox(height: 8),
          for (final caution in pose.cautions) HowToCue(text: caution),
          Text(kPoseCautionSource, style: AppText.caption.copyWith(color: kInkMuted)),
        ],
        if (!e.hasHowTo)
          Text(
            e.custom
                ? 'Your own exercises have no steps or photos.'
                : 'No steps for this exercise yet.',
            style: AppText.body.copyWith(color: kInkSecondary),
          ),
      ],
    );
  }
}

/// The photos of one exercise. A yoga pose shows each photo whole with its credit underneath,
/// as the Creative Commons licenses it was published under require; other exercises show their
/// start and end photos.
class HowToPhotosOf extends StatelessWidget {
  const HowToPhotosOf({super.key, required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    final credits = e.pose?.imageCredits ?? const <ImageCredit>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HowToPhotos(urls: e.imageUrls, name: e.name, whole: e.yoga),
        for (final credit in credits) PhotoCredit(credit: credit),
      ],
    );
  }
}

/// "Photo: author, license", a link to the photo's file page.
class PhotoCredit extends StatelessWidget {
  const PhotoCredit({super.key, required this.credit});

  final ImageCredit credit;

  Future<void> _open() async {
    final uri = Uri.tryParse(credit.sourceUrl);
    if (uri == null || uri.scheme != 'https') return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: '${credit.label}. Opens the photo page',
      excludeSemantics: true,
      onTap: _open,
      child: InkWell(
        onTap: _open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              credit.label,
              style: AppText.caption.copyWith(
                color: kInkSecondary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The start and end photos side by side, each labelled, so there is nothing to swipe. With
/// [whole] each photo is shown uncropped and unlabelled, since a pose has one photo.
class HowToPhotos extends StatelessWidget {
  const HowToPhotos({super.key, required this.urls, required this.name, this.whole = false});

  final List<String> urls;
  final String name;
  final bool whole;

  @override
  Widget build(BuildContext context) {
    const labels = ['Start', 'End'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, url) in urls.take(2).indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: _Photo(url: url, label: whole ? null : labels[i], name: name, whole: whole),
          ),
        ],
      ],
    );
  }
}

class _Photo extends ConsumerWidget {
  const _Photo({required this.url, required this.label, required this.name, required this.whole});

  final String url;
  final String? label;
  final String name;
  final bool whole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(exerciseImageProvider(url));
    final instant = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      image: true,
      label: label == null ? name : '$name, $label position',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The border is drawn over the photo, as every card in the app is outlined.
          Container(
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadiusField),
              border: Border.all(color: kBorder, width: kBorderWidth),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRadiusField),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: ColoredBox(
                  color: whole ? Colors.white : kSunken,
                  child: switch (image) {
                    AsyncValue(:final value?) => Image.memory(
                      value,
                      fit: whole ? BoxFit.contain : BoxFit.cover,
                      gaplessPlayback: true,
                      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
                        opacity: frame == null && !sync ? 0 : 1,
                        duration: instant ? Duration.zero : kMotionDuration,
                        child: child,
                      ),
                      errorBuilder: (_, _, _) => const _PhotoPlaceholder(),
                    ),
                    AsyncValue(hasError: true) => const _PhotoPlaceholder(),
                    _ => const SizedBox.shrink(),
                  },
                ),
              ),
            ),
          ),
          if (label case final text?) ...[
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: kInkSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) =>
      const Center(child: Icon(Icons.image_not_supported_outlined, color: kInkMuted));
}

class HowToStep extends StatelessWidget {
  const HowToStep({super.key, required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        container: true,
        label: 'Step $number. $text',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: accent.tint, shape: BoxShape.circle),
              child: Text('$number', style: AppText.tabular(AppText.label.copyWith(color: kInk))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(text, style: AppText.body),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HowToCue extends StatelessWidget {
  const HowToCue({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle_outline_rounded, size: 20, color: accent.lip),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: AppText.body.copyWith(color: kInkSecondary)),
          ),
        ],
      ),
    );
  }
}
