import Foundation
import UserNotifications

// Posts the few charge events worth knowing about.
@MainActor
final class Notifier {
  private var authorized: Bool?

  func post(_ event: ChargeEvent) {
    let content = UNMutableNotificationContent()
    switch event {
    case .limitReached(let limit):
      content.title = "Charge limit reached"
      content.body = "The battery is held at \(limit)%. The Mac now runs on the charger."
    case .heatPauseStarted(let temperature):
      content.title = "Charging paused"
      content.body = "The battery is at \(Format.temperature(temperature)). Charging resumes when it cools."
    case .calibrationFinished:
      content.title = "Calibration finished"
      content.body = "The battery gauge is recalibrated and back at your limit."
    case .calibrationStopped(let reason):
      content.title = "Calibration stopped"
      content.body = reason
    }
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    Task {
      guard await isAuthorized() else { return }
      try? await UNUserNotificationCenter.current().add(request)
    }
  }

  // Asked once per launch; a refusal is remembered so the owner is never asked again.
  private func isAuthorized() async -> Bool {
    if let authorized { return authorized }
    let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    authorized = granted
    return granted
  }
}
