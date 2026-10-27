import Flutter
import Foundation
import WatchConnectivity
import WidgetKit

/// Takes the snapshot Flutter builds whenever Today or the session changes and hands it to the
/// widgets (App Group file) and the Watch (application context).
final class CompanionBridge: NSObject, FlutterPlugin {
  static let shared = CompanionBridge()

  private var channel: FlutterMethodChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "newme/widgets", binaryMessenger: registrar.messenger())
    shared.channel = channel
    registrar.addMethodCallDelegate(shared, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "update":
      guard let json = call.arguments as? String, let data = json.data(using: .utf8),
        CompanionStore.decode(data) != nil
      else {
        result(FlutterError(code: "bad_args", message: "update takes the snapshot JSON", details: nil))
        return
      }
      publish(data)
      result(nil)
    case "clear":
      CompanionStore.clear()
      WidgetCenter.shared.reloadAllTimelines()
      WatchRelay.shared.send(Data())
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  fileprivate func publish(_ data: Data) {
    CompanionStore.save(data)
    WidgetCenter.shared.reloadAllTimelines()
    WatchRelay.shared.send(data)
  }

  /// Something outside the app changed today (a Watch tap through the phone), so Flutter
  /// should fetch Today again.
  fileprivate func notifyRemoteChange() {
    channel?.invokeMethod("remoteChange", arguments: nil)
  }
}

/// The phone's side of WatchConnectivity: keeps the Watch's snapshot current and runs the
/// Watch's actions when the Watch has no network of its own.
final class WatchRelay: NSObject, WCSessionDelegate {
  static let shared = WatchRelay()

  // Touched on the main queue only.
  private var pending: Data?

  func activate() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func send(_ snapshot: Data) {
    DispatchQueue.main.async {
      self.pending = snapshot
      self.flush()
    }
  }

  // The application context keeps only the latest value, so a snapshot that could not be sent
  // yet waits here for activation or for the Watch app to be installed.
  private func flush() {
    guard WCSession.isSupported(), let data = pending else { return }
    let session = WCSession.default
    guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
      return
    }
    do {
      try session.updateApplicationContext([CompanionRelay.snapshotKey: data])
      pending = nil
    } catch {
      NSLog("[NEWME] watch context update failed: \(error.localizedDescription)")
    }
  }

  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    DispatchQueue.main.async { self.flush() }
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    DispatchQueue.main.async {
      // A freshly installed Watch app has nothing yet; give it the newest snapshot on file.
      if self.pending == nil, session.isWatchAppInstalled, let data = CompanionStore.load(),
        let encoded = try? JSONEncoder().encode(data)
      {
        self.pending = encoded
      }
      self.flush()
    }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    // Switching to another Watch deactivates the session; the new Watch needs it active again.
    WCSession.default.activate()
  }

  func session(
    _ session: WCSession, didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    guard let payload = message[CompanionRelay.requestKey] as? Data,
      let request = try? JSONDecoder().decode(CompanionRequest.self, from: payload),
      let snapshot = CompanionStore.load(), let credentials = snapshot.session
    else {
      replyHandler([CompanionRelay.statusKey: 401])
      return
    }
    Task {
      do {
        let body = try await CompanionAPI(session: credentials).perform(request.action, date: request.date)
        replyHandler([CompanionRelay.statusKey: 200, CompanionRelay.bodyKey: body])
        DispatchQueue.main.async {
          if let latest = CompanionStore.load(), let data = try? JSONEncoder().encode(latest.applying(response: body)) {
            CompanionBridge.shared.publish(data)
          }
          CompanionBridge.shared.notifyRemoteChange()
        }
      } catch CompanionAPIError.status(let code) {
        replyHandler([CompanionRelay.statusKey: code])
      } catch {
        replyHandler([CompanionRelay.statusKey: 0])
      }
    }
  }
}
