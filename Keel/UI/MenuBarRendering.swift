import AppKit

// Draws the menu bar item. Template images, so macOS tints them for light and dark menu bars.
struct MenuBarRendering {
  let state: ChargeState
  let percent: Double?
  let snapshot: BatterySnapshot?
  let options: AppOptions
  let recent: [BatterySample]

  var text: String {
    var parts: [String] = []
    // The iPhone-style battery shows the level inside itself.
    if options.menuBarPercent, options.iconStyle != .battery, let percent {
      parts.append("\(Int(percent.rounded()))%")
    }
    if options.menuBarWatts, let snapshot, let watts = PowerFlow(snapshot: snapshot).sourceWatts {
      parts.append(String(format: "%.0fW", watts))
    }
    if options.menuBarTemperature, let temperature = snapshot?.temperature {
      parts.append(String(format: "%.0f°", temperature))
    }
    return parts.isEmpty ? "" : " " + parts.joined(separator: " ")
  }

  func image() -> NSImage? {
    switch options.iconStyle {
    case .symbol: return symbolImage()
    case .battery: return batteryImage()
    case .graph: return graphImage()
    }
  }

  // AlDente's live status icons: plugged in and charging, plugged in and paused, plugged in and
  // discharging, unplugged.
  var symbolName: String {
    switch state {
    case .charging, .topUp, .macOSOverride, .calibration: return "battery.100percent.bolt"
    case .paused: return "powerplug"
    case .heatProtect: return "thermometer.high"
    case .discharging: return "arrow.down.to.line.compact"
    case .unavailable: return "exclamationmark.triangle"
    case .onBattery:
      switch percent ?? 0 {
      case 88...: return "battery.100percent"
      case 63..<88: return "battery.75percent"
      case 38..<63: return "battery.50percent"
      case 13..<38: return "battery.25percent"
      default: return "battery.0percent"
      }
    }
  }

  private func symbolImage() -> NSImage? {
    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: state.title)
    image?.isTemplate = true
    return image
  }

  private func batteryImage() -> NSImage {
    let level = min(max((percent ?? 0) / 100, 0), 1)
    let label = percent.map { "\(Int($0.rounded()))" } ?? ""
    let charging = [.charging, .topUp, .macOSOverride, .calibration].contains(state)
    let showPercent = options.menuBarPercent
    let image = NSImage(size: NSSize(width: 27, height: 13), flipped: false) { _ in
      let body = NSRect(x: 0.5, y: 0.5, width: 23, height: 12)
      let outline = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
      NSColor.black.withAlphaComponent(0.4).setStroke()
      outline.lineWidth = 1
      outline.stroke()
      NSBezierPath(roundedRect: NSRect(x: 24.5, y: 4.5, width: 1.8, height: 4), xRadius: 0.9, yRadius: 0.9).fill()
      if showPercent {
        // Like iOS: the number sits inside, cut out of a full-width fill.
        NSColor.black.setFill()
        NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 2, yRadius: 2).fill()
        let attributes: [NSAttributedString.Key: Any] = [
          .font: NSFont.systemFont(ofSize: 9, weight: .bold),
          .foregroundColor: NSColor.black,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let size = text.size()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        text.draw(at: NSPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2))
        NSGraphicsContext.current?.compositingOperation = .sourceOver
      } else {
        NSColor.black.setFill()
        let fill = NSRect(x: 2, y: 2, width: max(1.5, 20 * level), height: 9)
        NSBezierPath(roundedRect: fill, xRadius: 1.8, yRadius: 1.8).fill()
      }
      if charging {
        let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        bolt?.draw(in: NSRect(x: 8, y: 0, width: 8, height: 13), from: .zero, operation: .xor, fraction: 1)
      }
      return true
    }
    image.isTemplate = true
    return image
  }

  // The charge level over the last half hour as a small line.
  private func graphImage() -> NSImage {
    let values = recent.map { Double($0.percent) } + (percent.map { [$0] } ?? [])
    let image = NSImage(size: NSSize(width: 34, height: 14), flipped: false) { rect in
      guard values.count >= 2 else {
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 6, width: rect.width, height: 1.5)).fill()
        return true
      }
      let low = max(0, (values.min() ?? 0) - 2)
      let high = min(100, (values.max() ?? 100) + 2)
      let span = max(high - low, 4)
      let path = NSBezierPath()
      for (index, value) in values.enumerated() {
        let point = NSPoint(
          x: rect.width * CGFloat(index) / CGFloat(values.count - 1),
          y: 1 + (rect.height - 2) * CGFloat((value - low) / span)
        )
        index == 0 ? path.move(to: point) : path.line(to: point)
      }
      NSColor.black.setStroke()
      path.lineWidth = 1.5
      path.lineJoinStyle = .round
      path.stroke()
      return true
    }
    image.isTemplate = true
    return image
  }
}
