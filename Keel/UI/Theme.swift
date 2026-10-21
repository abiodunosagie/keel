import AppKit
import SwiftUI

// The Keel brand palette (brand/README.md). Deep Water neutrals; Held Green = held at the limit and
// amber = moving toward it, the MagSafe light's own colours.
enum Theme {
  static let surface = dynamic(light: 0xF6F8F9, dark: 0x22282C)
  static let panel = dynamic(light: 0xFFFFFF, dark: 0x1B2023)
  static let chip = dynamic(light: 0xEEF1F3, dark: 0x2B3236)
  static let line = dynamic(light: 0x1B2226, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.09)
  static let ink = dynamic(light: 0x1B2226, dark: 0xEEF2F4)
  static let ink2 = dynamic(light: 0x55626B, dark: 0xA9B5BC)
  // Secondary text at 11 pt, kept at 4.5:1 or better against the panels.
  static let ink3 = dynamic(light: 0x66727A, dark: 0x8D9AA3)
  static let held = dynamic(light: 0x1F9A5A, dark: 0x3DD68C)
  static let moving = dynamic(light: 0xD9822B, dark: 0xF0A14D)
  static let heat = dynamic(light: 0xC8483A, dark: 0xEC6A5B)
  static let accent = dynamic(light: 0x1E5A78, dark: 0x7FB8D4)

  static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }

  static func color(for state: ChargeState) -> Color {
    switch state {
    case .paused: return held
    case .charging, .discharging, .topUp, .calibration, .macOSOverride: return moving
    case .heatProtect: return heat
    case .onBattery, .unavailable: return ink2
    }
  }

  private static func dynamic(
    light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1
  ) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      return rgb(isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
    })
  }

  private static func rgb(_ hex: UInt32, alpha: CGFloat) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: alpha
    )
  }
}

// A bordered inner panel for the dashboard window's groups.
struct PanelBackground: ViewModifier {
  var radius: CGFloat = 12

  func body(content: Content) -> some View {
    content
      .background(Theme.panel, in: RoundedRectangle(cornerRadius: radius))
      .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.line))
  }
}

extension View {
  func panel(radius: CGFloat = 12) -> some View {
    modifier(PanelBackground(radius: radius))
  }
}
