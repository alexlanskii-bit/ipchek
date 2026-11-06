import Foundation
import UserNotifications

/// Обёртка над системными уведомлениями macOS.
///
/// Методы не привязаны к главному потоку: центр уведомлений берётся внутри каждого вызова,
/// поэтому между потоками ничего не передаётся (требование строгого режима Swift 6).
struct NotificationService: Sendable {
  enum Status: Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
    case failed(String)
  }

  /// Спрашивает разрешение. macOS показывает вопрос только при первом вызове.
  func requestAuthorization() async -> Status {
    do {
      let granted = try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound])
      return granted ? .allowed : .denied
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  /// Текущее состояние разрешения: человек мог поменять его в Системных настройках.
  func currentStatus() async -> Status {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional:
      return .allowed
    case .denied:
      return .denied
    case .notDetermined:
      return .notDetermined
    @unknown default:
      return .failed("неизвестное состояние разрешения")
    }
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
