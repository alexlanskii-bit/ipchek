import Foundation

/// Что известно об адресах Mac в данный момент.
public struct AddressSnapshot: Equatable, Sendable {
  public var localIP: String?
  /// Имя VPN-интерфейса, если VPN включён.
  public var vpnInterface: String?
  /// Внешний IP, каким его видят российские сайты.
  public var russiaIP: String?
  /// Внешний IP, каким его видят зарубежные сайты.
  public var abroadIP: String?
  /// Страна российского и зарубежного внешнего IP — по двум службам со сверкой.
  public var russiaCountry: CountryVerdict
  public var abroadCountry: CountryVerdict

  public init(
    localIP: String? = nil, vpnInterface: String? = nil, russiaIP: String? = nil,
    abroadIP: String? = nil, russiaCountry: CountryVerdict = .unknown,
    abroadCountry: CountryVerdict = .unknown
  ) {
    self.localIP = localIP
    self.vpnInterface = vpnInterface
    self.russiaIP = russiaIP
    self.abroadIP = abroadIP
    self.russiaCountry = russiaCountry
    self.abroadCountry = abroadCountry
  }

  public func externalIP(_ region: Region) -> String? {
    switch region {
    case .russia: russiaIP
    case .abroad: abroadIP
    }
  }

  public func country(_ region: Region) -> CountryVerdict {
    switch region {
    case .russia: russiaCountry
    case .abroad: abroadCountry
    }
  }
}

/// Событие об адресах, о котором стоит сообщить.
public enum AddressEvent: Equatable, Sendable {
  /// `abroadCountry` — страна, которую теперь видят зарубежные сайты (если известна).
  case vpnOn(interface: String, abroadCountry: String?)
  case vpnOff(abroadCountry: String?)
  /// IP сменился, страна прежняя (или неизвестна).
  case externalIPChanged(Region, from: String, to: String, country: String?)
  /// Сменилась страна внешнего IP (решение владельца — сообщать).
  case countryChanged(Region, from: String, to: String, ip: String?)
  /// Две службы назвали разные страны (решение владельца — сообщать).
  case countryDisputed(Region, first: String, second: String, ip: String?)
}

/// Решает, о каких изменениях VPN и внешнего IP сообщать.
public struct AddressPolicy: Sendable {
  /// VPN считается включённым/выключенным, если новое состояние держится 10 секунд.
  public static let vpnStableSeconds: TimeInterval = 10
  /// Смена внешнего IP в течение 2 минут после изменения VPN объясняется им — отдельно не сообщаем.
  public static let vpnExplainsIPChangeSeconds: TimeInterval = 120
  /// О смене IP одного региона — не чаще раза в 10 минут.
  public static let repeatCooldown: TimeInterval = 600

  /// Подтверждённое состояние VPN; `nil` — ещё не наблюдали (после запуска).
  private var confirmedVPN: Bool?
  /// Новое состояние VPN, которое ещё не продержалось 10 секунд.
  private var pendingVPN: (active: Bool, since: Date)?
  /// Когда VPN в последний раз менялся по-настоящему (интерфейс пропал или появился).
  private var lastVPNChange: Date?
  /// Какую страну назвало последнее уведомление о VPN и когда оно ушло.
  private var vpnNotice: (country: String?, at: Date)?
  private var lastKnownIP: [Region: String] = [:]
  private var lastIPNotice: [Region: Date] = [:]
  private var lastKnownCountry: [Region: String] = [:]
  /// Последний ответ служб о стране (кроме «неизвестно»): то же расхождение повторно не сообщаем.
  private var lastVerdict: [Region: CountryVerdict] = [:]
  private var lastDisputeNotice: [Region: Date] = [:]

  public init() {}

  public mutating func observe(_ snapshot: AddressSnapshot, at time: Date) -> [AddressEvent] {
    var events: [AddressEvent] = []
    if let event = observeVPN(snapshot, at: time) {
      events.append(event)
    }
    for region in Region.allCases {
      events += observeRegion(snapshot, region: region, at: time)
    }
    return events
  }

  /// Страна и IP одного региона. Смена страны важнее смены IP: если сменилось и то и другое,
  /// приходит одно уведомление — о стране.
  private mutating func observeRegion(_ snapshot: AddressSnapshot, region: Region, at time: Date)
    -> [AddressEvent]
  {
    var events: [AddressEvent] = []
    let ip = snapshot.externalIP(region)
    let verdict = snapshot.country(region)

    // Расхождение служб — сигнал проверить, а не смена: сообщаем даже сразу после запуска.
    if case .disputed(let first, let second) = verdict, lastVerdict[region] != verdict,
      isCooledDown(lastDisputeNotice[region], at: time)
    {
      lastDisputeNotice[region] = time
      events.append(.countryDisputed(region, first: first, second: second, ip: ip))
    }
    if verdict != .unknown { lastVerdict[region] = verdict }

    var countryChanged = false
    if let country = verdict.effective {
      if let old = lastKnownCountry[region], old != country {
        countryChanged = true
        if !isExplainedByVPN(at: time) || contradictsVPNNotice(country, region: region) {
          events.append(.countryChanged(region, from: old, to: country, ip: ip))
        }
      }
      lastKnownCountry[region] = country
    }

    if let event = observeIP(
      ip, region: region, country: verdict.effective, silent: countryChanged, at: time)
    {
      events.append(event)
    }
    return events
  }

