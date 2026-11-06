import IPCheckCore
import Testing

// Факт из журнала macOS 26: если запрос закрыть крестиком или нажать «Не разрешать»,
// macOS сохраняет отказ и отвечает на запрос ошибкой «Notifications are not allowed».
@Suite("Разрешение на уведомления после ошибки запроса")
struct NotificationPermissionTests {
  @Test("Отказ, сохранённый системой, показывается как «запрещены», а не как сбой")
  func storedDenialWins() {
    let result = NotificationPermission.afterRequestError(
      "Notifications are not allowed for this application", currentStatus: .denied)

    #expect(result == .denied)
  }

  @Test("Разрешение, сохранённое системой, показывается как «разрешены»")
  func storedAllowWins() {
    let result = NotificationPermission.afterRequestError("любая ошибка", currentStatus: .allowed)

    #expect(result == .allowed)
  }

  @Test("Если решения в системе нет — это сбой, и текст ошибки сохраняется для журнала")
  func noStoredDecisionIsUnavailable() {
    let result = NotificationPermission.afterRequestError(
      "текст ошибки", currentStatus: .notDetermined)

    #expect(result == .unavailable("текст ошибки"))
  }
}
