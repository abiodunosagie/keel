import ServiceManagement
import SwiftUI

// What the setup quiz suggests. Pure, so the rules are tested.
struct SetupRecommendation: Equatable {
  enum Usage: String, CaseIterable, Identifiable {
    case desk, mixed, mobile
    var id: String { rawValue }
    var title: String {
      switch self {
      case .desk: return String(localized: "Plugged in at a desk")
      case .mixed: return String(localized: "About half plugged in, half on battery")
      case .mobile: return String(localized: "Mostly on battery")
      }
    }
  }

  enum LongDays: String, CaseIterable, Identifiable {
    case rarely, weekly, daily
    var id: String { rawValue }
    var title: String {
      switch self {
      case .rarely: return String(localized: "Rarely")
      case .weekly: return String(localized: "Once or twice a week")
      case .daily: return String(localized: "Most weekdays")
      }
    }
  }

  enum Heat: String, CaseIterable, Identifiable {
    case rarely, sometimes, often
    var id: String { rawValue }
    var title: String {
      switch self {
      case .rarely: return String(localized: "Rarely")
      case .sometimes: return String(localized: "Sometimes")
      case .often: return String(localized: "Often (heavy work or a warm room)")
      }
    }
  }

  var limit: Int
  var heatProtection: Bool
  var calibration: ScheduledTask.Repeat?
  var weekdayTopUp: Bool

  static func make(usage: Usage, longDays: LongDays, heat: Heat) -> SetupRecommendation {
    let limit: Int
    switch usage {
    case .desk: limit = 80
    case .mixed: limit = 85
    case .mobile: limit = 95
    }
    // A battery that rarely goes through full cycles drifts, so it gets calibrated regularly;
    // one used mostly on battery cycles on its own.
    let calibration: ScheduledTask.Repeat? = switch usage {
    case .desk: .biweekly
    case .mixed: .monthly
    case .mobile: nil
    }
    return SetupRecommendation(
      limit: limit,
      heatProtection: heat != .rarely,
      calibration: calibration,
      weekdayTopUp: longDays == .daily && usage != .mobile
    )
  }
}

struct OnboardingView: View {
  @Environment(AppModel.self) private var model
  @Environment(HelperClient.self) private var helper
  let close: () -> Void

  @State private var step = 0
  @State private var usage: SetupRecommendation.Usage = .desk
  @State private var longDays: SetupRecommendation.LongDays = .rarely
  @State private var heat: SetupRecommendation.Heat = .sometimes
  @State private var openAtLogin = true

  private var recommendation: SetupRecommendation {
    .make(usage: usage, longDays: longDays, heat: heat)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Step \(step + 1) of 5")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.ink3)
      Group {
        switch step {
        case 0: welcome
        case 1: question(String(localized: "How do you use this Mac most days?"), selection: $usage)
        case 2: question(String(localized: "How often do you need a full battery for a long day away from a charger?"), selection: $longDays)
        case 3: question(String(localized: "Does the Mac get hot?"), selection: $heat)
        default: summary
        }
      }
      Spacer()
      HStack {
        if step > 0 { Button("Back") { step -= 1 } }
        Spacer()
        if step < 4 {
          Button(step == 0 ? "Start" : "Next") { step += 1 }.keyboardShortcut(.defaultAction)
        } else {
          Button("Skip") { finish(apply: false) }
          Button("Apply and Finish") { finish(apply: true) }.keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.surface)
  }

  private var welcome: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Keep your battery healthy")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(Theme.ink)
      Text("Lithium batteries age fastest when they sit at 100% and when they are hot. Keel holds the battery at a limit you choose while the Mac is plugged in, and macOS keeps that limit even while the Mac sleeps or Keel is closed.")
        .foregroundStyle(Theme.ink2)
        .fixedSize(horizontal: false, vertical: true)
      Text("Three quick questions, and Keel suggests settings for how you use your Mac.")
        .foregroundStyle(Theme.ink2)
    }
    .font(.system(size: 13))
  }

  private func question<Choice: CaseIterable & Identifiable & Hashable>(
    _ title: String, selection: Binding<Choice>
  ) -> some View where Choice.AllCases: RandomAccessCollection, Choice: RawRepresentable, Choice.RawValue == String {
    VStack(alignment: .leading, spacing: 14) {
      Text(title)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .fixedSize(horizontal: false, vertical: true)
      Picker(title, selection: selection) {
        ForEach(Choice.allCases) { choice in
          Text(label(choice)).tag(choice)
        }
      }
      .pickerStyle(.radioGroup)
      .labelsHidden()
    }
  }

  private func label<Choice>(_ choice: Choice) -> String {
    if let usage = choice as? SetupRecommendation.Usage { return usage.title }
    if let days = choice as? SetupRecommendation.LongDays { return days.title }
    if let heat = choice as? SetupRecommendation.Heat { return heat.title }
    return ""
  }

  private var summary: some View {
    let plan = recommendation
    return VStack(alignment: .leading, spacing: 12) {
      Text("Suggested for you")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Theme.ink)
      RowGroup {
        SettingRow(title: String(localized: "Charge limit \(plan.limit)%"), detail: plan.limit >= 95
          ? String(localized: "Close to full, for days away from a charger.")
          : String(localized: "A healthy level while plugged in.")) { EmptyView() }
        SettingRow(title: plan.heatProtection ? String(localized: "Heat Protection on, 35 °C") : String(localized: "Heat Protection off"),
                   detail: String(localized: "Pauses charging while the battery is hot.")) { EmptyView() }
        SettingRow(title: plan.calibration.map { String(localized: "Calibration: \($0.title)") } ?? String(localized: "No scheduled calibration"),
                   detail: plan.calibration == nil
                     ? String(localized: "Using the battery keeps its reading accurate on its own.")
                     : String(localized: "Keeps the battery's percentage accurate. Needs Keel Helper.")) { EmptyView() }
        if plan.weekdayTopUp {
          SettingRow(title: String(localized: "Top Up weekday mornings at 06:30"), detail: String(localized: "A full battery for long days, back to the limit after you unplug.")) { EmptyView() }
        }
      }
      Toggle("Open Keel at login", isOn: $openAtLogin)
      if !helper.isReady {
        HStack {
          Text("Calibration and the MagSafe light need Keel Helper.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.ink2)
          Button("Install Helper") { helper.install() }
        }
      }
    }
  }

  private func finish(apply: Bool) {
    if apply {
      let plan = recommendation
      let controller = model.controller
      controller.setLimit(plan.limit)
      controller.settings.heatProtection = plan.heatProtection
      if plan.heatProtection { controller.settings.maxTemperature = 35 }
      let morning = Calendar.current.date(bySettingHour: 6, minute: 30, second: 0,
                                          of: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now) ?? .now
      if let repeats = plan.calibration {
        model.scheduler.save(ScheduledTask(action: .startCalibration, repeats: repeats, start: morning,
                                           runAtNextOpportunity: true))
      }
      if plan.weekdayTopUp {
        model.scheduler.save(ScheduledTask(action: .topUp, repeats: .weekdays, start: morning,
                                           runAtNextOpportunity: true))
      }
      if openAtLogin { try? SMAppService.mainApp.register() }
    }
    model.store.hasOnboarded = true
    close()
  }
}
