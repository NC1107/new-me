import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every tap target on screen smaller than [min] points in either direction, described by its
/// text and size, so a test can assert that no control on a page is under 44pt. A target is a
/// gesture detector, ink well or button with a tap handler, measured by its laid out box.
List<String> smallTargets(WidgetTester tester, {double min = 44}) {
  final found = <String>[];
  void visit(Element element) {
    final widget = element.widget;
    final tappable =
        (widget is GestureDetector && (widget.onTap != null || widget.onTapDown != null)) ||
        (widget is InkWell && widget.onTap != null) ||
        (widget is IconButton && widget.onPressed != null);
    if (tappable) {
      final box = element.renderObject;
      if (box is RenderBox && box.hasSize && box.attached) {
        final size = box.size;
        if (size.width < min - 0.5 || size.height < min - 0.5) {
          final texts = <String>[];
          void collect(Element e) {
            final w = e.widget;
            if (w is Text && w.data != null) texts.add(w.data!);
            if (w is Icon && w.icon != null) texts.add('icon ${w.icon!.codePoint}');
            e.visitChildren(collect);
          }

          element.visitChildren(collect);
          found.add('[${texts.join('|')}] ${size.width.round()}x${size.height.round()}');
        }
      }
    }
    element.visitChildren(visit);
  }

  tester.binding.rootElement?.visitChildren(visit);
  return found;
}
