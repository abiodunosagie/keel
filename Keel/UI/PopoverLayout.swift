import Foundation

// Which cards the popover shows, in which order. The owner rearranges them in edit mode.
struct PopoverLayout: Codable, Equatable, Sendable {
  enum Card: String, Codable, CaseIterable, Identifiable, Sendable {
    case summary, limit, actions, powerFlow, stats, charger, chart

    var id: String { rawValue }

    var title: String {
      switch self {
      case .summary: return "Battery level"
      case .limit: return "Charge limit"
      case .actions: return "Top Up, Discharge, Calibrate"
      case .powerFlow: return "Power flow"
      case .stats: return "Health, cycles, temperature"
      case .charger: return "Charger"
      case .chart: return "Last 24 hours"
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
