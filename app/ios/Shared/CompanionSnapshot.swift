import Foundation

/// Today as the app last saw it, written by Flutter for the widgets and the Watch. It also
/// carries the session, so a widget button or a Watch tap can reach the API without the app.
struct CompanionSnapshot: Codable, Equatable {
  struct Accent: Codable, Equatable {
    let fill: String
    let tint: String
  }

  struct Quest: Codable, Equatable {
    let key: String
    let title: String
    var done: Bool
  }

  /// One tappable thing: a slot of a check habit, or a whole count habit (slot is nil).
  struct HabitItem: Codable, Equatable, Hashable, Identifiable {
    let habitId: Int
    let slot: Int?
    let name: String
    let label: String
    let icon: String
    var done: Bool
    var count: Int
    let target: Int?
    let time: String?

    var id: String { slot.map { "\(habitId)-\($0)" } ?? "\(habitId)" }
    var isCount: Bool { slot == nil }

    var title: String {
      if isCount, let target = target { return "\(name) \(count)/\(target)" }
      return label.isEmpty || label == "Daily" ? name : "\(name) · \(label)"
    }

    /// What VoiceOver reads for the row, which the strike-through and the tick alone do not say.
    var accessibilityText: String {
      if isCount, let target = target {
        return "\(name), \(count) of \(target)\(done ? ", done" : "")"
      }
      return "\(title), \(done ? "done" : "not done")"
    }
  }

  struct Session: Codable, Equatable {
    let baseUrl: String
    let token: String
    let appKey: String
    let clientVersion: String
  }

  static let supportedVersion = 1

  let version: Int
  /// The person's local day, YYYY-MM-DD, that every number here belongs to.
  let date: String
  let name: String
  let accent: Accent
  var points: Int
  var percent: Int
  let streakLine: Int
  var counted: Bool
  let streak: Int
  var quests: [Quest]
  var habits: [HabitItem]
  let session: Session?
  /// The profile's IANA zone, which `date` was cut in; nil in snapshots from older builds.
  var timezone: String? = nil

  var questsLeft: Int { quests.filter { !$0.done }.count }
  var habitsDue: Int { habits.filter { !$0.done }.count }

  /// The calendar of the person's day, so midnight is theirs and not the phone's.
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timezone.flatMap { TimeZone(identifier: $0) } ?? TimeZone.current
    return calendar
  }

  /// False once the local day has moved on, when every number here belongs to yesterday.
  func isCurrent(at now: Date = Date()) -> Bool {
    date == Self.dayString(now, in: timezone.flatMap { TimeZone(identifier: $0) })
  }

  static func dayString(_ date: Date, in zone: TimeZone? = nil) -> String {
    let format = DateFormatter()
    format.calendar = Calendar(identifier: .gregorian)
    format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = zone ?? TimeZone.current
    format.dateFormat = "yyyy-MM-dd"
    return format.string(from: date)
  }

  /// Undone first, so the buttons that still matter are the ones that fit.
  var habitsForButtons: [HabitItem] {
    habits.enumerated()
      .sorted { a, b in a.element.done == b.element.done ? a.offset < b.offset : !a.element.done }
      .map(\.element)
  }

  func with(_ item: HabitItem) -> CompanionSnapshot {
    var copy = self
    copy.habits = habits.map { $0.id == item.id ? item : $0 }
    return copy
  }

  /// What a tap means: a check slot flips, a count habit goes up by one.
  static func tapped(_ item: HabitItem) -> (next: HabitItem, action: CompanionAction) {
    var next = item
    if let slot = item.slot {
      next.done.toggle()
      return (next, .markSlot(habitId: item.habitId, slot: slot, done: next.done))
    }
    next.count += 1
    next.done = item.target.map { next.count >= $0 } ?? false
    return (next, .markCount(habitId: item.habitId, count: next.count))
  }

  /// Folds in what the server answered to a mark or a log, so the ring and quests are right
  /// before the app next refreshes.
  func applying(response data: Data) -> CompanionSnapshot {
    guard let response = try? JSONDecoder().decode(ActionResponse.self, from: data) else {
      return self
    }
    var copy = self
    if let day = response.day {
      copy.points = day.points ?? points
      // The ring and the gauges show the goal percent; a server that does not send it is
      // asked for the raw percent, which the 70 percent streak line scales to the same number.
      copy.percent = day.goalPercent ?? day.percent.map { $0 * 100 / 70 } ?? percent
      copy.counted = day.counted ?? counted
      if let quests = day.quests {
        let doneByKey = Dictionary(quests.map { ($0.key, $0.done) }, uniquingKeysWith: { a, _ in a })
        copy.quests = copy.quests.map { quest in
          var quest = quest
          quest.done = doneByKey[quest.key] ?? quest.done
          return quest
        }
      }
    }
    for habit in response.habits ?? [] {
      copy.habits = copy.habits.map { item in
        guard item.habitId == habit.id else { return item }
        var item = item
        if let slot = item.slot, let state = habit.slots?.first(where: { $0.index == slot }) {
          item.done = state.done
        } else if item.isCount, let count = habit.count {
          item.count = count
          item.done = item.target.map { count >= $0 } ?? false
        }
        return item
      }
    }
    return copy
  }
}

/// The parts of a mark or log response the snapshot keeps.
private struct ActionResponse: Decodable {
  struct Day: Decodable {
    struct Quest: Decodable {
      let key: String
      let done: Bool
    }
    let points: Int?
    let percent: Int?
    let goalPercent: Int?
    let counted: Bool?
    let quests: [Quest]?
  }

  struct Habit: Decodable {
    struct Slot: Decodable {
      let index: Int
      let done: Bool
    }
    let id: Int
    let slots: [Slot]?
    let count: Int?
  }

  let day: Day?
  let habits: [Habit]?
}

/// The App Group file every target reads. A file rather than shared defaults so a write is
/// atomic and readable after first unlock, when widgets refresh on a locked phone.
enum CompanionStore {
  static let appGroup = "group.top.npcserver.newme"
  private static let fileName = "companion-snapshot.json"

  private static var url: URL? {
    let container =
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
      // Unsigned builds have no group container; the app's own directory keeps them working.
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    return container?.appendingPathComponent(fileName)
  }

  static func load() -> CompanionSnapshot? {
    guard let url = url, let data = try? Data(contentsOf: url) else { return nil }
    return decode(data)
  }

  static func decode(_ data: Data) -> CompanionSnapshot? {
    guard let snapshot = try? JSONDecoder().decode(CompanionSnapshot.self, from: data),
      snapshot.version == CompanionSnapshot.supportedVersion
    else { return nil }
    return snapshot
  }

  @discardableResult
  static func save(_ data: Data) -> Bool {
    guard let url = url else { return false }
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
      try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      return true
    } catch {
      return false
    }
  }

  @discardableResult
  static func save(_ snapshot: CompanionSnapshot) -> Bool {
    guard let data = try? JSONEncoder().encode(snapshot) else { return false }
    return save(data)
  }

  static func clear() {
    guard let url = url else { return }
    try? FileManager.default.removeItem(at: url)
  }
}
