import IPCheckCore

/// Тексты уведомлений. Согласованы с владельцем на наброске этапа 3.
enum NotificationText {
  static func title(_ event: ConnectivityEvent) -> String {
    switch event {
    case .outage: "Интернет пропал"
    case .restored: "Интернет вернулся"
    case .unstable: "Связь нестабильна"
    case .partial(reachable: .russia): "Зарубежные сайты недоступны"
    case .partial(reachable: .abroad): "Российские сайты недоступны"
    case .partialResolved: "Все сайты снова доступны"
    }
  }

  static func body(_ event: ConnectivityEvent) -> String {
    switch event {
    case .outage(.noLink, _):
      "Wi-Fi и кабель отключены."
    case .outage(.serversNotResponding, let link):
      "\(StatusText.linkName(link)) подключён, но сайты не отвечают."
    case .restored(let seconds):
      "Его не было \(DurationText.short(seconds: seconds))."
    case .unstable(.highLatency(let ms, let threshold)):
      "Задержка \(ms) мс (порог \(threshold))."
    case .unstable(.packetLoss(let percent, let threshold)):
      "Потери \(percent) % за минуту (порог \(threshold))."
    case .partial(reachable: .russia):
      "Российские работают. Возможно, дело в VPN."
    case .partial(reachable: .abroad):
      "Зарубежные работают."
    case .partialResolved(let unreachable, let seconds):
      "\(unreachable == .abroad ? "Зарубежные" : "Российские") не открывались \(DurationText.short(seconds: seconds))."
    }
  }
}
