import AppIntents
import SwiftUI
import WidgetKit

@main
struct NewMeWidgets: WidgetBundle {
  var body: some Widget {
    TodayWidget()
  }
}

struct TodayEntry: TimelineEntry {
  let date: Date
  let snapshot: CompanionSnapshot?
  /// The snapshot belongs to a day that has ended, so its numbers must not be shown as today's.
  let stale: Bool
}

struct TodayProvider: TimelineProvider {
  func placeholder(in context: Context) -> TodayEntry {
    TodayEntry(date: Date(), snapshot: .preview, stale: false)
  }

  func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
    let snapshot = CompanionStore.load() ?? (context.isPreview ? .preview : nil)
    completion(TodayEntry(date: Date(), snapshot: snapshot, stale: snapshot.map { !$0.isCurrent() } ?? false))
  }

  // The app reloads the timeline whenever Today changes, so the only scheduled change is
  // midnight, when yesterday's numbers stop being today's.
  func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
    let now = Date()
    let snapshot = CompanionStore.load()
    guard let snapshot = snapshot, snapshot.isCurrent(at: now) else {
      completion(Timeline(entries: [TodayEntry(date: now, snapshot: snapshot, stale: snapshot != nil)], policy: .never))
      return
    }
    var entries = [TodayEntry(date: now, snapshot: snapshot, stale: false)]
    if let midnight = snapshot.calendar.nextDate(
      after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
    {
      entries.append(TodayEntry(date: midnight, snapshot: snapshot, stale: true))
    }
    completion(Timeline(entries: entries, policy: .never))
  }
}

struct TodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "NewMeToday", provider: TodayProvider()) { entry in
      TodayWidgetView(entry: entry)
    }
    .configurationDisplayName("Today")
    .description("Your ring, points, streak and the habits still due.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
  }
}

struct TodayWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: TodayEntry

  var body: some View {
    switch family {
    case .accessoryCircular:
      CircularView(entry: entry).containerBackground(for: .widget) { Color.clear }
    case .accessoryRectangular:
      RectangularView(entry: entry).containerBackground(for: .widget) { Color.clear }
    case .systemMedium:
      MediumView(entry: entry).containerBackground(CompanionStyle.canvas, for: .widget)
    default:
      SmallView(entry: entry).containerBackground(CompanionStyle.canvas, for: .widget)
    }
  }
}

/// Shown when there is nothing current to show: signed out, or a new day the app has not
/// opened yet.
private struct EmptyMessage: View {
  let entry: TodayEntry

  var body: some View {
    Text(entry.snapshot == nil ? "Open New Me to sign in." : "New day. Open New Me to start it.")
      .font(CompanionStyle.rounded(.footnote, weight: .medium))
      .foregroundStyle(CompanionStyle.inkMuted)
      .multilineTextAlignment(.center)
  }
}

private struct RingWithPoints: View {
  let snapshot: CompanionSnapshot
  let stale: Bool

  var body: some View {
    ZStack {
      ScoreRing(
        percent: stale ? 0 : snapshot.percent, streakLine: snapshot.streakLine, color: snapshot.fill,
        lineWidth: 9)
      VStack(spacing: 0) {
        Text(stale ? "0" : "\(snapshot.points)")
          .font(CompanionStyle.rounded(.title2, weight: .bold))
          .foregroundStyle(CompanionStyle.ink)
          .minimumScaleFactor(0.6)
          .lineLimit(1)
        Text("pts")
          .font(CompanionStyle.rounded(.caption2, weight: .medium))
          .foregroundStyle(CompanionStyle.inkMuted)
      }
      .padding(.horizontal, 14)
    }
  }
}

private struct StreakLine: View {
  let snapshot: CompanionSnapshot
  let stale: Bool

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "flame.fill").foregroundStyle(CompanionStyle.flame)
      Text("Day \(snapshot.streak)").foregroundStyle(CompanionStyle.ink)
      Spacer(minLength: 4)
      Text(stale ? "0%" : "\(snapshot.percent)%").foregroundStyle(CompanionStyle.inkMuted)
    }
    .font(CompanionStyle.rounded(.caption, weight: .semibold))
    .lineLimit(1)
  }
}

private struct SmallView: View {
  let entry: TodayEntry

  var body: some View {
    if let snapshot = entry.snapshot {
      VStack(spacing: 8) {
        RingWithPoints(snapshot: snapshot, stale: entry.stale)
        StreakLine(snapshot: snapshot, stale: entry.stale)
      }
    } else {
      EmptyMessage(entry: entry)
    }
  }
}

private struct MediumView: View {
  let entry: TodayEntry

