import Foundation

/// Everything a widget or the Watch can change. Codable so the Watch can hand an action to the
/// phone when it has no network of its own.
enum CompanionAction: Codable, Equatable {
  case markSlot(habitId: Int, slot: Int, done: Bool)
  case markCount(habitId: Int, count: Int)
  case logActivity(type: String, quantity: Int, unit: String, clientOpId: String)
}

/// What the Watch sends the phone over WatchConnectivity under [CompanionRelay.requestKey]; the
/// reply carries the HTTP status and body under [CompanionRelay.statusKey] and [bodyKey].
struct CompanionRequest: Codable {
  let action: CompanionAction
  let date: String
}

enum CompanionRelay {
  static let snapshotKey = "snapshot"
  static let requestKey = "request"
  static let statusKey = "status"
  static let bodyKey = "body"
}

enum CompanionAPIError: Error, Equatable {
  /// No answer at all, which the Watch treats as a reason to go through the phone.
  case offline
  /// The server answered and refused; retrying elsewhere will not help.
  case status(Int)
  case badRequest
}

struct CompanionAPI {
  let session: CompanionSnapshot.Session
  var urlSession: URLSession = .shared

  /// Sends [action] for [date] and returns the server's JSON body.
  func perform(_ action: CompanionAction, date: String) async throws -> Data {
    switch action {
    case let .markSlot(habitId, slot, done):
      return try await send("PUT", "/api/habits/\(habitId)/marks/\(date)", ["slot": slot, "done": done])
    case let .markCount(habitId, count):
      return try await send("PUT", "/api/habits/\(habitId)/marks/\(date)", ["count": count])
    case let .logActivity(type, quantity, unit, clientOpId):
      return try await send(
        "POST", "/api/logs",
        ["kind": "activity", "type": type, "quantity": quantity, "unit": unit, "clientOpId": clientOpId])
    }
  }

  private func send(_ method: String, _ path: String, _ body: [String: Any]) async throws -> Data {
    let base = session.baseUrl.hasSuffix("/") ? String(session.baseUrl.dropLast()) : session.baseUrl
    guard let url = URL(string: base + path),
      let payload = try? JSONSerialization.data(withJSONObject: body)
    else { throw CompanionAPIError.badRequest }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = method
    request.httpBody = payload
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(session.appKey, forHTTPHeaderField: "X-App-Key")
    request.setValue("Bearer " + session.token, forHTTPHeaderField: "Authorization")
    request.setValue(session.clientVersion, forHTTPHeaderField: "X-Client-Version")
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await urlSession.data(for: request)
    } catch {
      throw CompanionAPIError.offline
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    // A 5xx is the server being away, not a refusal of this action.
    if status >= 500 || status == 0 { throw CompanionAPIError.offline }
    guard (200..<300).contains(status) else { throw CompanionAPIError.status(status) }
    return data
  }
}
