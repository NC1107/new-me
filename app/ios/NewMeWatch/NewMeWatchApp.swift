import SwiftUI
import WatchKit

@main
struct NewMeWatchApp: App {
  @StateObject private var model = WatchModel()

  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(model)
    }
  }
}

struct RootView: View {
  @EnvironmentObject private var model: WatchModel

  var body: some View {
    if let snapshot = model.snapshot, model.isCurrent {
      NavigationStack {
        TabView {
          TodayPage(snapshot: snapshot)
          HabitsPage(snapshot: snapshot)
          LogPage(snapshot: snapshot)
        }
        .tabViewStyle(.verticalPage)
      }
    } else {
      VStack(spacing: 8) {
        Image(systemName: "iphone")
          .font(.title2)
          .foregroundStyle(.secondary)
        Text(model.snapshot == nil ? "Open New Me on your iPhone to sign in." : "New day. Open New Me on your iPhone to start it.")
          .font(CompanionStyle.rounded(.footnote, weight: .medium))
          .multilineTextAlignment(.center)
      }
      .padding()
    }
  }
}

struct TodayPage: View {
  let snapshot: CompanionSnapshot

  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        ZStack {
          ScoreRing(
            percent: snapshot.percent, streakLine: snapshot.streakLine, color: snapshot.fill,
            track: Color.white.opacity(0.15), tick: .white, lineWidth: 10)
          VStack(spacing: 0) {
            Text("\(snapshot.points)").font(CompanionStyle.rounded(.title2, weight: .bold))
            Text("pts").font(CompanionStyle.rounded(.caption2)).foregroundStyle(.secondary)
          }
        }
        .frame(width: 104, height: 104)
        HStack {
          Label("Day \(snapshot.streak)", systemImage: "flame.fill")
            .labelStyle(FlameLabelStyle())
          Spacer()
          Text("\(snapshot.percent)%").foregroundStyle(.secondary)
        }
        .font(CompanionStyle.rounded(.footnote, weight: .semibold))
        ForEach(snapshot.quests, id: \.key) { quest in
          HStack(spacing: 6) {
            Image(systemName: quest.done ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(quest.done ? snapshot.fill : .secondary)
            Text(quest.title)
              .font(CompanionStyle.rounded(.footnote))
              .foregroundStyle(quest.done ? .secondary : .primary)
            Spacer(minLength: 0)
          }
        }
      }
    }
    .navigationTitle("Today")
  }
}

private struct FlameLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 4) {
      configuration.icon.foregroundStyle(CompanionStyle.flame)
      configuration.title
    }
  }
}

struct HabitsPage: View {
  @EnvironmentObject private var model: WatchModel
  let snapshot: CompanionSnapshot

  var body: some View {
    List {
      if snapshot.habits.isEmpty {
        Text("No habits due today.").foregroundStyle(.secondary)
      }
      ForEach(snapshot.habits) { item in
        Button {
          WKInterfaceDevice.current().play(item.done ? .directionDown : .success)
          model.tap(item)
        } label: {
          HStack(spacing: 8) {
            Image(systemName: item.done ? "checkmark.circle.fill" : CompanionStyle.symbol(for: item.icon))
              .foregroundStyle(item.done ? snapshot.fill : .primary)
              .frame(width: 20)
            Text(item.title)
              .font(CompanionStyle.rounded(.footnote, weight: .medium))
              .foregroundStyle(item.done ? .secondary : .primary)
              .lineLimit(2)
          }
        }
      }
      if let status = model.status {
        Text(status).font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Habits")
  }
}

struct LogPage: View {
  private struct Kind: Hashable {
    let type: String
    let unit: String
    let noun: String
    let start: Double
    let max: Double
  }

  private static let kinds = [
    Kind(type: "pushups", unit: "reps", noun: "push-ups", start: 10, max: 200),
    Kind(type: "reading", unit: "minutes", noun: "min reading", start: 15, max: 300),
  ]

  @EnvironmentObject private var model: WatchModel
  let snapshot: CompanionSnapshot
  @State private var kind = 0
  @State private var amount: Double = 10

  var body: some View {
    let current = Self.kinds[kind]
    VStack(spacing: 6) {
      Button {
        kind = (kind + 1) % Self.kinds.count
        amount = Self.kinds[kind].start
      } label: {
        Text(current.noun.capitalized(with: nil))
          .font(CompanionStyle.rounded(.footnote, weight: .semibold))
      }
      .buttonStyle(.bordered)
      Text("\(Int(amount))")
        .font(CompanionStyle.rounded(.largeTitle, weight: .bold))
        .focusable()
        .digitalCrownRotation(
          $amount, from: 0, through: current.max, by: 1, sensitivity: .medium,
          isContinuous: false, isHapticFeedbackEnabled: true)
      Button {
        Task {
          let quantity = Int(amount)
          if await model.log(type: current.type, quantity: quantity, unit: current.unit, noun: current.noun) {
            WKInterfaceDevice.current().play(.success)
          } else {
            WKInterfaceDevice.current().play(.failure)
          }
        }
      } label: {
        Text("Save").font(CompanionStyle.rounded(.body, weight: .semibold)).frame(maxWidth: .infinity)
      }
      .tint(snapshot.fill)
      .buttonStyle(.borderedProminent)
      .disabled(amount < 1 || model.busy)
      if let status = model.status {
        Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
      }
    }
    .navigationTitle("Log")
  }
}
