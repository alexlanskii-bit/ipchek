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
    case .vpnOn(let interface, let country):
      Content(
        title: "VPN включён",
        body: country.map { "Зарубежные сайты видят вас из страны: \(CountryText.flagName($0))." }
          ?? "Подключение через VPN (\(interface)).")
    case .vpnOff(let country):
      Content(
        title: "VPN отключён",
        body: "Сайты снова видят ваш настоящий IP"
          + (country.map { " — \(CountryText.flagName($0))" } ?? "") + ".")
    case .externalIPChanged(let region, let old, let new, let country):
      Content(
        title: "Внешний IP изменился",
        body: "Для \(sites(region)) сайтов: \(old) → \(new)"
          + (country.map { " (\(CountryText.flagName($0)))" } ?? "") + ".")
    case .countryChanged(let region, let old, let new, let ip):
      Content(
        title: "Страна внешнего IP изменилась",
        body: "Для \(sites(region)) сайтов: \(CountryText.flagName(old)) → "
          + "\(CountryText.flagName(new))" + (ip.map { " (IP \($0))" } ?? "") + ".")
    case .countryDisputed(let region, let first, let second, let ip):
      Content(
        title: "Службы не согласны о стране IP",
        body: "Для \(sites(region)) сайтов" + (ip.map { " (IP \($0))" } ?? "") + ": "
          + "\(CountryPlan.first.name) — \(CountryText.flagName(first)), "
          + "\(CountryPlan.second.name) — \(CountryText.flagName(second)). "
          + "Возможна подмена или ошибка базы.")
    }
  }

  private static func sites(_ region: Region) -> String {
    region == .russia ? "российских" : "зарубежных"
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
    case .vpnOn(let interface, let country): "VPN включён (\(interface), \(country ?? "страна —"))"
    case .vpnOff(let country): "VPN отключён (\(country ?? "страна —"))"
    case .externalIPChanged(let region, _, _, let country):
      "смена внешнего IP (\(region.rawValue), \(country ?? "страна —"))"
    case .countryChanged(let region, let old, let new, _):
      "смена страны (\(region.rawValue)): \(old) → \(new)"
    case .countryDisputed(let region, let first, let second, _):
      "службы не согласны (\(region.rawValue)): \(first) / \(second)"
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
