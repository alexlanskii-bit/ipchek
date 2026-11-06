import Foundation
import IPCheckCore
import Observation
import UserNotifications

/// Состояние приложения для интерфейса.
@MainActor
@Observable
final class AppModel {
  private(set) var settings: MonitorSettings
  private(set) var notificationStatus: NotificationService.Status = .notDetermined
  private(set) var isSendingTest = false
  private(set) var lastTestResult: String?

  private let notifications = NotificationService()
  /// Центр уведомлений хранит делегата слабой ссылкой, поэтому держим его здесь.
  private let presenter = NotificationPresenter()

  init() {
    settings = Self.loadSettings()
    UNUserNotificationCenter.current().delegate = presenter
    Task { await requestNotificationPermission() }
  }

  var notificationStatusText: String {
    switch notificationStatus {
    case .notDetermined: "Уведомления: ждём вашего ответа"
    case .allowed: "Уведомления: разрешены"
    case .denied: "Уведомления: запрещены — включите в Системных настройках"
    case .failed: "Уведомления: macOS не даёт их включить"
    }
  }

  func sendTestNotification() {
    guard !isSendingTest else { return }
    isSendingTest = true
    Task {
      defer { isSendingTest = false }
      notificationStatus = await notifications.currentStatus()
      guard notificationStatus == .allowed else {
        lastTestResult = "Не отправлено: уведомления не разрешены"
        return
      }
      do {
        try await notifications.sendTest()
        lastTestResult = "Тестовое уведомление отправлено"
        Log.notifications.info("Тестовое уведомление отправлено")
      } catch {
        lastTestResult = "Не удалось отправить уведомление"
        Log.notifications.error(
          "Тестовое уведомление не отправлено: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func requestNotificationPermission() async {
    let status = await notifications.requestAuthorization()
    notificationStatus = status
    switch status {
    case .allowed:
      Log.notifications.info("Уведомления разрешены")
    case .denied, .notDetermined:
      Log.notifications.notice("Уведомления не разрешены")
    case .failed(let reason):
      Log.notifications.error(
        "Запрос разрешения на уведомления не удался: \(reason, privacy: .public)")
    }
  }

  /// Проверка настроек при запуске: неверные значения заменяются значениями по умолчанию,
  /// каждая замена пишется в журнал.
  private static func loadSettings() -> MonitorSettings {
    let stored = MonitorSettings.storedValues { UserDefaults.standard.object(forKey: $0) }
    let validation = MonitorSettings.validated(from: stored)
    for issue in validation.issues {
      Log.settings.warning("\(issue.logDescription, privacy: .public)")
    }
    return validation.settings
  }
}
