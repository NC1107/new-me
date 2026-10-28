import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/me/my_foods_page.dart';
import 'package:newme/features/scan/barcode_scan_page.dart';
import 'package:newme/features/scan/barcode_scanner.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

const _nutella = '3017620422003';
const _unknown = '96385074';

class FakeSession implements ScannerSession {
  FakeSession(this.initial);

  final ScannerStatus initial;
  final codeController = StreamController<String>.broadcast();
  @override
  final ValueNotifier<ScannerStatus> status = ValueNotifier(ScannerStatus.starting);
  @override
  final ValueNotifier<ScannerTorch> torch = ValueNotifier(ScannerTorch.off);
  int starts = 0;
  int toggles = 0;
  bool disposed = false;

  @override
  Stream<String> get codes => codeController.stream;

  @override
  Widget buildPreview() => const SizedBox.expand(key: Key('fake-preview'));

  @override
  Future<void> start() async {
    starts++;
    status.value = initial;
  }

  @override
  Future<void> toggleTorch() async {
    toggles++;
    torch.value = torch.value == ScannerTorch.on ? ScannerTorch.off : ScannerTorch.on;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await codeController.close();
  }
}

class FakeScanner implements BarcodeScanner {
  FakeScanner({this.available = true, this.initial = ScannerStatus.running});

  @override
  final bool available;
  final ScannerStatus initial;
  final sessions = <FakeSession>[];

  FakeSession get session => sessions.last;

  @override
  ScannerSession open() {
    final s = FakeSession(initial);
    sessions.add(s);
    return s;
  }
}

const _hazelnut = {
  'id': null,
  'saved': false,
  'name': 'Hazelnut spread',
  'brand': 'Ferrero',
  'servingText': '15 g',
  'servingGrams': 15,
  'kcal': 81,
  'protein': 0.9,
  'carbs': 8.3,
  'fat': 4.6,
  'source': 'openfoodfacts',
  'sourceId': _nutella,
  'servings': <Object>[],
  'imageUrl': null,
  'sourceUrl': 'https://world.openfoodfacts.org/product/$_nutella',
};

final _savedHazelnut = {..._hazelnut, 'id': 5};

StubAdapter _server({Duration? delay}) => fullServer()
  ..on('GET /api/foods', const StubResponse(200, {'foods': [], 'candidates': []}))
  ..on('POST /api/logs', StubResponse(201, logResultJson()))
  ..routes['GET /api/foods/barcode/$_nutella'] = (_) async {
    if (delay != null) await Future<void>.delayed(delay);
    return const StubResponse(200, _hazelnut);
  }
  ..on(
    'GET /api/foods/barcode/$_unknown',
    const StubResponse(404, {'error': 'no food found for that barcode', 'code': 'not_found'}),
  );

Finder get _scanButton => find.bySemanticsLabel('Scan a barcode');

Future<void> _openScanner(TestApp app) async {
  await app.tap(_scanButton);
  expect(find.byKey(const Key('fake-preview')), findsOneWidget);
}

