import SwiftUI

/// The app's warm palette from tokens.dart, so the widgets and Watch read as the same product.
enum CompanionStyle {
  static let canvas = Color(hex: "#FBF8F3")
  static let sunken = Color(hex: "#F3EFE8")
  static let border = Color(hex: "#E8E2D8")
  static let ink = Color(hex: "#25283D")
  static let inkMuted = Color(hex: "#6E7283")
  static let flame = Color(hex: "#F08A24")
  static let fallbackAccent = Color(hex: "#3FA66B")

  static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
    .system(style, design: .rounded).weight(weight)
  }

  /// Material icon names the app stores, mapped to the nearest SF Symbol.
  static func symbol(for icon: String) -> String {
    switch icon {
    case "bathtub": return "bathtub.fill"
    case "bedtime": return "moon.fill"
    case "bolt": return "bolt.fill"
    case "brush": return "mouth.fill"
    case "clean_hands": return "hands.sparkles.fill"
    case "directions_bike": return "bicycle"
    case "directions_run": return "figure.run"
    case "directions_walk": return "figure.walk"
    case "eco": return "leaf.fill"
    case "edit_note": return "square.and.pencil"
    case "favorite": return "heart.fill"
    case "fitness_center": return "dumbbell.fill"
    case "local_cafe": return "cup.and.saucer.fill"
    case "lunch_dining", "restaurant": return "fork.knife"
    case "medication", "vaccines": return "pills.fill"
    case "menu_book": return "book.fill"
    case "pets": return "pawprint.fill"
    case "self_improvement", "spa": return "figure.mind.and.body"
    case "sports_gymnastics": return "figure.cooldown"
    case "star": return "star.fill"
    case "water_drop": return "drop.fill"
    case "wb_sunny": return "sun.max.fill"
    default: return "checkmark.circle"
    }
  }
}

extension Color {
  init(hex: String) {
    let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let value = UInt32(digits, radix: 16) ?? 0x3FA66B
    self.init(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }
}

extension CompanionSnapshot {
  var fill: Color { Color(hex: accent.fill) }
  var tint: Color { Color(hex: accent.tint) }
}

/// The Today ring: a sweep for the day's percent and a tick where the streak line sits.
struct ScoreRing: View {
  let percent: Int
  let streakLine: Int
  let color: Color
  var track: Color = CompanionStyle.sunken
  var tick: Color = CompanionStyle.ink
  var lineWidth: CGFloat = 8

  var body: some View {
    let sweep = CGFloat(min(max(percent, 0), 100)) / 100
    let line = CGFloat(min(max(streakLine, 1), 99)) / 100
    ZStack {
      Circle().stroke(track, lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: sweep)
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Circle()
        .trim(from: line - 0.004, to: line + 0.004)
        .stroke(tick, style: StrokeStyle(lineWidth: lineWidth + 3, lineCap: .butt))
        .rotationEffect(.degrees(-90))
    }
    .padding(lineWidth / 2)
  }
}

/// Sample data for widget galleries and previews.
extension CompanionSnapshot {
  static let preview = CompanionSnapshot(
    version: supportedVersion, date: dayString(Date()), name: "You",
    accent: Accent(fill: "#3FA66B", tint: "#E6F4EC"), points: 180, percent: 62, streakLine: 70,
    counted: false, streak: 4,
    quests: [
      Quest(key: "steps", title: "Steps", done: true),
      Quest(key: "pushups", title: "Get stronger", done: false),
    ],
    habits: [
      HabitItem(
        habitId: 1, slot: 0, name: "Brush teeth", label: "Morning", icon: "brush", done: true,
        count: 0, target: nil, time: "07:30"),
      HabitItem(
        habitId: 2, slot: 0, name: "Vitamins", label: "Daily", icon: "medication", done: false,
        count: 0, target: nil, time: nil),
      HabitItem(
        habitId: 3, slot: nil, name: "Water", label: "", icon: "water_drop", done: false, count: 3,
        target: 8, time: nil),
    ],
    session: nil)
}
