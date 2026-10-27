import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

const kBackgroundChannel = MethodChannel('newme/background');

/// Hands the native iOS side what it needs to push Health totals while the app is not running.
class BackgroundHealthBridge {
  const BackgroundHealthBridge([this._channel = kBackgroundChannel]);

  final MethodChannel _channel;

  Future<void> configure({required String baseUrl, required String token}) => _invoke('configure', {
    'baseUrl': baseUrl,
    'token': token,
    'appKey': kAppKey,
    'clientVersion': kClientVersion,
  });

  Future<void> clear() => _invoke('clear');

  /// Registers the native observers; call once Health access has been asked for.
  Future<void> enable() => _invoke('enable');

  /// Best effort: web and non-iOS builds have no native side, and a failure here must never
  /// break the foreground sync.
  Future<void> _invoke(String method, [Map<String, String>? args]) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No native handler on this platform.
    } on Object catch (e) {
      debugPrint('[NEWME] background health $method failed: $e');
    }
  }
}

final backgroundHealthBridgeProvider = Provider<BackgroundHealthBridge>(
  (ref) => const BackgroundHealthBridge(),
);
