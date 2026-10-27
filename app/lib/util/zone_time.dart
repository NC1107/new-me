import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _loaded = false;

/// [t] as wall-clock time in the IANA [zone]; the device zone when the name is unknown or absent.
/// The server stores instants, and a night's bed time must read the way the person lived it.
DateTime inZone(DateTime t, String? zone) {
  if (zone == null || zone.isEmpty) return t.toLocal();
  try {
    if (!_loaded) {
      tzdata.initializeTimeZones();
      _loaded = true;
    }
    return tz.TZDateTime.from(t, tz.getLocation(zone));
  } on Object {
    return t.toLocal();
  }
}
