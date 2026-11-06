/// Настройки мониторинга.
public struct MonitorSettings: Equatable, Sendable {
  public var checkIntervalSeconds: Int
  public var failuresBeforeOutage: Int
  public var unstableLatencyMs: Int
  public var unstableLossPercent: Int
  public var soundEnabled: Bool
  /// Уведомлять о нестабильной связи (не чаще раза в 10 минут).
  public var notifyUnstable: Bool
  public var wakeGraceSeconds: Int
  public var eventRetentionDays: Int
  public var sampleRetentionDays: Int
  /// Адрес VPN-сервера в Нидерландах (IP или имя); пусто — сервер не проверяется.
  public var serverHost: String
  public var serverCheck: ServerCheckMethod
  /// Порт для способа «только мой порт».
  public var serverPort: Int

  public init(
    checkIntervalSeconds: Int,
    failuresBeforeOutage: Int,
    unstableLatencyMs: Int,
    unstableLossPercent: Int,
    soundEnabled: Bool,
    notifyUnstable: Bool,
    wakeGraceSeconds: Int,
    eventRetentionDays: Int,
    sampleRetentionDays: Int,
    serverHost: String = "",
    serverCheck: ServerCheckMethod = .auto,
    serverPort: Int = 443
  ) {
    self.checkIntervalSeconds = checkIntervalSeconds
    self.failuresBeforeOutage = failuresBeforeOutage
    self.unstableLatencyMs = unstableLatencyMs
    self.unstableLossPercent = unstableLossPercent
    self.soundEnabled = soundEnabled
    self.notifyUnstable = notifyUnstable
    self.wakeGraceSeconds = wakeGraceSeconds
    self.eventRetentionDays = eventRetentionDays
    self.sampleRetentionDays = sampleRetentionDays
    self.serverHost = serverHost
    self.serverCheck = serverCheck
    self.serverPort = serverPort
  }

  /// Значения по умолчанию — из паспорта проекта (docs/PROJECT.md, раздел 17).
  public static let defaults = MonitorSettings(
    checkIntervalSeconds: 5,
    failuresBeforeOutage: 3,
    unstableLatencyMs: 300,
    unstableLossPercent: 10,
    soundEnabled: true,
    notifyUnstable: true,
    wakeGraceSeconds: 30,
    eventRetentionDays: 365,
    sampleRetentionDays: 90,
    serverHost: "",
    serverCheck: .auto,
    serverPort: 443
  )
}

/// Ключ настройки в хранилище.
public enum SettingsKey: String, CaseIterable, Sendable {
  case checkIntervalSeconds
  case failuresBeforeOutage
  case unstableLatencyMs
  case unstableLossPercent
  case soundEnabled
  case notifyUnstable
  case wakeGraceSeconds
  case eventRetentionDays
  case sampleRetentionDays
  case serverHost
  case serverCheck
  case serverPort
}

/// Значение, прочитанное из хранилища настроек, до проверки.
public enum StoredValue: Equatable, Sendable {
  case int(Int)
  case bool(Bool)
  case string(String)
  /// Значение неподходящего типа; в скобках — что именно нашли (для лога).
  case unsupported(String)
}

/// Проблема с одной настройкой: её значение не принято, вместо него взято значение по умолчанию.
public struct SettingsIssue: Equatable, Sendable {
  public enum Problem: Equatable, Sendable {
    case outOfRange(value: Int, allowed: ClosedRange<Int>)
    case wrongType(found: String)
    /// Неверный текст. Сам текст не сохраняем: это может быть адрес сервера.
    case invalidText
  }

  public let key: SettingsKey
  public let problem: Problem

  public init(key: SettingsKey, problem: Problem) {
    self.key = key
    self.problem = problem
  }

  /// Текст для журнала.
  public var logDescription: String {
    switch problem {
    case .outOfRange(let value, let allowed):
      "Настройка \(key.rawValue): значение \(value) вне диапазона "
        + "\(allowed.lowerBound)…\(allowed.upperBound), взято значение по умолчанию"
    case .wrongType(let found):
      "Настройка \(key.rawValue): неподходящий тип (\(found)), взято значение по умолчанию"
    case .invalidText:
      "Настройка \(key.rawValue): неверное значение, взято значение по умолчанию"
    }
  }
}

/// Итог проверки: принятые настройки и список проблем.
public struct SettingsValidation: Equatable, Sendable {
  public let settings: MonitorSettings
  public let issues: [SettingsIssue]
}

