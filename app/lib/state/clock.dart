import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every time-dependent rule reads the clock through this, so tests can move time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
