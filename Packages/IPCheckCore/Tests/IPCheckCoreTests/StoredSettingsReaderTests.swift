import Foundation
import IPCheckCore
import Testing

// UserDefaults отдаёт и «вкл/выкл», и числа как NSNumber, поэтому в тестах — NSNumber,
// как в настоящем хранилище.
@Suite("Чтение настроек из хранилища macOS")
struct StoredSettingsReaderTests {
  @Test("«Вкл/выкл» распознаётся как логическое значение")
  func booleanNumberBecomesBool() {
    #expect(StoredValue(propertyListValue: NSNumber(value: true)) == .bool(true))
    #expect(StoredValue(propertyListValue: NSNumber(value: false)) == .bool(false))
  }

  @Test("Целое число, включая 0 и 1, остаётся числом, а не «вкл/выкл»")
  func integerNumberStaysInt() {
    #expect(StoredValue(propertyListValue: NSNumber(value: 0)) == .int(0))
    #expect(StoredValue(propertyListValue: NSNumber(value: 1)) == .int(1))
    #expect(StoredValue(propertyListValue: NSNumber(value: 300)) == .int(300))
  }

  @Test("Дробное число и строка не подходят")
  func fractionAndStringAreUnsupported() {
    #expect(isUnsupported(StoredValue(propertyListValue: NSNumber(value: 2.5))))
    #expect(isUnsupported(StoredValue(propertyListValue: "5")))
  }

  @Test("Читаются только известные ключи, отсутствующие пропускаются")
  func readsOnlyKnownKeys() {
    let raw: [String: Any] = [
      "checkIntervalSeconds": NSNumber(value: 10),
      "soundEnabled": NSNumber(value: false),
      "someOtherKey": NSNumber(value: 1),
    ]

    let stored = MonitorSettings.storedValues(lookup: { raw[$0] })

    #expect(stored == [.checkIntervalSeconds: .int(10), .soundEnabled: .bool(false)])
  }
}

private func isUnsupported(_ value: StoredValue) -> Bool {
  if case .unsupported = value { true } else { false }
}
