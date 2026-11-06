import AppKit
import Foundation
import IPCheckCore

/// Как показывать страну: флаг и название по-русски.
enum CountryText {
  private static let locale = Locale(identifier: "ru_RU")

  static func name(_ code: String) -> String {
    locale.localizedString(forRegionCode: code) ?? code
  }

  /// «🇳🇱 Нидерланды».
  static func flagName(_ code: String) -> String {
    let flag = CountryCode.flag(code)
    return flag.isEmpty ? name(code) : "\(flag) \(name(code))"
  }

  /// Строка под IP в панели: текст, цвет и подсказка при наведении.
  static func line(_ verdict: CountryVerdict) -> (text: String, color: NSColor, help: String)? {
    switch verdict {
    case .agreed(let code):
      return (flagName(code), .secondaryLabelColor, "Обе службы согласны")
    case .single(let code):
      return (flagName(code), .secondaryLabelColor, "Определила одна служба: вторая не ответила")
    case .disputed(let first, let second):
      return (
        "⚠︎ \(flagName(first)) или \(flagName(second))", .systemOrange,
        "\(CountryPlan.first.name): \(name(first)), \(CountryPlan.second.name): \(name(second)). "
          + "Службы не согласны — возможна подмена или ошибка базы."
      )
    case .unknown:
      return nil
    }
  }
}
