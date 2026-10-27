import Foundation
import WatchConnectivity
import WidgetKit

/// The Watch's copy of Today. The phone sends it whenever Today changes; taps go straight to the
/// API when the Watch has a network, and through the phone when it does not.
@MainActor
final class WatchModel: NSObject, ObservableObject {
  @Published private(set) var snapshot: CompanionSnapshot?
  /// A short line under an action: what was saved, or why it was not.
  @Published var status: String?
  @Published private(set) var busy = false

  override init() {
    snapshot = CompanionStore.load()
    super.init()
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  var isCurrent: Bool { snapshot?.isCurrent() ?? false }

  func tap(_ item: CompanionSnapshot.HabitItem) {
    guard let snapshot = snapshot, snapshot.isCurrent() else { return }
    let (next, action) = CompanionSnapshot.tapped(item)
    store(snapshot.with(next))
    Task {
      do {
        let body = try await perform(action, date: snapshot.date)
        if let latest = self.snapshot { store(latest.applying(response: body)) }
      } catch {
        if let latest = self.snapshot, latest.habits.first(where: { $0.id == next.id }) == next {
          store(latest.with(item))
        }
        status = message(for: error)
      }
    }
  }

  /// Logs an activity such as push-ups; returns whether the server took it.
  func log(type: String, quantity: Int, unit: String, noun: String) async -> Bool {
    guard let snapshot = snapshot, quantity > 0 else { return false }
    busy = true
    defer { busy = false }
    let action = CompanionAction.logActivity(
      type: type, quantity: quantity, unit: unit, clientOpId: UUID().uuidString.lowercased())
    do {
      let body = try await perform(action, date: snapshot.date)
      if let latest = self.snapshot { store(latest.applying(response: body)) }
      status = "Saved \(quantity) \(noun)"
      return true
    } catch {
      status = message(for: error)
      return false
    }
  }

  private func perform(_ action: CompanionAction, date: String) async throws -> Data {
    guard let session = snapshot?.session else { throw CompanionAPIError.status(401) }
    do {
      return try await CompanionAPI(session: session).perform(action, date: date)
    } catch CompanionAPIError.offline {
      return try await relay(CompanionRequest(action: action, date: date))
    }
  }

  private func relay(_ request: CompanionRequest) async throws -> Data {
    let session = WCSession.default
    guard session.activationState == .activated, session.isReachable,
      let payload = try? JSONEncoder().encode(request)
    else { throw CompanionAPIError.offline }
    return try await withCheckedThrowingContinuation { continuation in
      session.sendMessage(
        [CompanionRelay.requestKey: payload],
        replyHandler: { reply in
          let status = reply[CompanionRelay.statusKey] as? Int ?? 0
          if (200..<300).contains(status), let body = reply[CompanionRelay.bodyKey] as? Data {
            continuation.resume(returning: body)
          } else if status == 0 {
            continuation.resume(throwing: CompanionAPIError.offline)
          } else {
            continuation.resume(throwing: CompanionAPIError.status(status))
          }
        },
        errorHandler: { _ in continuation.resume(throwing: CompanionAPIError.offline) })
    }
  }

  private func message(for error: Error) -> String {
    switch error as? CompanionAPIError {
    case .status(401): return "Open New Me on your iPhone to sign in again."
    case .status(422): return "That day is closed."
    case .status: return "The server said no. Try from your iPhone."
    default: return "No connection. Try again near your iPhone."
    }
  }

  private func store(_ next: CompanionSnapshot?) {
    snapshot = next
    if let next = next {
      CompanionStore.save(next)
    } else {
      CompanionStore.clear()
    }
    WidgetCenter.shared.reloadAllTimelines()
  }

  fileprivate func receive(_ context: [String: Any]) {
    guard let data = context[CompanionRelay.snapshotKey] as? Data else { return }
    // An empty snapshot is the phone signing out.
    store(data.isEmpty ? nil : CompanionStore.decode(data))
  }
}

extension WatchModel: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    let context = session.receivedApplicationContext
    Task { @MainActor in self.receive(context) }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    Task { @MainActor in self.receive(context) }
  }
}
