import SwiftUI
import WidgetKit

struct RingEntry: TimelineEntry {
  let date: Date
  let snapshot: CompanionSnapshot?
  let stale: Bool
}

/// Reads the snapshot the Watch app saves from the phone; the Watch app reloads this timeline
/// whenever it saves, so the only scheduled change is midnight.
struct RingProvider: TimelineProvider {
  func placeholder(in context: Context) -> RingEntry {
    RingEntry(date: Date(), snapshot: .preview, stale: false)
  }

  func getSnapshot(in context: Context, completion: @escaping (RingEntry) -> Void) {
    let snapshot = CompanionStore.load() ?? (context.isPreview ? .preview : nil)
    completion(RingEntry(date: Date(), snapshot: snapshot, stale: snapshot.map { !$0.isCurrent() } ?? false))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<RingEntry>) -> Void) {
    let now = Date()
    let snapshot = CompanionStore.load()
    var entries = [RingEntry(date: now, snapshot: snapshot, stale: snapshot.map { !$0.isCurrent(at: now) } ?? false)]
    if let snapshot = snapshot, snapshot.isCurrent(at: now),
      let midnight = snapshot.calendar.nextDate(
        after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
    {
      entries.append(RingEntry(date: midnight, snapshot: snapshot, stale: true))
    }
    completion(Timeline(entries: entries, policy: .never))
  }
}

@main
struct NewMeComplication: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "NewMeRing", provider: RingProvider()) { entry in
      RingComplicationView(entry: entry)
    }
    .configurationDisplayName("Today ring")
    .description("Today's percent and points.")
    .supportedFamilies([.accessoryCircular])
  }
}

struct RingComplicationView: View {
  let entry: RingEntry

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
    .tint(entry.snapshot?.fill ?? CompanionStyle.fallbackAccent)
    .widgetAccentable()
    .containerBackground(for: .widget) { Color.clear }
  }
}
