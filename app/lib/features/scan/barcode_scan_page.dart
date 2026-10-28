import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/models.dart';
import '../../state/log_actions.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import 'barcode_scanner.dart';

/// How the scanner page ended.
sealed class ScanOutcome {
  const ScanOutcome();
}

/// The barcode matched a food, ready to pick like a search result.
class ScanFound extends ScanOutcome {
  const ScanFound(this.food);
  final SavedFood food;
}

class ScanSearchInstead extends ScanOutcome {
  const ScanSearchInstead();
}

class ScanEnterByHand extends ScanOutcome {
  const ScanEnterByHand();
}

/// Opens the scanner and resolves with what the person chose, or null when they closed it.
Future<ScanOutcome?> scanBarcode(BuildContext context, {bool canEnterByHand = true}) =>
    pushPage<ScanOutcome>(context, BarcodeScanPage(canEnterByHand: canEnterByHand));

/// GS1 check: 8 to 14 digits whose last digit balances the weighted sum of the others. Misreads
/// fail it, so they are ignored instead of costing a lookup.
bool isValidBarcode(String code) {
  if (!RegExp(r'^\d{8,14}$').hasMatch(code)) return false;
  var sum = 0;
  for (var i = code.length - 2, w = 3; i >= 0; i--, w = 4 - w) {
    sum += int.parse(code[i]) * w;
  }
  return (10 - sum % 10) % 10 == int.parse(code[code.length - 1]);
}

Future<void> openAppSettings() async {
  await launchUrl(Uri.parse('app-settings:'), mode: LaunchMode.externalApplication);
}

enum _Phase { scanning, looking, notFound, failed }

class BarcodeScanPage extends ConsumerStatefulWidget {
  const BarcodeScanPage({
    super.key,
    this.onOpenSettings = openAppSettings,
    this.canEnterByHand = true,
  });

  final Future<void> Function() onOpenSettings;

  /// False where the caller has no form to type into, so the choice is not offered.
  final bool canEnterByHand;

  @override
  ConsumerState<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends ConsumerState<BarcodeScanPage> with WidgetsBindingObserver {
  late final ScannerSession _session = ref.read(barcodeScannerProvider).open();
  StreamSubscription<String>? _codes;
  _Phase _phase = _Phase.scanning;
  String? _code;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _codes = _session.codes.listen(_detected);
    unawaited(_session.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_codes?.cancel());
    unawaited(_session.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from Settings after allowing the camera.
    if (state == AppLifecycleState.resumed && _session.status.value == ScannerStatus.denied) {
      unawaited(_session.start());
    }
  }

  void _detected(String code) {
    if (_phase != _Phase.scanning || !isValidBarcode(code)) return;
    HapticFeedback.mediumImpact();
    unawaited(_lookup(code));
  }

  Future<void> _lookup(String code) async {
    setState(() {
      _phase = _Phase.looking;
      _code = code;
      _error = null;
    });
    try {
      final food = await ref.read(logActionsProvider).foodByBarcode(code);
      if (!mounted) return;
      if (food != null) {
        Navigator.of(context).pop(ScanFound(food));
      } else {
        setState(() => _phase = _Phase.notFound);
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = errorCopy(e);
      });
    }
  }

  void _finish(ScanOutcome outcome) => Navigator.of(context).pop(outcome);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<ScannerStatus>(
        valueListenable: _session.status,
        builder: (context, status, _) {
          final blocked = status == ScannerStatus.denied || status == ScannerStatus.failed;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (!blocked) _session.buildPreview(),
              if (!blocked) const _FramingGuide(),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _RoundButton(
                            icon: Icons.close_rounded,
                            label: 'Close scanner',
                            onTap: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                          if (!blocked) _TorchButton(session: _session),
                        ],
                      ),
                      const Spacer(),
                      _Panel(child: blocked ? _blockedBody(status) : _scanBody()),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _scanBody() {
    switch (_phase) {
      case _Phase.scanning:
        return const _Message(title: 'Scan a barcode', body: 'Hold it inside the frame.');
      case _Phase.looking:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text('Looking up $_code', style: AppText.body.copyWith(color: Colors.white)),
            ),
          ],
        );
      case _Phase.notFound:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Message(
              title: 'No match for that barcode',
              body: 'Open Food Facts does not have it yet.',
            ),
            const SizedBox(height: 12),
            ..._choices(),
          ],
        );
      case _Phase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Message(title: 'Could not look that up', body: _error ?? 'Try again.'),
            const SizedBox(height: 12),
            ChunkyButton(label: 'Try again', onPressed: () => _lookup(_code!)),
            const SizedBox(height: 8),
            ..._choices(),
          ],
        );
    }
  }

  List<Widget> _choices() => [
    ChunkyButton(label: 'Scan another', onPressed: _scanAnother),
    const SizedBox(height: 8),
    ChunkyButton.secondary(
      label: 'Search instead',
      onPressed: () => _finish(const ScanSearchInstead()),
    ),
    if (widget.canEnterByHand) ...[
      const SizedBox(height: 8),
      ChunkyButton.secondary(
        label: 'Enter by hand',
        onPressed: () => _finish(const ScanEnterByHand()),
      ),
    ],
  ];

  void _scanAnother() => setState(() {
    _phase = _Phase.scanning;
    _code = null;
    _error = null;
  });

  Widget _blockedBody(ScannerStatus status) {
    final denied = status == ScannerStatus.denied;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Message(
          title: denied ? 'Camera access is off' : 'The camera is not available',
          body: denied
              ? 'Allow the camera for New Me in Settings to scan barcodes.'
              : 'Close anything else using the camera and try again.',
        ),
        const SizedBox(height: 12),
        if (denied) ...[
          ChunkyButton(label: 'Open Settings', onPressed: widget.onOpenSettings),
          const SizedBox(height: 8),
        ],
        ChunkyButton(
          label: 'Search instead',
          kind: denied ? ChunkyKind.secondary : ChunkyKind.primary,
          onPressed: () => _finish(const ScanSearchInstead()),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          body,
          textAlign: TextAlign.center,
          style: AppText.label.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
          ),
          child: AnimatedSize(duration: kMotionDuration, child: child),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.session});

  final ScannerSession session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScannerTorch>(
      valueListenable: session.torch,
      builder: (context, torch, _) {
        if (torch == ScannerTorch.unavailable) return const SizedBox(width: 48, height: 48);
        final on = torch == ScannerTorch.on;
        return _RoundButton(
          icon: on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          label: on ? 'Turn torch off' : 'Turn torch on',
          onTap: () {
            HapticFeedback.selectionClick();
            unawaited(session.toggleTorch());
          },
        );
      },
    );
  }
}

/// Four corner brackets around where the barcode should sit.
class _FramingGuide extends StatelessWidget {
  const _FramingGuide();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: ExcludeSemantics(
        child: Center(
          child: SizedBox(width: 280, height: 170, child: CustomPaint(painter: _CornerPainter())),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const arm = 28.0;
    const r = 12.0;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, arm)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(arm, 0)
      ..moveTo(w - arm, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, arm)
      ..moveTo(w, h - arm)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(w - arm, h)
      ..moveTo(arm, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, h - arm);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => false;
}
