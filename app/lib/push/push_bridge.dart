import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kPushChannel = MethodChannel('newme/push');

/// The native side of remote notifications on iOS: asks APNs for a device token and reports
/// taps on a delivered push. Everything is a no-op on web and on platforms without the plugin.
class PushBridge {
  const PushBridge([this._channel = kPushChannel]);

  final MethodChannel _channel;

  /// Starts listening for what the native side reports. [onToken] gets the lowercase hex APNs
  /// token, [onTap] the `kind` of a tapped push.
  void listen({
    required ValueChanged<String> onToken,
    required ValueChanged<String> onTap,
    ValueChanged<String>? onError,
  }) {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      final arg = call.arguments;
      switch (call.method) {
        case 'token' when arg is String && arg.isNotEmpty:
          onToken(arg);
          return true;
        case 'tapped' when arg is String:
          onTap(arg);
          return true;
        case 'error':
          onError?.call('$arg');
          return true;
      }
      return null;
    });
  }

  void stopListening() {
    if (kIsWeb) return;
    _channel.setMethodCallHandler(null);
  }

  /// Asks iOS for a token. Only call once notification permission is granted; the token arrives
  /// through [listen]'s onToken, and again whenever iOS changes it.
  Future<void> register() => _invoke<void>('register');

  Future<void> unregister() => _invoke<void>('unregister');

  /// The kind of a push that was tapped before Dart was listening (a cold start), once.
  Future<String?> takeLaunchTap() => _invoke<String>('takeTap');

  Future<T?> _invoke<T>(String method) async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on Object catch (e) {
      debugPrint('[NEWME] push $method failed: $e');
      return null;
    }
  }
}

final pushBridgeProvider = Provider<PushBridge>((ref) => const PushBridge());
