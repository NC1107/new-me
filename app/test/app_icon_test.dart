import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/widgets/mascot.dart';

/// The app icon is the mascot on a soft green. Regenerate every icon file with
/// `NEWME_WRITE_ICONS=1 flutter test test/app_icon_test.dart`; without the variable the test
/// checks that the committed files still match what the mascot draws.
const _targets = <String, int>{
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-1024.png': 1024,
  'web/icons/Icon-512.png': 512,
  'web/icons/Icon-192.png': 192,
  'web/icons/Icon-maskable-512.png': 512,
  'web/icons/Icon-maskable-192.png': 192,
  'web/favicon.png': 32,
};

// The mascot's ring is 84 of its 100 units wide; this scale makes it 62% of the icon, which keeps
// it inside iOS's rounded mask and the 80% maskable safe zone with room to breathe.
const _mascotScale = 0.74;
// The ring's centre sits at 56 of the mascot's 100 units, not 50, because of its lip.
const _ringCentre = 0.56;

Future<Uint8List> _renderRgba(WidgetTester tester, int px) async {
  Mascot.idleMotion = false;
  final key = GlobalKey();
  tester.view
    ..physicalSize = Size(px.toDouble(), px.toDouble())
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final size = px * _mascotScale;
  final palette = accentById('green');
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: Size(px.toDouble(), px.toDouble())),
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: palette.tint,
            child: Stack(
              children: [
                Positioned(
                  left: (px - size) / 2,
                  top: px / 2 - _ringCentre * size,
                  child: Mascot(size: size, state: MascotState.happy, palette: palette),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final data = await tester.runAsync(() async {
    final image = await boundary.toImage();
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return data!.buffer.asUint8List();
}

/// An 8-bit RGB PNG, so the file has no alpha channel (the App Store rejects icons with one).
Uint8List _encodeRgbPng(Uint8List rgba, int px) {
  final raw = BytesBuilder();
  for (var y = 0; y < px; y++) {
    raw.addByte(0);
    for (var x = 0; x < px; x++) {
      final i = (y * px + x) * 4;
      raw.add([rgba[i], rgba[i + 1], rgba[i + 2]]);
    }
  }
  final header = ByteData(13)
    ..setUint32(0, px)
    ..setUint32(4, px)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  final out = BytesBuilder()..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> body) {
    final length = ByteData(4)..setUint32(0, body.length);
    final typed = [...type.codeUnits, ...body];
    final crc = ByteData(4)..setUint32(0, _crc32(typed));
    out
      ..add(length.buffer.asUint8List())
      ..add(typed)
      ..add(crc.buffer.asUint8List());
  }

  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder(level: 9).convert(raw.toBytes()));
  chunk('IEND', const []);
  return out.toBytes();
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

void main() {
  final write = Platform.environment['NEWME_WRITE_ICONS'] == '1';

  for (final entry in _targets.entries) {
    testWidgets('${entry.key} is the opaque mascot icon', (tester) async {
      final px = entry.value;
      final rgba = await _renderRgba(tester, px);
      final file = File(entry.key);
      if (write) file.writeAsBytesSync(_encodeRgbPng(rgba, px));

      final bytes = file.readAsBytesSync();
      final header = ByteData.sublistView(bytes);
      expect(header.getUint32(16), px, reason: 'width');
      expect(header.getUint32(20), px, reason: 'height');
      expect(bytes[25], 2, reason: 'PNG colour type 2 is RGB with no alpha channel');

      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        final committed = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        var diff = 0;
        for (var i = 0; i < rgba.length; i++) {
          diff += (rgba[i] - committed.getUint8(i)).abs();
        }
        expect(diff / rgba.length, lessThan(1.0), reason: 'committed icon matches the mascot');
      });
    });
  }
}
