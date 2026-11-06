/// Разрешение на уведомления, как его видит приложение.
public enum NotificationPermission: Equatable, Sendable {
  case notDetermined
  case allowed
  case denied
  /// macOS не дала включить уведомления; в скобках — её объяснение.
  case unavailable(String)

  /// Итог запроса разрешения, если macOS ответила ошибкой.
  ///
  /// macOS отвечает ошибкой и тогда, когда человек сам отказал (закрыл запрос или нажал
  /// «Не разрешать»). Поэтому верим решению, которое система сохранила, а «сбой» — только
  /// если решения нет.
  public static func afterRequestError(
    _ message: String, currentStatus: NotificationPermission
  ) -> NotificationPermission {
    switch currentStatus {
    case .allowed, .denied:
      currentStatus
    case .notDetermined, .unavailable:
      .unavailable(message)
    }
  }
}
