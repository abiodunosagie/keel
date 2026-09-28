import KeyboardShortcuts
import SwiftUI

struct AutomationPane: View {
  @Environment(Automation.self) private var automation
  @Environment(ChargeController.self) private var controller
  @State private var newNetwork = ""
  @State private var newLimit = 80

  var body: some View {
    @Bindable var automation = automation
    VStack(alignment: .leading, spacing: 16) {
      PaneHeader(title: String(localized: "Automation"), lede: String(localized: "Let Keel react to your calendar, your Wi-Fi and your keyboard."))
      RowGroup {
        SettingRow(title: String(localized: "Top Up before trips"), detail: calendarDetail) {
          Toggle("Top Up before trips", isOn: $automation.settings.calendarTopUp).labelsHidden().toggleStyle(.switch)
        }
        SettingRow(title: String(localized: "Event words"), detail: String(localized: "Events whose title contains one of these, separated by commas.")) {
          TextField("Words", text: $automation.settings.calendarKeywords)
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }
        .disabled(!automation.settings.calendarTopUp)
        SettingRow(title: String(localized: "Start charging"), detail: String(localized: "Hours before the event. Needs the charger plugged in then.")) {
          Stepper(value: $automation.settings.calendarLeadHours, in: 1...12) {
            ValueChip(text: String(localized: "\(automation.settings.calendarLeadHours) h before"))
          }
        }
        .disabled(!automation.settings.calendarTopUp)
      }
      networkRules
      RowGroup {
        SettingRow(title: String(localized: "Turn the display off when idle"), detail: String(localized: "While Keel keeps the Mac awake (calibration, keep awake until the limit).")) {
          HStack(spacing: 10) {
            Stepper(value: $automation.settings.displayIdleMinutes, in: 1...60) {
              ValueChip(text: String(localized: "\(automation.settings.displayIdleMinutes) min"))
            }
            .disabled(!automation.settings.displayOffWhenIdle)
            Toggle("Turn the display off when idle", isOn: $automation.settings.displayOffWhenIdle)
              .labelsHidden().toggleStyle(.switch)
          }
        }
        SettingRow(title: String(localized: "Lock the screen when the lid closes"), detail: String(localized: "While Keel keeps the Mac awake, so nobody can open it and use it.")) {
          Toggle("Lock the screen when the lid closes", isOn: $automation.settings.lockOnLidClose)
            .labelsHidden().toggleStyle(.switch)
        }
      }
      shortcuts
    }
  }

  private var calendarDetail: String {
    if automation.calendarAccess == false {
      return String(localized: "Keel has no calendar access. Allow it in System Settings > Privacy & Security > Calendars.")
    }
    if let trip = automation.nextTrip {
      return String(localized: "Next: \(trip.title), \(trip.start.formatted(date: .abbreviated, time: .shortened)).")
    }
    return String(localized: "Charges to 100% before events like flights or conferences, then back to your limit after you unplug.")
  }

  private var networkRules: some View {
    @Bindable var automation = automation
    return VStack(alignment: .leading, spacing: 8) {
      Text("Limits per Wi-Fi network").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
      Text(networkDetail)
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.ink3)
        .fixedSize(horizontal: false, vertical: true)
      RowGroup {
        ForEach(automation.settings.networkRules) { rule in
          SettingRow(title: rule.network, detail: rule.network == automation.currentNetwork ? String(localized: "Connected now.") : nil) {
            HStack(spacing: 10) {
              ValueChip(text: "\(rule.limit)%")
              Button("Remove") { automation.settings.networkRules.removeAll { $0.id == rule.id } }
            }
          }
        }
        SettingRow(title: String(localized: "Add a network"), detail: nil) {
          HStack(spacing: 8) {
            TextField("Network name", text: $newNetwork)
              .textFieldStyle(.roundedBorder)
              .frame(width: 170)
            if let current = automation.currentNetwork, newNetwork.isEmpty {
              Button("Use \(current)") { newNetwork = current }
            }
            Stepper(value: $newLimit, in: controller.limitRange, step: 5) { ValueChip(text: "\(newLimit)%") }
            Button("Add") {
              let name = newNetwork.trimmingCharacters(in: .whitespaces)
              guard !name.isEmpty else { return }
              automation.settings.networkRules.removeAll { $0.network == name }
              automation.settings.networkRules.append(NetworkRule(network: name, limit: newLimit))
              newNetwork = ""
            }
            .disabled(newNetwork.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
      }
    }
  }

  private var networkDetail: String {
    if automation.locationAccess == false {
      return String(localized: "macOS hides Wi-Fi names without location access. Allow Keel in System Settings > Privacy & Security > Location Services.")
    }
    let current = automation.currentNetwork.map { String(localized: "Connected to \($0). ") } ?? ""
    return current + String(localized: "Joining a listed network sets its limit; other networks use your normal limit.")
  }

  private var shortcuts: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Keyboard shortcuts").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
      RowGroup {
        shortcutRow(String(localized: "Top Up on or off"), .toggleTopUp)
        shortcutRow(String(localized: "Raise the limit by \(Hotkeys.limitStep)%"), .raiseLimit)
        shortcutRow(String(localized: "Lower the limit by \(Hotkeys.limitStep)%"), .lowerLimit)
        shortcutRow(String(localized: "Pause here"), .pauseHere)
        shortcutRow(String(localized: "Show the popover"), .togglePopover)
        shortcutRow(String(localized: "Open the dashboard"), .openDashboard)
      }
    }
  }

  private func shortcutRow(_ title: String, _ name: KeyboardShortcuts.Name) -> some View {
    SettingRow(title: title, detail: nil) {
      KeyboardShortcuts.Recorder(for: name)
    }
  }
}
