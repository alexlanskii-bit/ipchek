import AppKit
import Foundation
import IPCheckCore
import Observation
import UserNotifications

/// Состояние приложения для интерфейса.
@MainActor
@Observable
final class AppModel {
  let settings: MonitorSettings
  let connectivity: ConnectivityMonitor
  private(set) var notificationStatus: NotificationPermission = .notDetermined
  private(set) var isSendingTest = false
  private(set) var lastTestResult: String?

  private let notifications = NotificationService()
  /// Центр уведомлений хранит делегата слабой ссылкой, поэтому держим его здесь.
  private let presenter = NotificationPresenter()

  /// Раздел «Уведомления» Системных настроек. Идентификатор и разрешение на такие ссылки
  /// (`allowsXAppleSystemPreferencesURLScheme`) сверены по NotificationsSettings.appex в macOS 26.2.
  private static let notificationSettingsURL = URL(
    string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")

  init() {
    settings = Self.loadSettings()
    connectivity = ConnectivityMonitor(settings: settings)
    UNUserNotificationCenter.current().delegate = presenter
    connectivity.start()
    Task { await requestNotificationPermission() }
  }

  var notificationsAllowed: Bool { notificationStatus == .allowed }

  var notificationStatusText: String {
    switch notificationStatus {
    case .notDetermined: "Уведомления: ждём вашего ответа"
    case .allowed: "Уведомления разрешены"
    case .denied: "Уведомления запрещены"
    case .unavailable: "macOS не даёт включить уведомления"
    }
  }

  /// Человек мог поменять разрешение в Системных настройках — перечитываем при открытии панели.
  func refreshNotificationStatus() {
    Task { notificationStatus = await notifications.currentStatus() }
  }

  func openNotificationSettings() {
    guard let url = Self.notificationSettingsURL else { return }
    NSWorkspace.shared.open(url)
  }

  func sendTestNotification() {
    guard !isSendingTest else { return }
    isSendingTest = true
    Task {
      defer { isSendingTest = false }
      notificationStatus = await notifications.currentStatus()
      guard notificationStatus == .allowed else {
        lastTestResult = "Не отправлено: уведомления не разрешены"
        Log.notifications.notice("Тестовое уведомление не отправлено: уведомления не разрешены")
        return
      }
      do {
        try await notifications.sendTest()
        lastTestResult = "Тестовое уведомление отправлено"
        Log.notifications.notice("Тестовое уведомление отправлено")
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
      Log.notifications.notice("Уведомления разрешены")
    case .denied, .notDetermined:
      Log.notifications.notice("Уведомления не разрешены")
    case .unavailable(let reason):
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
