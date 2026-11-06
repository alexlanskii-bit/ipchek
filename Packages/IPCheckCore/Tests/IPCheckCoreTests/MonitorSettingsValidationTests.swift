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
      IntCase(.serverPort, 1), IntCase(.serverPort, 65535),
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
      RangeCase(.serverPort, 0, fallback: 443, allowed: 1...65535),
      RangeCase(.serverPort, 65536, fallback: 443, allowed: 1...65535),
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
      TypeCase(.notifyUnstable, .int(0)),
      TypeCase(.checkIntervalSeconds, .string("5")),
      TypeCase(.serverHost, .int(1)),
      TypeCase(.serverCheck, .bool(true)),
    ]
  )
  func wrongTypeFallsBackToDefault(_ example: TypeCase) {
    let result = MonitorSettings.validated(from: [example.key: example.stored])

    #expect(result.settings == passportDefaults)
    #expect(result.issues.map(\.key) == [example.key])
    #expect(result.issues.allSatisfy { if case .wrongType = $0.problem { true } else { false } })
  }

  @Test("Выключенные уведомления о нестабильной связи сохраняются")
  func notifyUnstableOffIsKept() {
    let result = MonitorSettings.validated(from: [.notifyUnstable: .bool(false)])

    #expect(result.settings.notifyUnstable == false)
    #expect(result.issues.isEmpty)
  }

  @Test("Окно настроек и проверка при запуске используют одни и те же диапазоны")
  func allowedRanges() {
    #expect(MonitorSettings.allowedRange(for: .checkIntervalSeconds) == 1...60)
    #expect(MonitorSettings.allowedRange(for: .failuresBeforeOutage) == 1...10)
    #expect(MonitorSettings.allowedRange(for: .unstableLatencyMs) == 50...5000)
    #expect(MonitorSettings.allowedRange(for: .unstableLossPercent) == 1...100)
    #expect(MonitorSettings.allowedRange(for: .wakeGraceSeconds) == 0...300)
    #expect(MonitorSettings.allowedRange(for: .eventRetentionDays) == 1...3650)
    #expect(MonitorSettings.allowedRange(for: .sampleRetentionDays) == 1...3650)
    #expect(MonitorSettings.allowedRange(for: .soundEnabled) == nil)
    #expect(MonitorSettings.allowedRange(for: .notifyUnstable) == nil)
    #expect(MonitorSettings.allowedRange(for: .serverPort) == 1...65535)
    #expect(MonitorSettings.allowedRange(for: .serverHost) == nil)
    #expect(MonitorSettings.allowedRange(for: .serverCheck) == nil)
  }

  @Test("Сохранённые настройки читаются обратно без изменений")
  func storedValuesRoundTrip() {
    let custom = MonitorSettings(
      checkIntervalSeconds: 7, failuresBeforeOutage: 4, unstableLatencyMs: 450,
      unstableLossPercent: 20, soundEnabled: false, notifyUnstable: false, wakeGraceSeconds: 45,
      eventRetentionDays: 200, sampleRetentionDays: 30, serverHost: "vpn.example.com",
      serverCheck: .port, serverPort: 8443)

    let stored = custom.asStoredValues
    let result = MonitorSettings.validated(from: stored)

    #expect(stored.count == SettingsKey.allCases.count)
    #expect(result.settings == custom)
    #expect(result.issues.isEmpty)
  }

  @Test(
    "Адрес сервера — IP или имя — сохраняется, пробелы по краям убираются",
    arguments: [
      ("203.0.113.5", "203.0.113.5"), ("vpn.example.com", "vpn.example.com"),
      ("2001:db8::1", "2001:db8::1"), ("  vpn.example.com \n", "vpn.example.com"), ("", ""),
    ])
  func serverHostKept(stored: String, expected: String) {
    let result = MonitorSettings.validated(from: [.serverHost: .string(stored)])

    #expect(result.settings.serverHost == expected)
    #expect(result.issues.isEmpty)
  }

  @Test("Неверный адрес сервера — пусто и запись о проблеме, но без самого адреса")
  func invalidServerHost() {
    let result = MonitorSettings.validated(from: [.serverHost: .string("bad host!")])

    #expect(result.settings.serverHost == "")
    #expect(result.issues == [SettingsIssue(key: .serverHost, problem: .invalidText)])
    #expect(result.issues.first.map { !$0.logDescription.contains("bad host") } == true)
  }

  @Test("Способ проверки сервера: известное значение сохраняется, неизвестное — «автоматически»")
  func serverCheckMethod() {
    let port = MonitorSettings.validated(from: [.serverCheck: .string("port")])
    // «ping» больше не поддерживается (песочница macOS) — как и любое неизвестное значение.
    let unknown = MonitorSettings.validated(from: [.serverCheck: .string("ping")])

    #expect(port.settings.serverCheck == .port)
    #expect(port.issues.isEmpty)
    #expect(unknown.settings.serverCheck == .auto)
    #expect(unknown.issues == [SettingsIssue(key: .serverCheck, problem: .invalidText)])
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
  notifyUnstable: true,
  wakeGraceSeconds: 30,
  eventRetentionDays: 365,
  sampleRetentionDays: 90,
  serverHost: "",
  serverCheck: .auto,
  serverPort: 443
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
  case .serverPort: settings.serverPort
  case .soundEnabled, .notifyUnstable, .serverHost, .serverCheck: nil
  }
}