  private func isExplainedByVPN(at time: Date) -> Bool {
    guard let change = lastVPNChange else { return false }
    return time.timeIntervalSince(change) < Self.vpnExplainsIPChangeSeconds
  }

  /// Уведомление об этом изменении VPN уже ушло и назвало другую страну (или никакую): например,
  /// маршруты переключились позже, чем оно ушло. Верную страну сообщаем отдельно.
  private func contradictsVPNNotice(_ country: String, region: Region) -> Bool {
    guard region == .abroad, let notice = vpnNotice, let change = lastVPNChange,
      notice.at >= change
    else { return false }
    return notice.country != country
  }

  private func isCooledDown(_ last: Date?, at time: Date) -> Bool {
    guard let last else { return true }
    return time.timeIntervalSince(last) >= Self.repeatCooldown
  }

  private mutating func observeVPN(_ snapshot: AddressSnapshot, at time: Date) -> AddressEvent? {
    let interface = snapshot.vpnInterface
    let active = interface != nil
    guard let confirmed = confirmedVPN else {
      confirmedVPN = active  // первое наблюдение после запуска — без уведомления
      return nil
    }
    guard active != confirmed else {
      pendingVPN = nil  // VPN мигнул и вернулся
      return nil
    }
    guard let pending = pendingVPN, pending.active == active else {
      pendingVPN = (active, time)
      lastVPNChange = time
      return nil
    }
    guard time.timeIntervalSince(pending.since) >= Self.vpnStableSeconds else { return nil }
    confirmedVPN = active
    pendingVPN = nil
    let country = snapshot.abroadCountry.effective
    vpnNotice = (country, time)
    if let interface { return .vpnOn(interface: interface, abroadCountry: country) }
    return .vpnOff(abroadCountry: country)
  }

  /// `silent` — об этой смене уже сказано уведомлением о стране.
  private mutating func observeIP(
    _ ip: String?, region: Region, country: String?, silent: Bool, at time: Date
  ) -> AddressEvent? {
    guard let ip else { return nil }  // не удалось узнать — это не смена
    guard let old = lastKnownIP[region] else {
      lastKnownIP[region] = ip
      return nil
    }
    guard old != ip else { return nil }
    lastKnownIP[region] = ip
    guard !silent, !isExplainedByVPN(at: time), isCooledDown(lastIPNotice[region], at: time)
    else { return nil }
    lastIPNotice[region] = time
    return .externalIPChanged(region, from: old, to: ip, country: country)
  }
}

/// Откуда и как часто узнавать внешний IP.
///
/// Только HTTPS. Ответ сверяется строгим разбором `IPAddressText` и должен быть публичным
/// адресом (`IPAddressText.isPublic`).
public enum AddressPlan {
  public static let refreshSeconds: TimeInterval = 60
  /// После смены VPN или локального IP — ещё раз через 5 секунд: сразу после смены маршруты
  /// могут быть ещё старыми, и служба назовёт прежний адрес.
  public static let settleSeconds: TimeInterval = 5
  /// Ваш IP напрямую (без VPN) — его видят российские сайты при раздельной настройке VPN.
  /// Яндекс не годится: отдавал 127.0.0.1 даже напрямую (проверено 2026-11-06).
  ///
  /// Службы напрямую и через VPN — разные: одна служба не должна одновременно видеть запрос
  /// с вашего адреса и с адреса VPN-сервера, иначе она может связать их. Общая — только последняя
  /// запасная (Amazon): её спрашивают, лишь когда основная молчит.
  public static let russia = [
    "https://icanhazip.com",
    "https://checkip.amazonaws.com",
  ]
  public static let abroad = [
    "https://api.ipify.org",
    "https://checkip.amazonaws.com",
  ]

  /// Узнавать ли IP напрямую через Wi-Fi/кабель, в обход VPN.
  public static func isDirect(_ region: Region) -> Bool {
    region == .russia
  }

  public static func services(for region: Region) -> [String] {
    switch region {
    case .russia: russia
    case .abroad: abroad
    }
  }

  /// Пора ли узнавать внешний IP: впервые, раз в минуту, сразу после смены VPN/локального IP
  /// (`lastAddressChange`) и ещё раз через `settleSeconds` после неё.
  public static func needsExternalRefresh(lastRefresh: Date?, lastAddressChange: Date?, now: Date)
    -> Bool
  {
    guard let lastRefresh else { return true }
    if let change = lastAddressChange {
      if lastRefresh < change { return true }
      let settled = change.addingTimeInterval(settleSeconds)
      if lastRefresh < settled && now >= settled { return true }
    }
    return now.timeIntervalSince(lastRefresh) >= refreshSeconds
  }
}
