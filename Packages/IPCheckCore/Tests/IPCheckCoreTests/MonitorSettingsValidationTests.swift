import IPCheckCore
import Testing

@Suite("Проверка настроек при запуске")
struct MonitorSettingsValidationTests {
  @Test("Пустое хранилище — значения по умолчанию из паспорта, без проблем")
  func emptyStorageGivesPassportDefaults() {
    let result = MonitorSettings.validated(from: [:])

    #expect(result.settings == passportDefaults)
    #expect(result.issues.isEmpty)
  }

  @Test(
    "Значение ровно на границе допустимого сохраняется",
    arguments: [
      IntCase(.checkIntervalSeconds, 1), IntCase(.checkIntervalSeconds, 60),
      IntCase(.failuresBeforeOutage, 1), IntCase(.failuresBeforeOutage, 10),
      IntCase(.unstableLatencyMs, 50), IntCase(.unstableLatencyMs, 5000),
      IntCase(.unstableLossPercent, 1), IntCase(.unstableLossPercent, 100),
      IntCase(.wakeGraceSeconds, 0), IntCase(.wakeGraceSeconds, 300),
      IntCase(.eventRetentionDays, 1), IntCase(.eventRetentionDays, 3650),
      IntCase(.sampleRetentionDays, 1), IntCase(.sampleRetentionDays, 3650),
    ]
  )
  func boundaryValueIsKept(_ example: IntCase) {
    let result = MonitorSettings.validated(from: [example.key: .int(example.value)])

    #expect(intValue(example.key, in: result.settings) == example.value)
    #expect(result.issues.isEmpty)
  }

  @Test("Выключенный звук сохраняется")
  func soundOffIsKept() {
    let result = MonitorSettings.validated(from: [.soundEnabled: .bool(false)])

    #expect(result.settings.soundEnabled == false)
    #expect(result.issues.isEmpty)
  }

  @Test(
    "Значение за границей на единицу — значение по умолчанию и запись о проблеме",
    arguments: [
      RangeCase(.checkIntervalSeconds, 0, fallback: 5, allowed: 1...60),
      RangeCase(.checkIntervalSeconds, 61, fallback: 5, allowed: 1...60),
      RangeCase(.failuresBeforeOutage, 0, fallback: 3, allowed: 1...10),
      RangeCase(.failuresBeforeOutage, 11, fallback: 3, allowed: 1...10),
      RangeCase(.unstableLatencyMs, 49, fallback: 300, allowed: 50...5000),
      RangeCase(.unstableLatencyMs, 5001, fallback: 300, allowed: 50...5000),
      RangeCase(.unstableLossPercent, 0, fallback: 10, allowed: 1...100),
      RangeCase(.unstableLossPercent, 101, fallback: 10, allowed: 1...100),
      RangeCase(.wakeGraceSeconds, -1, fallback: 30, allowed: 0...300),
      RangeCase(.wakeGraceSeconds, 301, fallback: 30, allowed: 0...300),
      RangeCase(.eventRetentionDays, 0, fallback: 365, allowed: 1...3650),
      RangeCase(.eventRetentionDays, 3651, fallback: 365, allowed: 1...3650),
      RangeCase(.sampleRetentionDays, 0, fallback: 90, allowed: 1...3650),
      RangeCase(.sampleRetentionDays, 3651, fallback: 90, allowed: 1...3650),
    ]
  )
  func outOfRangeFallsBackToDefault(_ example: RangeCase) {
    let result = MonitorSettings.validated(from: [example.key: .int(example.value)])

    #expect(intValue(example.key, in: result.settings) == example.fallback)
    #expect(
      result.issues == [
        SettingsIssue(
          key: example.key,
          problem: .outOfRange(value: example.value, allowed: example.allowed)
        )
      ]
    )
  }

  @Test(
    "Значение не того типа — значение по умолчанию и запись о проблеме",
    arguments: [
      TypeCase(.checkIntervalSeconds, .bool(false)),
      TypeCase(.unstableLatencyMs, .unsupported("строка")),
      TypeCase(.soundEnabled, .int(0)),
      TypeCase(.soundEnabled, .unsupported("дробное число")),
    ]
  )
  func wrongTypeFallsBackToDefault(_ example: TypeCase) {
    let result = MonitorSettings.validated(from: [example.key: example.stored])

    #expect(result.settings == passportDefaults)
    #expect(result.issues.map(\.key) == [example.key])
    #expect(result.issues.allSatisfy { if case .wrongType = $0.problem { true } else { false } })
  }

  @Test("Несколько ошибок — каждая сообщается отдельно, правильные настройки не задеты")
  func severalIssuesAreReportedSeparately() {
    let result = MonitorSettings.validated(from: [
      .checkIntervalSeconds: .int(0),
      .unstableLatencyMs: .int(500),
      .soundEnabled: .int(1),
      .sampleRetentionDays: .int(30),
    ])

    var expected = passportDefaults
    expected.unstableLatencyMs = 500
    expected.sampleRetentionDays = 30
    #expect(result.settings == expected)
    #expect(result.issues.map(\.key) == [.checkIntervalSeconds, .soundEnabled])
  }
}

// MARK: - Помощники тестов

/// Значения по умолчанию из паспорта проекта (раздел 17), записаны вручную.
let passportDefaults = MonitorSettings(
  checkIntervalSeconds: 5,
  failuresBeforeOutage: 3,
  unstableLatencyMs: 300,
  unstableLossPercent: 10,
  soundEnabled: true,
  wakeGraceSeconds: 30,
  eventRetentionDays: 365,
  sampleRetentionDays: 90
)

struct RangeCase: Sendable, CustomTestStringConvertible {
  let key: SettingsKey
  let value: Int
  let fallback: Int
  let allowed: ClosedRange<Int>

  init(_ key: SettingsKey, _ value: Int, fallback: Int, allowed: ClosedRange<Int>) {
    self.key = key
    self.value = value
    self.fallback = fallback
    self.allowed = allowed
  }

  var testDescription: String { "\(key.rawValue) = \(value)" }
}

struct TypeCase: Sendable, CustomTestStringConvertible {
  let key: SettingsKey
  let stored: StoredValue

  init(_ key: SettingsKey, _ stored: StoredValue) {
    self.key = key
    self.stored = stored
  }

  var testDescription: String { "\(key.rawValue) = \(stored)" }
}

struct IntCase: Sendable, CustomTestStringConvertible {
  let key: SettingsKey
  let value: Int

  init(_ key: SettingsKey, _ value: Int) {
    self.key = key
    self.value = value
  }

  var testDescription: String { "\(key.rawValue) = \(value)" }
}

/// Читает числовую настройку по ключу. Соответствие записано вручную, отдельно от кода продукта,
/// чтобы перепутанные в продукте настройки ловились тестами.
func intValue(_ key: SettingsKey, in settings: MonitorSettings) -> Int? {
  switch key {
  case .checkIntervalSeconds: settings.checkIntervalSeconds
  case .failuresBeforeOutage: settings.failuresBeforeOutage
  case .unstableLatencyMs: settings.unstableLatencyMs
  case .unstableLossPercent: settings.unstableLossPercent
  case .wakeGraceSeconds: settings.wakeGraceSeconds
  case .eventRetentionDays: settings.eventRetentionDays
  case .sampleRetentionDays: settings.sampleRetentionDays
  case .soundEnabled: nil
  }
}
