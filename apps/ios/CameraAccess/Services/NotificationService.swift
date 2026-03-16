import Foundation
import UserNotifications
import UIKit

final class NotificationService {
  static let shared = NotificationService()
  private init() {}

  private var isAuthorized = false

  func requestPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      DispatchQueue.main.async { self.isAuthorized = granted }
    }
  }

  /// Send a local notification if the app is not in the foreground
  func sendIfBackground(title: String, body: String, categoryId: String = "response") {
    guard isAuthorized else { return }

    let state = UIApplication.shared.applicationState
    // Send when backgrounded OR when screen is locked (inactive)
    guard state != .active else { return }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = categoryId

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil // deliver immediately
    )

    UNUserNotificationCenter.current().add(request)
  }
}
