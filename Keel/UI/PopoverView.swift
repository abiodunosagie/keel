import Charts
import SwiftUI

// The menu bar popover, laid out as in the approved mockup. Hold any card to rearrange or hide
// cards; the layout is saved.
struct PopoverView: View {
  @Environment(AppModel.self) private var model
  @Environment(ChargeController.self) private var controller

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if model.isEditingPopover {
        PopoverEditor()
      } else if let snapshot = controller.snapshot {
        ForEach(model.popoverLayout.visible) { card in
          if card.isInteractive {
            // The slider and buttons keep their own gestures; hold any other card to edit.
            view(for: card, snapshot: snapshot)
          } else {
            view(for: card, snapshot: snapshot)
              .contentShape(Rectangle())
              .onLongPressGesture(minimumDuration: 0.6) { model.isEditingPopover = true }
          }
        }
      } else {
        Text("No battery found.").foregroundStyle(Theme.ink2)
      }
      if let error = controller.lastError {
        Label(error, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(Theme.heat)
      }
    }
    .padding(14)
    .frame(width: 340)
    .background(controller.options.reduceTransparency ? Theme.surface : .clear)
  }

  @ViewBuilder
  private func view(for card: PopoverLayout.Card, snapshot: BatterySnapshot) -> some View {
    switch card {
    case .summary:
      SummaryCard(snapshot: snapshot)
    case .limit:
      if controller.isAvailable {
        LimitCard()
      } else {
        Text(controller.unavailableReason).font(.callout).foregroundStyle(Theme.ink2)
      }
    case .actions:
      if controller.isAvailable { ActionRow(open: model.open) }
    case .powerFlow:
      PowerFlowRow(snapshot: snapshot)
    case .stats:
      StatsRow(snapshot: snapshot)
    case .charger:
      ChargerLine(snapshot: snapshot)
    case .chart:
      MiniChart()
    }
  }

  private var header: some View {
    HStack {
      if model.isEditingPopover {
        Text("Hold, hide and reorder cards").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink2)
        Spacer()
        Button("Done") { model.isEditingPopover = false }
      } else {
        StatePill(state: controller.state)
        Spacer()
        Button { model.open(.dashboard) } label: {
          Label("Open Dashboard", systemImage: "square.grid.2x2").labelStyle(.iconOnly)
        }
        .buttonStyle(IconButtonStyle())
        .help("Open Dashboard")
        Button { model.open(.charge) } label: {
          Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
        }
        .buttonStyle(IconButtonStyle())
        .help("Settings")
      }
    }
  }
}

private struct SummaryCard: View {
  @Environment(ChargeController.self) private var controller
  let snapshot: BatterySnapshot

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      HStack(alignment: .lastTextBaseline, spacing: 1) {
        Text(verbatim: "\(Int((controller.displayPercent ?? 0).rounded()))")
          .font(.system(size: 46, weight: .semibold))
          .monospacedDigit()
        Text(verbatim: "%")
          .font(Theme.mono(20, weight: .medium))
          .foregroundStyle(Theme.ink3)
      }
      .foregroundStyle(Theme.ink)
      Text(detail)
        .font(.system(size: 12))
        .foregroundStyle(Theme.ink2)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var detail: String {
    let other = controller.settings.useHardwarePercent
      ? String(localized: "macOS shows \(snapshot.macOSPercent)%.")
      : String(localized: "Hardware reads \(Format.percent(snapshot.hardwarePercent)).")
    switch controller.state {
    case .onBattery:
      if let minutes = snapshot.minutesToEmpty { return String(localized: "On battery, \(Format.duration(minutes)) left. \(other)") }
      return String(localized: "On battery. \(other)")
    case .charging, .topUp, .macOSOverride:
      if let minutes = snapshot.minutesToFull { return String(localized: "Charging, full in \(Format.duration(minutes)). \(other)") }
      return String(localized: "Plugged in and charging. \(other)")
    case .discharging:
      return String(localized: "Plugged in, running on battery down to the limit. \(other)")
    case .heatProtect:
      return String(localized: "Charging paused until the battery cools. \(other)")
    case .calibration:
      let step = controller.calibrationStep?.title ?? String(localized: "Calibrating")
      return "\(step). \(other)"
    case .paused:
      return String(localized: "Plugged in, running on the charger. \(other) Battery idle.")
    case .unavailable:
      return other
    }
  }
}

