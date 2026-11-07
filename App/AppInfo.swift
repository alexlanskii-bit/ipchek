import Foundation
import OSLog

enum AppInfo {
  static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
  }

  static let subsystem = Bundle.main.bundleIdentifier ?? "com.lavmoviesstudio.ipchek"
}

/// Журналы приложения. Смотреть: Console.app, фильтр по подсистеме com.lavmoviesstudio.ipchek
/// (подробности — docs/OPERATIONS.md).
enum Log {
  static let settings = Logger(subsystem: AppInfo.subsystem, category: "settings")
  static let notifications = Logger(subsystem: AppInfo.subsystem, category: "notifications")
  static let connectivity = Logger(subsystem: AppInfo.subsystem, category: "connectivity")
  static let address = Logger(subsystem: AppInfo.subsystem, category: "address")
  static let server = Logger(subsystem: AppInfo.subsystem, category: "server")
  /// Запуск, автозапуск, передача работы процессу под присмотром macOS, завершение.
  static let launch = Logger(subsystem: AppInfo.subsystem, category: "launch")
  /// Сон и пробуждение Mac.
  static let power = Logger(subsystem: AppInfo.subsystem, category: "power")
}