  var body: some View {
    if let snapshot = entry.snapshot {
      HStack(spacing: 14) {
        VStack(spacing: 8) {
          RingWithPoints(snapshot: snapshot, stale: entry.stale)
          StreakLine(snapshot: snapshot, stale: entry.stale)
        }
        .frame(maxWidth: 120)
        if entry.stale {
          EmptyMessage(entry: entry).frame(maxWidth: .infinity)
        } else {
          HabitButtons(snapshot: snapshot)
        }
      }
    } else {
      EmptyMessage(entry: entry)
    }
  }
}

private struct HabitButtons: View {
  let snapshot: CompanionSnapshot

  var body: some View {
    let items = Array(snapshot.habitsForButtons.prefix(4))
    VStack(alignment: .leading, spacing: 6) {
      if items.isEmpty {
        Text("No habits due today.")
          .font(CompanionStyle.rounded(.footnote, weight: .medium))
          .foregroundStyle(CompanionStyle.inkMuted)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ForEach(items) { item in
          Button(intent: ToggleHabitIntent(habitId: item.habitId, slot: item.slot ?? -1)) {
            HabitRow(item: item, fill: snapshot.fill, tint: snapshot.tint)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(item.accessibilityText)
        }
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct HabitRow: View {
  let item: CompanionSnapshot.HabitItem
  let fill: Color
  let tint: Color

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: item.done ? "checkmark.circle.fill" : CompanionStyle.symbol(for: item.icon))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(item.done ? fill : CompanionStyle.ink)
        .frame(width: 18)
      Text(item.title)
        .font(CompanionStyle.rounded(.footnote, weight: .semibold))
        .foregroundStyle(item.done ? CompanionStyle.inkMuted : CompanionStyle.ink)
        .strikethrough(item.done && !item.isCount, color: CompanionStyle.inkMuted)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 8)
    .frame(height: 28)
    .background(item.done ? tint : CompanionStyle.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct CircularView: View {
  let entry: TodayEntry

  var body: some View {
    let percent = entry.stale ? 0 : entry.snapshot?.percent ?? 0
    Gauge(value: Double(min(percent, 100)), in: 0...100) {
      Image(systemName: "flame.fill")
    } currentValueLabel: {
      Text(entry.snapshot == nil ? "-" : "\(min(percent, 999))")
        .font(CompanionStyle.rounded(.body, weight: .bold))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
    .gaugeStyle(.accessoryCircularCapacity)
    .widgetAccentable()
  }
}

private struct RectangularView: View {
  let entry: TodayEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      if let snapshot = entry.snapshot, !entry.stale {
        Text("\(snapshot.percent)% · \(snapshot.points) pts")
          .font(CompanionStyle.rounded(.headline, weight: .bold))
          .widgetAccentable()
        Text(snapshot.questsLeft == 0 ? "All quests done" : plural(snapshot.questsLeft, "quest") + " left")
        Text(snapshot.habitsDue == 0 ? "No habits due" : plural(snapshot.habitsDue, "habit") + " due")
      } else {
        Text("New Me").font(CompanionStyle.rounded(.headline, weight: .bold)).widgetAccentable()
        Text(entry.snapshot == nil ? "Open the app to sign in" : "Open the app to start today")
      }
    }
    .font(CompanionStyle.rounded(.caption, weight: .medium))
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}

/// Marks a habit from the Home Screen. The snapshot changes first so the widget redraws at
/// once; the server's answer then settles the ring, and a refusal puts the habit back.
struct ToggleHabitIntent: AppIntent {
  static let title: LocalizedStringResource = "Mark habit"
  static let isDiscoverable = false

  @Parameter(title: "Habit") var habitId: Int
  /// The check slot, or -1 for a count habit.
  @Parameter(title: "Slot") var slot: Int

  init() {}

  init(habitId: Int, slot: Int) {
    self.habitId = habitId
    self.slot = slot
  }

  func perform() async throws -> some IntentResult {
    let wanted = slot < 0 ? nil : slot
    guard let snapshot = CompanionStore.load(), snapshot.isCurrent(),
      let session = snapshot.session,
      let before = snapshot.habits.first(where: { $0.habitId == habitId && $0.slot == wanted })
    else { return .result() }

    let (next, action) = CompanionSnapshot.tapped(before)
    CompanionStore.save(snapshot.with(next))
    WidgetCenter.shared.reloadAllTimelines()

    do {
      let body = try await CompanionAPI(session: session).perform(action, date: snapshot.date)
      if let latest = CompanionStore.load() { CompanionStore.save(latest.applying(response: body)) }
    } catch {
      // Only undo our own change; a newer write from the app already knows better.
      if let latest = CompanionStore.load(), latest.habits.first(where: { $0.id == next.id }) == next {
        CompanionStore.save(latest.with(before))
      }
    }
    WidgetCenter.shared.reloadAllTimelines()
    return .result()
  }
}