private struct ChargerLine: View {
  let snapshot: BatterySnapshot

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "powerplug").foregroundStyle(Theme.accent)
      if let charger = snapshot.charger {
        Text(charger.name).foregroundStyle(Theme.ink)
        Spacer()
        Text(snapshot.powerIn.map { "\(Format.watts($0)) in" } ?? "\(charger.watts) W")
          .font(Theme.mono(12, weight: .semibold))
          .foregroundStyle(Theme.ink)
      } else {
        Text("No charger").foregroundStyle(Theme.ink2)
        Spacer()
      }
    }
    .font(.system(size: 12))
  }
}

// The last 24 hours of charge, small.
private struct MiniChart: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let samples = model.history.samples(since: .now.addingTimeInterval(-86_400))
    Chart(samples) { sample in
      LineMark(x: .value(String(localized: "Time"), sample.date), y: .value(String(localized: "Percent"), sample.percent))
        .foregroundStyle(Theme.held)
    }
    .chartYScale(domain: 0...100)
    .chartXAxis(.hidden)
    .chartYAxis { AxisMarks(values: [0, 50, 100]) { AxisValueLabel() } }
    .frame(height: 60)
  }
}

// Edit mode: every card with show or hide and move up or down.
private struct PopoverEditor: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(model.popoverLayout.order.enumerated()), id: \.element) { index, card in
        let hidden = model.popoverLayout.hidden.contains(card)
        HStack(spacing: 10) {
          Button {
            model.popoverLayout.toggle(card)
          } label: {
            Label(hidden ? "Show" : "Hide", systemImage: hidden ? "eye.slash" : "eye").labelStyle(.iconOnly)
          }
          .buttonStyle(IconButtonStyle())
          Text(card.title)
            .foregroundStyle(hidden ? Theme.ink3 : Theme.ink)
          Spacer()
          Button { model.popoverLayout.move(card, by: -1) } label: {
            Label("Move up", systemImage: "chevron.up").labelStyle(.iconOnly)
          }
          .buttonStyle(IconButtonStyle())
          .disabled(index == 0)
          Button { model.popoverLayout.move(card, by: 1) } label: {
            Label("Move down", systemImage: "chevron.down").labelStyle(.iconOnly)
          }
          .buttonStyle(IconButtonStyle())
          .disabled(index == model.popoverLayout.order.count - 1)
        }
        .font(.system(size: 12.5))
        .padding(.vertical, 5)
      }
      Button("Reset Layout") { model.popoverLayout = PopoverLayout() }
        .padding(.top, 8)
    }
    .padding(12)
    .panel()
  }
}

struct StatePill: View {
  let state: ChargeState

  var body: some View {
    let color = Theme.color(for: state)
    HStack(spacing: 7) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
        .overlay(Circle().stroke(color.opacity(0.3), lineWidth: 3))
      Text(state.title)
    }
    .font(.system(size: 12, weight: .semibold))
    .foregroundStyle(color)
    .padding(.vertical, 4)
    .padding(.leading, 8)
    .padding(.trailing, 10)
    .background(color.opacity(0.15), in: Capsule())
    .help(state == .macOSOverride
          ? String(localized: "macOS sometimes charges to 100% to recalibrate its battery gauge. It goes back to the limit afterwards.")
          : "")
  }
}

struct IconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14))
      .foregroundStyle(Theme.ink2)
      .frame(width: 26, height: 26)
      .background(configuration.isPressed ? Theme.line : .clear, in: RoundedRectangle(cornerRadius: 7))
      .contentShape(Rectangle())
  }
}