extension MonitorSettings {
  /// Проверяет сохранённые значения. Неверное или отсутствующее значение заменяется значением по умолчанию.
  public static func validated(from stored: [SettingsKey: StoredValue]) -> SettingsValidation {
    let fallback = MonitorSettings.defaults
    var issues: [SettingsIssue] = []

    func int(_ key: SettingsKey, default value: Int) -> Int {
      let allowed = allowedRange(for: key) ?? value...value
      switch stored[key] {
      case nil:
        return value
      case .int(let found) where allowed.contains(found):
        return found
      case .int(let found):
        issues.append(SettingsIssue(key: key, problem: .outOfRange(value: found, allowed: allowed)))
      case .bool:
        issues.append(SettingsIssue(key: key, problem: .wrongType(found: "логическое значение")))
      case .string:
        issues.append(SettingsIssue(key: key, problem: .wrongType(found: "строка")))
      case .unsupported(let found):
        issues.append(SettingsIssue(key: key, problem: .wrongType(found: found)))
      }
      return value
    }

    func bool(_ key: SettingsKey, default value: Bool) -> Bool {
      switch stored[key] {
      case nil:
        return value
      case .bool(let found):
        return found
      case .int:
        // Число вместо «вкл/выкл» не угадываем: 0 мог означать что угодно.
        issues.append(SettingsIssue(key: key, problem: .wrongType(found: "число")))
      case .string:
        issues.append(SettingsIssue(key: key, problem: .wrongType(found: "строка")))
      case .unsupported(let found):
        issues.append(SettingsIssue(key: key, problem: .wrongType(found: found)))
      }
      return value
    }

    func text(_ key: SettingsKey, default value: String, accept: (String) -> String?) -> String {
      switch stored[key] {
      case nil:
        return value
      case .string(let found):
        if let accepted = accept(found) { return accepted }
        issues.append(SettingsIssue(key: key, problem: .invalidText))
      case .int:
        issues.append(SettingsIssue(key: key, problem: .wrongType(found: "число")))
      case .bool:
        issues.append(SettingsIssue(key: key, problem: .wrongType(found: "логическое значение")))
      case .unsupported(let found):
        issues.append(SettingsIssue(key: key, problem: .wrongType(found: found)))
      }
      return value
    }

    let checkRaw = text(.serverCheck, default: fallback.serverCheck.rawValue) {
      ServerCheckMethod(rawValue: $0)?.rawValue
    }
    let settings = MonitorSettings(
      checkIntervalSeconds: int(.checkIntervalSeconds, default: fallback.checkIntervalSeconds),
      failuresBeforeOutage: int(.failuresBeforeOutage, default: fallback.failuresBeforeOutage),
      unstableLatencyMs: int(.unstableLatencyMs, default: fallback.unstableLatencyMs),
      unstableLossPercent: int(.unstableLossPercent, default: fallback.unstableLossPercent),
      soundEnabled: bool(.soundEnabled, default: fallback.soundEnabled),
      notifyUnstable: bool(.notifyUnstable, default: fallback.notifyUnstable),
      wakeGraceSeconds: int(.wakeGraceSeconds, default: fallback.wakeGraceSeconds),
      eventRetentionDays: int(.eventRetentionDays, default: fallback.eventRetentionDays),
      sampleRetentionDays: int(.sampleRetentionDays, default: fallback.sampleRetentionDays),
      serverHost: text(.serverHost, default: fallback.serverHost) { found in
        // Пустой адрес — «сервер не задан», это допустимо.
        found.allSatisfy(\.isWhitespace) ? "" : ServerAddress.normalize(found)
      },
      serverCheck: ServerCheckMethod(rawValue: checkRaw) ?? fallback.serverCheck,
      serverPort: int(.serverPort, default: fallback.serverPort)
    )
    return SettingsValidation(settings: settings, issues: issues)
  }
}

extension MonitorSettings {
  /// Допустимый диапазон числовой настройки; `nil` — настройка «вкл/выкл».
  public static func allowedRange(for key: SettingsKey) -> ClosedRange<Int>? {
    switch key {
    case .checkIntervalSeconds: 1...60
    case .failuresBeforeOutage: 1...10
    case .unstableLatencyMs: 50...5000
    case .unstableLossPercent: 1...100
    case .wakeGraceSeconds: 0...300
    case .eventRetentionDays, .sampleRetentionDays: 1...3650
    case .serverPort: 1...65535
    case .soundEnabled, .notifyUnstable, .serverHost, .serverCheck: nil
    }
  }

  /// Настройки в виде значений для хранилища (обратная операция к `validated(from:)`).
  public var asStoredValues: [SettingsKey: StoredValue] {
    [
      .checkIntervalSeconds: .int(checkIntervalSeconds),
      .failuresBeforeOutage: .int(failuresBeforeOutage),
      .unstableLatencyMs: .int(unstableLatencyMs),
      .unstableLossPercent: .int(unstableLossPercent),
      .soundEnabled: .bool(soundEnabled),
      .notifyUnstable: .bool(notifyUnstable),
      .wakeGraceSeconds: .int(wakeGraceSeconds),
      .eventRetentionDays: .int(eventRetentionDays),
      .sampleRetentionDays: .int(sampleRetentionDays),
      .serverHost: .string(serverHost),
      .serverCheck: .string(serverCheck.rawValue),
      .serverPort: .int(serverPort),
    ]
  }
}
