import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// The device's IANA zone, or null when it cannot be read.
final deviceTimezoneProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } on Object catch (e) {
      debugPrint('[NEWME] timezone unavailable: $e');
      return null;
    }
  },
);