Future<void> _emit(TestApp app, FakeScanner scanner, String code) async {
  scanner.session.codeController.add(code);
  await app.settle();
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('the Scan button is hidden when no camera can be used', (tester) async {
    final scanner = FakeScanner(available: false);
    final app = TestApp(tester, _server(), surfaceHeight: 2400);
    await app.pump(
      const Scaffold(body: LogSheet(kind: LogKind.meal)),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );
    expect(_scanButton, findsNothing);
    expect(find.text('Search foods'), findsOneWidget);
  });

  testWidgets('log sheet: a scanned barcode selects the food for logging, once', (tester) async {
    final scanner = FakeScanner();
    final server = _server(delay: const Duration(milliseconds: 200));
    final app = TestApp(tester, server, surfaceHeight: 2400);
    await app.pump(
      const Scaffold(body: LogSheet(kind: LogKind.meal)),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );
    await _openScanner(app);

    scanner.session.codeController
      ..add(_nutella)
      ..add(_nutella);
    await app.settle(20);

    expect(server.to('GET /api/foods/barcode/$_nutella'), hasLength(1));
    expect(scanner.session.disposed, isTrue);
    expect(find.byKey(const Key('fake-preview')), findsNothing);
    expect(fieldWith('Hazelnut spread'), findsOneWidget);
    expect(server.to('POST /api/logs'), isEmpty);
  });

  testWidgets('a misread barcode is ignored without a lookup', (tester) async {
    final scanner = FakeScanner();
    final server = _server();
    final app = TestApp(tester, server, surfaceHeight: 2400);
    await app.pump(
      const Scaffold(body: LogSheet(kind: LogKind.meal)),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );
    await _openScanner(app);
    await _emit(app, scanner, '3017620422004');
    await _emit(app, scanner, '12345');

    expect(server.requests.where((r) => r.path.contains('/barcode/')), isEmpty);
    expect(find.text('Scan a barcode'), findsOneWidget);
  });

  testWidgets('log sheet: not found offers Search instead, which focuses the search field', (
    tester,
  ) async {
    final scanner = FakeScanner();
    final app = TestApp(tester, _server(), surfaceHeight: 2400);
    await app.pump(
      const Scaffold(body: LogSheet(kind: LogKind.meal)),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );
    await _openScanner(app);
    await _emit(app, scanner, _unknown);

    expect(find.text('No match for that barcode'), findsOneWidget);
    await app.tap(find.text('SEARCH INSTEAD'));

    expect(find.byKey(const Key('fake-preview')), findsNothing);
    final search = find.ancestor(of: find.text('Search foods'), matching: find.byType(TextField));
    expect(tester.widget<TextField>(search).focusNode?.hasFocus, isTrue);
  });

  testWidgets('log sheet: not found, Enter by hand focuses the name field', (tester) async {
    final scanner = FakeScanner();
    final app = TestApp(tester, _server(), surfaceHeight: 2400);
    await app.pump(
      const Scaffold(body: LogSheet(kind: LogKind.meal)),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );
    await _openScanner(app);
    await _emit(app, scanner, _unknown);
    await app.tap(find.text('ENTER BY HAND'));

    final name = find.ancestor(
      of: find.text('What was it? (optional)'),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(name).focusNode?.hasFocus, isTrue);
  });

  testWidgets('a failed lookup can be retried', (tester) async {
    final scanner = FakeScanner();
    final server = _server()
      ..on('GET /api/foods/barcode/$_nutella', const StubResponse.unreachable());
    final app = TestApp(tester, server, surfaceHeight: 2400);
    await app.pump(
      const Scaffold(body: LogSheet(kind: LogKind.meal)),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );
    await _openScanner(app);
    await _emit(app, scanner, _nutella);
    expect(find.text('Could not look that up'), findsOneWidget);

    server.on('GET /api/foods/barcode/$_nutella', const StubResponse(200, _hazelnut));
    await app.tap(find.text('TRY AGAIN'));
    expect(fieldWith('Hazelnut spread'), findsOneWidget);
  });

  testWidgets('My foods: a scanned barcode opens the prefilled save page', (tester) async {
    final scanner = FakeScanner();
    final server = _server()..on('POST /api/foods', StubResponse(201, _savedHazelnut));
    final app = TestApp(tester, server, surfaceHeight: 3200);
    await app.pump(
      const MyFoodsPage(),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );
    await _openScanner(app);
    await _emit(app, scanner, _nutella);

    expect(find.text('Save food'), findsOneWidget);
    expect(fieldWith('Hazelnut spread'), findsOneWidget);
    await app.tap(find.text('SAVE'));
    final body = app.body('POST /api/foods');
    expect((body['source'], body['sourceId']), ('openfoodfacts', _nutella));
  });

  testWidgets('My foods: not found, Enter by hand opens a blank food', (tester) async {
    final scanner = FakeScanner();
    final app = TestApp(tester, _server(), surfaceHeight: 3200);
    await app.pump(
      const MyFoodsPage(),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );
    await _openScanner(app);
    await _emit(app, scanner, _unknown);
    await app.tap(find.text('ENTER BY HAND'));

    expect(find.text('New food'), findsWidgets);
    expect(find.text('Save food'), findsNothing);
    expect(find.byKey(const Key('fake-preview')), findsNothing);
  });

  testWidgets('closing the scanner returns to the page and releases the camera', (tester) async {
    final scanner = FakeScanner();
    final app = TestApp(tester, _server(), surfaceHeight: 3200);
    await app.pump(
      const MyFoodsPage(),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );
    await _openScanner(app);
    await app.tap(find.bySemanticsLabel('Close scanner'));

    expect(scanner.session.disposed, isTrue);
    expect(find.text('My foods'), findsOneWidget);
  });

  testWidgets('the torch button toggles the torch and is hidden without one', (tester) async {
    final scanner = FakeScanner();
    final app = TestApp(tester, _server(), surfaceHeight: 3200);
    await app.pump(
      const MyFoodsPage(),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );
    await _openScanner(app);

    await app.tap(find.bySemanticsLabel('Turn torch on'));
    expect(scanner.session.toggles, 1);
    expect(find.bySemanticsLabel('Turn torch off'), findsOneWidget);

    scanner.session.torch.value = ScannerTorch.unavailable;
    await app.settle();
    expect(find.bySemanticsLabel('Turn torch off'), findsNothing);
    expect(find.bySemanticsLabel('Turn torch on'), findsNothing);
  });

  testWidgets('denied camera access explains itself, opens Settings and retries on return', (
    tester,
  ) async {
    final scanner = FakeScanner(initial: ScannerStatus.denied);
    var opened = 0;
    final app = TestApp(tester, _server(), surfaceHeight: 3200);
    await app.pump(
      BarcodeScanPage(onOpenSettings: () async => opened++),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );

    expect(find.text('Camera access is off'), findsOneWidget);
    expect(find.byKey(const Key('fake-preview')), findsNothing);
    await app.tap(find.text('OPEN SETTINGS'));
    expect(opened, 1);
    expect(find.text('SEARCH INSTEAD'), findsOneWidget);

    scanner.session.starts = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await app.settle();
    expect(scanner.session.starts, 1);
  });

  testWidgets('a camera that cannot start shows a message without a Settings link', (tester) async {
    final scanner = FakeScanner(initial: ScannerStatus.failed);
    final app = TestApp(tester, _server(), surfaceHeight: 3200);
    await app.pump(
      const BarcodeScanPage(),
      overrides: [barcodeScannerProvider.overrideWithValue(scanner)],
    );
    expect(find.text('The camera is not available'), findsOneWidget);
    expect(find.text('OPEN SETTINGS'), findsNothing);
  });

  test('isValidBarcode checks length, digits and the check digit', () {
    expect(isValidBarcode(_nutella), isTrue);
    expect(isValidBarcode('036000291452'), isTrue);
    expect(isValidBarcode(_unknown), isTrue);
    expect(isValidBarcode('3017620422004'), isFalse);
    expect(isValidBarcode('1234567'), isFalse);
    expect(isValidBarcode('30176204220a3'), isFalse);
  });
}
