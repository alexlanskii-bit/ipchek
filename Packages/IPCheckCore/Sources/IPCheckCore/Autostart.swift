import Foundation

/// Кто запустил этот процесс IPCHEK.
public enum LaunchSource: Equatable, Sendable {
  /// macOS по файлу автозапуска: при входе в систему, после сбоя или после `make install`.
  case agent
  /// Человек: Dock, Spotlight, Launchpad, `make run`.
  case user

  /// Переменная окружения, которую задаёт файл автозапуска (`scripts/autostart.plist`).
  public static let environmentKey = "IPCHEK_LAUNCHED_BY"
  public static let agentValue = "agent"

  public init(environment: [String: String]) {
    self = environment[Self.environmentKey] == Self.agentValue ? .agent : .user
  }
}

/// Что сделать сразу после запуска.
public enum LaunchPlan: Equatable, Sendable {
  /// Работать; `showWindow` — показать окно состояния (запустил человек, решение владельца).
  case run(showWindow: Bool)
  /// Запустила macOS, а человек выключил «Запускать при входе»: штатно выйти сразу.
  /// Код выхода 0 — launchd не принимает это за сбой и не запускает IPCHEK снова.
  case quit
}

/// Файл автозапуска глазами macOS (`SMAppService.statusForLegacyPlist`).
public enum AutostartJobStatus: Equatable, Sendable, CaseIterable {
  /// Файл на месте и разрешён.
  case enabled
  /// Человек выключил IPCHEK в Системных настройках → Основные → Объекты входа.
  case disabledInSystemSettings
  /// Файла нет: рабочую версию ставили не через `make install` (или до этапа 7).
  case notInstalled
}

/// Подсказка под переключателем «Запускать при входе».
public enum AutostartNotice: Equatable, Sendable {
  /// У отладочной версии и у копии вне «Программ» автозапуска нет.
  case onlyInstalledCopy
  case runMakeInstall
  case disabledInSystemSettings
  /// Выбор действует со следующего входа в систему (или со следующего сбоя).
  case appliesAtNextLogin
}

/// Автозапуск и перезапуск после сбоя (этап 7, решение 38).
///
/// Как устроено: `make install` кладёт файл задания launchd в `~/Library/LaunchAgents`
/// (`scripts/autostart.sh`). launchd запускает IPCHEK при входе в систему и перезапускает после
/// сбоя (`KeepAlive` → `SuccessfulExit = false`); штатный выход («Выйти», выключение Mac,
/// сигнал SIGTERM) — код 0, его launchd не перезапускает. Переключатель в настройках IPCHEK
/// хранит выбор человека: если автозапуск выключен, запущенная macOS копия сразу выходит.
///
/// Почему не `SMAppService`: при подписи без Apple ID macOS привязывает его задание к отпечатку
/// сборки, и после пересборки задание не запускается («spawn failed», код 78) — проверено
/// 2026-11-07. Файл с обычным путём к программе такой привязки не имеет.
public enum Autostart {
  /// Метка задания launchd и имя файла в `~/Library/LaunchAgents`.
  public static let jobLabel = "com.lavmoviesstudio.ipchek.autostart"
  /// Идентификатор рабочей версии: у отладочной (IPCHEK Dev) автозапуска нет.
  public static let installedBundleID = "com.lavmoviesstudio.ipchek"

  /// Автозапуск — только у рабочей версии, установленной в «Программы»: файл задания указывает
  /// именно на неё.
  public static func isInstalledCopy(bundlePath: String, bundleID: String?) -> Bool {
    bundleID == installedBundleID && bundlePath.hasPrefix("/Applications/")
  }

  public static func plan(source: LaunchSource, launchAtLogin: Bool) -> LaunchPlan {
    switch source {
    case .agent: launchAtLogin ? .run(showWindow: false) : .quit
    case .user: .run(showWindow: true)
    }
  }

  public static func notice(isInstalledCopy: Bool, job: AutostartJobStatus) -> AutostartNotice {
    guard isInstalledCopy else { return .onlyInstalledCopy }
    switch job {
    case .enabled: return .appliesAtNextLogin
    case .disabledInSystemSettings: return .disabledInSystemSettings
    case .notInstalled: return .runMakeInstall
    }
  }

  /// `home` — настоящая домашняя папка (в «песочнице» `NSHomeDirectory()` — папка контейнера).
  public static func jobPlistPath(home: String) -> String {
    let trimmed = home.hasSuffix("/") ? String(home.dropLast()) : home
    return "\(trimmed)/Library/LaunchAgents/\(jobLabel).plist"
  }
}
