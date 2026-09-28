import Foundation

// Which cards the popover shows, in which order. The owner rearranges them in edit mode.
struct PopoverLayout: Codable, Equatable, Sendable {
  enum Card: String, Codable, CaseIterable, Identifiable, Sendable {
    case summary, limit, actions, powerFlow, stats, charger, chart

    var id: String { rawValue }

    var title: String {
      switch self {
      case .summary: return String(localized: "Battery level")
      case .limit: return String(localized: "Charge limit")
      case .actions: return String(localized: "Top Up, Discharge, Calibrate")
      case .powerFlow: return String(localized: "Power flow")
      case .stats: return String(localized: "Health, cycles, temperature")
      case .charger: return String(localized: "Charger")
      case .chart: return String(localized: "Last 24 hours")
      }
    }
  }

  var order: [Card] = [.summary, .limit, .actions, .powerFlow, .stats, .charger, .chart]
  var hidden: Set<Card> = [.charger, .chart]

  var visible: [Card] { order.filter { !hidden.contains($0) } }

  // Adds cards introduced after the layout was saved and drops unknown ones.
  func normalized() -> PopoverLayout {
    var copy = self
    copy.order = order.filter { Card.allCases.contains($0) }
    for card in Card.allCases where !copy.order.contains(card) {
      copy.order.append(card)
      copy.hidden.insert(card)
    }
    return copy
  }

  mutating func move(_ card: Card, by offset: Int) {
    guard let index = order.firstIndex(of: card) else { return }
    let target = index + offset
    guard order.indices.contains(target) else { return }
    order.swapAt(index, target)
  }

  mutating func toggle(_ card: Card) {
    if hidden.contains(card) { hidden.remove(card) } else { hidden.insert(card) }
  }
}
