import IPCheckCore

/// Тексты уведомлений. Согласованы с владельцем на наброске этапа 3.
enum NotificationText {
  struct Content: Sendable {
    let title: String
    let body: String
  }

  static func content(_ event: ConnectivityEvent) -> Content {
    Content(title: title(event), body: body(event))
  }

  static func content(_ event: AddressEvent) -> Content {
    switch event {
    case .vpnOn(let interface):
      Content(title: "VPN включён", body: "Подключение через VPN (\(interface)).")
    case .vpnOff:
      Content(title: "VPN отключён", body: "Сайты снова видят ваш настоящий IP.")
    case .externalIPChanged(let region, let old, let new):
      Content(
        title: "Внешний IP изменился",
        body: "Для \(region == .russia ? "российских" : "зарубежных") сайтов: \(old) → \(new).")
    }
  }

  static func content(_ event: ServerEvent) -> Content {
    switch event {
    case .down:
      Content(
        title: "Сервер NL не отвечает",
        body: "Домашний интернет работает, а сервер молчит. VPN может не работать.")
    case .up(let seconds):
      Content(
        title: "Сервер NL снова отвечает",
        body: "Он молчал \(DurationText.short(seconds: seconds)).")
    }
  }

  /// Для журнала — без IP-адресов.
  static func logDescription(_ event: AddressEvent) -> String {
    switch event {
    case .vpnOn(let interface): "VPN включён (\(interface))"
    case .vpnOff: "VPN отключён"
    case .externalIPChanged(let region, _, _): "смена внешнего IP (\(region.rawValue))"
    }
  }

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
