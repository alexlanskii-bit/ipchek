import Foundation

extension StoredValue {
  /// Переводит значение из системных настроек (UserDefaults) в понятный тип.
  ///
  /// UserDefaults хранит и «вкл/выкл», и числа как NSNumber. «Вкл/выкл» отличаем по внутреннему
  /// типу CFBoolean, иначе 0 и 1 стали бы «выкл» и «вкл».
  public init(propertyListValue value: Any) {
    if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
      self = .bool(number.boolValue)
    } else if let integer = value as? Int {
      self = .int(integer)
    } else if value is NSNumber {
      self = .unsupported("дробное число")
    } else if let text = value as? String {
      self = .string(text)
    } else {
      self = .unsupported(String(describing: type(of: value)))
    }
  }
}

extension MonitorSettings {
  /// Читает сохранённые значения по ключам настроек. `lookup` — например, `UserDefaults.standard.object(forKey:)`.
  public static func storedValues(lookup: (String) -> Any?) -> [SettingsKey: StoredValue] {
    var stored: [SettingsKey: StoredValue] = [:]
    for key in SettingsKey.allCases {
      if let value = lookup(key.rawValue) {
        stored[key] = StoredValue(propertyListValue: value)
      }
    }
    return stored
  }
}
