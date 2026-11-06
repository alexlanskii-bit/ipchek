import AppKit
import IPCheckCore

/// Тексты и значки состояния для панели и строки меню.
enum StatusText {
  static func title(_ snapshot: ConnectivitySnapshot, now: Date) -> String {
    switch snapshot.state {
    case .checking: "Проверяю связь…"
    case .online: "Интернет работает"
    case .unstable: "Связь нестабильна"
    case .partial: "Интернет работает частично"
    case .offline: "Нет интернета · \(duration(since: snapshot.stateSince, now: now))"
    }
  }

  static func reason(_ snapshot: ConnectivitySnapshot, now: Date) -> String {
    switch snapshot.state {
    case .checking:
      snapshot.updatedAt == nil ? "Первая проверка" : "Связь возвращается"
    case .online:
      "Все проверки проходят · \(updatedAgo(snapshot, now: now))"
    case .unstable(.highLatency(let ms, let threshold)):
      "Задержка \(ms) мс (порог \(threshold))"
    case .unstable(.packetLoss(let percent, let threshold)):
      "Потери \(percent) % за минуту (порог \(threshold))"
    case .partial(reachable: .russia):
      "Российские сайты доступны, зарубежные — нет"
    case .partial(reachable: .abroad):
      "Зарубежные сайты доступны, российские — нет"
    case .offline(.noLink):
      "Wi-Fi и кабель отключены"
    case .offline(.serversNotResponding):
      "\(linkName(snapshot.link)) подключён, но серверы не отвечают"
    }
  }

  static func linkName(_ link: LinkStatus?) -> String {
    // Сначала разворачиваем: иначе вариант `.none` путается с «значения нет» у Optional.
    guard let link else { return "—" }
    switch link {
    case .wifi: return "Wi-Fi"
    case .wired: return "Кабель"
    case .other: return "Другое подключение"
    case .none: return "Нет"
    }
  }

  static func region(_ result: RegionResult?) -> (text: String, color: NSColor) {
    switch result {
    case .reachable(let latency, _): ("отвечает · \(latency) мс", .systemGreen)
    case .unreachable: ("не отвечает", .systemRed)
    case nil: ("—", .secondaryLabelColor)
    }
  }

  static func regionLabel(_ name: String, _ result: RegionResult?) -> String {
    if case .reachable(_, let via) = result { return "\(name) · \(via)" }
    return name
  }

  // MARK: - Значок

  struct Icon {
    let symbol: String
    /// `nil` — значок рисуется в цвет строки меню (как системные).
    let color: NSColor?
  }

  static func icon(for state: ConnectionState) -> Icon {
    switch state.kind {
    case .checking: Icon(symbol: "wifi", color: nil)
    case .online: Icon(symbol: "wifi", color: .systemGreen)
    case .unstable, .partial: Icon(symbol: "wifi.exclamationmark", color: .systemYellow)
    case .offline: Icon(symbol: "wifi.slash", color: .systemRed)
    }
  }

  // MARK: - Внутреннее

  private static func duration(since: Date?, now: Date) -> String {
    guard let since else { return "—" }
    return DurationText.short(seconds: Int(now.timeIntervalSince(since)))
  }

  private static func updatedAgo(_ snapshot: ConnectivitySnapshot, now: Date) -> String {
    guard let updatedAt = snapshot.updatedAt else { return "ещё не проверяли" }
    return "\(DurationText.short(seconds: Int(now.timeIntervalSince(updatedAt)))) назад"
  }
}
