import Foundation
import IPCheckCore
import UserNotifications

/// Обёртка над системными уведомлениями macOS.
///
/// Методы не привязаны к главному потоку: центр уведомлений берётся внутри каждого вызова,
/// поэтому между потоками ничего не передаётся (требование строгого режима Swift 6).
struct NotificationService: Sendable {
  /// Спрашивает разрешение. macOS показывает вопрос только при первом вызове.
  func requestAuthorization() async -> NotificationPermission {
    do {
      let granted = try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound])
      return granted ? .allowed : .denied
    } catch {
      Log.notifications.notice(
        "macOS ответила на запрос разрешения ошибкой: \(error.localizedDescription, privacy: .public)"
      )
      let current = await currentStatus()
      return .afterRequestError(error.localizedDescription, currentStatus: current)
    }
  }

  /// Текущее состояние разрешения: человек мог поменять его в Системных настройках.
  func currentStatus() async -> NotificationPermission {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional:
      return .allowed
    case .denied:
      return .denied
    case .notDetermined:
      return .notDetermined
    @unknown default:
      return .unavailable("неизвестное состояние разрешения")
    }
  }

  /// Уведомление о событии связи. Тексты согласованы с владельцем (этап 3).
  func post(_ event: ConnectivityEvent, sound: Bool) async throws {
    let content = UNMutableNotificationContent()
    content.title = NotificationText.title(event)
    content.body = NotificationText.body(event)
    content.threadIdentifier = "connectivity"
    if sound { content.sound = .default }
    let request = UNNotificationRequest(
      identifier: "event-\(UUID().uuidString)", content: content, trigger: nil)
    try await UNUserNotificationCenter.current().add(request)
  }

  func sendTest() async throws {
    let content = UNMutableNotificationContent()
    content.title = "IPCHEK"
    content.body = "Тестовое уведомление: уведомления работают."
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: "test-\(UUID().uuidString)", content: content, trigger: nil)
    try await UNUserNotificationCenter.current().add(request)
  }
}

/// Показывает уведомления, даже когда меню IPCHEK открыто (приложение активно).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }
}
