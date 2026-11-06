/// Настройки мониторинга.
public struct MonitorSettings: Equatable, Sendable {
  public var checkIntervalSeconds: Int
  public var failuresBeforeOutage: Int
  public var unstableLatencyMs: Int
  public var unstableLossPercent: Int
  public var soundEnabled: Bool
  public var wakeGraceSeconds: Int
  public var eventRetentionDays: Int
  public var sampleRetentionDays: Int

  public init(
    checkIntervalSeconds: Int,
    failuresBeforeOutage: Int,
    unstableLatencyMs: Int,
    unstableLossPercent: Int,
    soundEnabled: Bool,
    wakeGraceSeconds: Int,
    eventRetentionDays: Int,
    sampleRetentionDays: Int
  ) {
    self.checkIntervalSeconds = checkIntervalSeconds
    self.failuresBeforeOutage = failuresBeforeOutage
    self.unstableLatencyMs = unstableLatencyMs
    self.unstableLossPercent = unstableLossPercent
    self.soundEnabled = soundEnabled
    self.wakeGraceSeconds = wakeGraceSeconds
    self.eventRetentionDays = eventRetentionDays
    self.sampleRetentionDays = sampleRetentionDays
  }

  /// Значения по умолчанию — из паспорта проекта (docs/PROJECT.md, раздел 17).
  public static let defaults = MonitorSettings(
    checkIntervalSeconds: 5,
    failuresBeforeOutage: 3,
    unstableLatencyMs: 300,
    unstableLossPercent: 10,
    soundEnabled: true,
    wakeGraceSeconds: 30,
    eventRetentionDays: 365,
    sampleRetentionDays: 90
  )
}

/// Ключ настройки в хранилище.
public enum SettingsKey: String, CaseIterable, Sendable {
  case checkIntervalSeconds
  case failuresBeforeOutage
  case unstableLatencyMs
  case unstableLossPercent
  case soundEnabled
  case wakeGraceSeconds
  case eventRetentionDays
  case sampleRetentionDays
}

/// Значение, прочитанное из хранилища настроек, до проверки.
public enum StoredValue: Equatable, Sendable {
  case int(Int)
  case bool(Bool)
  /// Значение неподходящего типа; в скобках — что именно нашли (для лога).
  case unsupported(String)
}

/// Проблема с одной настройкой: её значение не принято, вместо него взято значение по умолчанию.
public struct SettingsIssue: Equatable, Sendable {
  public enum Problem: Equatable, Sendable {
    case outOfRange(value: Int, allowed: ClosedRange<Int>)
    case wrongType(found: String)
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

    func int(_ key: SettingsKey, _ allowed: ClosedRange<Int>, default value: Int) -> Int {
      switch stored[key] {
      case nil:
        return value
      case .int(let found) where allowed.contains(found):
        return found
      case .int(let found):
        issues.append(SettingsIssue(key: key, problem: .outOfRange(value: found, allowed: allowed)))
      case .bool:
        issues.append(SettingsIssue(key: key, problem: .wrongType(found: "логическое значение")))
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
      case .unsupported(let found):
        issues.append(SettingsIssue(key: key, problem: .wrongType(found: found)))
      }
      return value
    }

    let settings = MonitorSettings(
      checkIntervalSeconds: int(
        .checkIntervalSeconds, 1...60, default: fallback.checkIntervalSeconds),
      failuresBeforeOutage: int(
        .failuresBeforeOutage, 1...10, default: fallback.failuresBeforeOutage),
      unstableLatencyMs: int(.unstableLatencyMs, 50...5000, default: fallback.unstableLatencyMs),
      unstableLossPercent: int(
        .unstableLossPercent, 1...100, default: fallback.unstableLossPercent),
      soundEnabled: bool(.soundEnabled, default: fallback.soundEnabled),
      wakeGraceSeconds: int(.wakeGraceSeconds, 0...300, default: fallback.wakeGraceSeconds),
      eventRetentionDays: int(
        .eventRetentionDays, 1...3650, default: fallback.eventRetentionDays),
      sampleRetentionDays: int(
        .sampleRetentionDays, 1...3650, default: fallback.sampleRetentionDays)
    )
    return SettingsValidation(settings: settings, issues: issues)
  }
}
