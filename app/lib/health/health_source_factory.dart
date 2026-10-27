import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'health_source.dart';
import 'healthkit_source_stub.dart' if (dart.library.io) 'healthkit_source.dart' as platform;

/// Web has no HealthKit, and importing package:health there would not compile.
HealthSource createHealthSource() => platform.createPlatformHealthSource();

final healthSourceProvider = Provider<HealthSource>((ref) => createHealthSource());
