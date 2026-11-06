import AppKit
import Foundation
import IPCheckCore
import Observation
import UserNotifications

/// Состояние приложения для интерфейса.
@MainActor
@Observable
final class AppModel {
  private(set) var settings: MonitorSettings
  let connectivity: ConnectivityMonitor
  let addresses = AddressMonitor()
  let server: ServerMonitor
  private(set) var notificationStatus: NotificationPermission = .notDetermined
  private(set) var isSendingTest = false
  private(set) var lastTestResult: String?

  private let notifications = NotificationService()
  private var policy = NotificationPolicy()
  private var addressPolicy = AddressPolicy()
  private var serverPolicy = ServerPolicy()
  /// Центр уведомлений хранит делегата слабой ссылкой, поэтому держим его здесь.
  private let presenter = NotificationPresenter()

  /// Раздел «Уведомления» Системных настроек. Идентификатор и разрешение на такие ссылки
  /// (`allowsXAppleSystemPreferencesURLScheme`) сверены по NotificationsSettings.appex в macOS 26.2.
  private static let notificationSettingsURL = URL(
    string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")

  init() {
    let loaded = Self.loadSettings()
    settings = loaded
    connectivity = ConnectivityMonitor(settings: loaded)
    server = ServerMonitor(settings: loaded)
    UNUserNotificationCenter.current().delegate = presenter
    connectivity.onSnapshot = { [weak self] snapshot in self?.handle(snapshot) }
    addresses.preferredInterface = { [weak connectivity] in connectivity?.primaryInterface }
    addresses.onSnapshot = { [weak self] snapshot in self?.handle(snapshot) }
    server.directInterface = { [weak connectivity] in connectivity?.primaryNWInterface }
    server.onSnapshot = { [weak self] snapshot in self?.handle(snapshot) }
    server.onReset = { [weak self] in self?.serverPolicy = ServerPolicy() }
    connectivity.start()
    addresses.start()
    server.start()
    Task { await requestNotificationPermission() }
  }

  var notificationsAllowed: Bool { notificationStatus == .allowed }

  // MARK: - Настройки

  /// Меняет одну настройку: проверка теми же правилами, что при запуске → сохранение → применение.
  func change<Value>(_ keyPath: WritableKeyPath<MonitorSettings, Value>, to value: Value) {
    var changed = settings
    changed[keyPath: keyPath] = value
    apply(changed)
  }

  /// Сброс параметров проверки и уведомлений. Адрес и способ проверки сервера сохраняются:
  /// это не порог, который хочется вернуть, а данные, которые человек вписал сам.
  func resetSettings() {
    apply(defaultsKeepingServer)
  }

  var settingsAreDefault: Bool { settings == defaultsKeepingServer }

  private var defaultsKeepingServer: MonitorSettings {
    var reset = MonitorSettings.defaults
    reset.serverHost = settings.serverHost
    reset.serverCheck = settings.serverCheck
    reset.serverPort = settings.serverPort
    return reset
  }

  private func apply(_ candidate: MonitorSettings) {
    let validation = MonitorSettings.validated(from: candidate.asStoredValues)
    for issue in validation.issues {
      Log.settings.warning("\(issue.logDescription, privacy: .public)")
    }
    guard validation.settings != settings else { return }
    settings = validation.settings
    Self.save(settings)
    connectivity.apply(settings: settings)
    server.apply(settings: settings)
    Log.settings.notice("Настройки изменены")
  }

  private static func save(_ settings: MonitorSettings) {
    let defaults = UserDefaults.standard
    for (key, value) in settings.asStoredValues {
      switch value {
      case .int(let number): defaults.set(number, forKey: key.rawValue)
      case .bool(let flag): defaults.set(flag, forKey: key.rawValue)
      case .string(let text): defaults.set(text, forKey: key.rawValue)
      case .unsupported: break  // asStoredValues такого не возвращает
      }
    }
  }

  // MARK: - Уведомления о связи

  private func handle(_ snapshot: ConnectivitySnapshot) {
    switch snapshot.state.kind {
    case .online, .unstable, .partial:
      addresses.internetAvailable = true
      server.internetWorking = true
    case .offline:
      addresses.internetAvailable = false
      server.internetWorking = false
    case .checking: break
    }
    let events = policy.observe(snapshot, at: .now, notifyUnstable: settings.notifyUnstable)
    for event in events {
      Log.notifications.notice("Событие: \(String(describing: event), privacy: .public)")
    }
    post(events.map(NotificationText.content))
  }

  private func handle(_ snapshot: AddressSnapshot) {
    let events = addressPolicy.observe(snapshot, at: .now)
    for event in events {
      // Без самих адресов: в журнал IP не пишем.
      Log.notifications.notice(
        "Событие: \(NotificationText.logDescription(event), privacy: .public)")
    }
    post(events.map(NotificationText.content))
  }

  private func handle(_ snapshot: ServerSnapshot) {
    let events = serverPolicy.observe(snapshot, at: .now)
    for event in events {
      Log.notifications.notice("Событие: сервер — \(String(describing: event), privacy: .public)")
    }
    post(events.map(NotificationText.content))
  }

  /// Одна задача на все уведомления — они приходят в том же порядке.
  private func post(_ contents: [NotificationText.Content]) {
    guard !contents.isEmpty else { return }
    let sound = settings.soundEnabled
    Task {
      for content in contents {
        do {
          try await notifications.post(content, sound: sound)
        } catch {
          Log.notifications.error(
            "Уведомление не отправлено: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
  }

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
