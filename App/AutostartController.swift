import Foundation
import IPCheckCore
import Observation
import ServiceManagement

/// Автозапуск и перезапуск после сбоя: файл задания launchd, который кладёт `make install`
/// (решение 38). Правила — `Autostart` в IPCheckCore (покрыты тестами), здесь — только macOS.
///
/// «Песочница» не даёт приложению менять файлы вне своей папки, поэтому переключатель хранит
/// выбор человека, а файл задания ставит и снимает `scripts/autostart.sh`.
@MainActor
@Observable
final class AutostartController {
  /// Как запустили этот процесс.
  let source: LaunchSource
  /// Рабочая версия в «Программах»: только у неё есть автозапуск.
  let isAvailable: Bool
  /// Выбор человека: запускать ли IPCHEK при входе и после сбоя (паспорт: по умолчанию — да).
  private(set) var launchAtLogin: Bool
  /// Файл задания глазами macOS.
  private(set) var job: AutostartJobStatus = .notInstalled
  /// Решение о запуске принимается при старте процесса.
  @ObservationIgnored let launchPlan: LaunchPlan

  private static let launchAtLoginKey = "launchAtLogin"

  init() {
    source = LaunchSource(environment: ProcessInfo.processInfo.environment)
    isAvailable = Autostart.isInstalledCopy(
      bundlePath: Bundle.main.bundlePath, bundleID: Bundle.main.bundleIdentifier)
    // Только настоящее «вкл/выкл» (та же проверка, что у остальных настроек); иначе — «вкл».
    var wanted = true
    if let stored = UserDefaults.standard.object(forKey: Self.launchAtLoginKey) {
      if case .bool(let value) = StoredValue(propertyListValue: stored) {
        wanted = value
      } else {
        Log.settings.warning("Неверное значение «запуск при входе» — беру «включён»")
      }
    }
    launchAtLogin = wanted
    launchPlan = Autostart.plan(source: source, launchAtLogin: wanted)
    refreshJobStatus()
  }

  var notice: AutostartNotice { Autostart.notice(isInstalledCopy: isAvailable, job: job) }

  func setLaunchAtLogin(_ enabled: Bool) {
    guard isAvailable, enabled != launchAtLogin else { return }
    launchAtLogin = enabled
    UserDefaults.standard.set(enabled, forKey: Self.launchAtLoginKey)
    Log.launch.notice("Запуск при входе: \(enabled ? "включён" : "выключен", privacy: .public)")
  }

  /// Человек мог выключить IPCHEK в Системных настройках — перечитываем при открытии настроек.
  func refreshJobStatus() {
    guard let home = Self.realHome else {
      job = .notInstalled
      return
    }
    let plist = URL(fileURLWithPath: Autostart.jobPlistPath(home: home))
    job =
      switch SMAppService.statusForLegacyPlist(at: plist) {
      case .enabled: .enabled
      case .requiresApproval: .disabledInSystemSettings
      case .notRegistered, .notFound: .notInstalled
      @unknown default: .notInstalled
      }
  }

  func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  /// Настоящая домашняя папка: в «песочнице» `NSHomeDirectory()` указывает на папку контейнера.
  private static var realHome: String? {
    guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return nil }
    return String(cString: directory)
  }
}
