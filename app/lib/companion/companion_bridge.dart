import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kCompanionChannel = MethodChannel('newme/widgets');

/// Hands the iOS side the snapshot for the Home and Lock Screen widgets and the Watch.
class CompanionBridge {
  const CompanionBridge([this._channel = kCompanionChannel]);

  final MethodChannel _channel;

  Future<void> update(String snapshotJson) => _invoke('update', snapshotJson);

  /// Signs the widgets and the Watch out.
  Future<void> clear() => _invoke('clear');

  /// Called when the Watch changed today through the phone, so Today should be fetched again.
  void onRemoteChange(VoidCallback? handler) {
    if (kIsWeb) return;
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method == 'remoteChange') handler();
            },
    );
  }

  /// Best effort: web has no native side, and a widget failing must never break the app.
  Future<void> _invoke(String method, [Object? args]) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No native handler on this platform.
    } on Object catch (e) {
      debugPrint('[NEWME] companion $method failed: $e');
    }
  }
}

final companionBridgeProvider = Provider<CompanionBridge>((ref) => const CompanionBridge());
