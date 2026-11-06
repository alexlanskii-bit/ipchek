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

  public init(
    localIP: String? = nil, vpnInterface: String? = nil, russiaIP: String? = nil,
    abroadIP: String? = nil
  ) {
    self.localIP = localIP
    self.vpnInterface = vpnInterface
    self.russiaIP = russiaIP
    self.abroadIP = abroadIP
  }

  public func externalIP(_ region: Region) -> String? {
    switch region {
    case .russia: russiaIP
    case .abroad: abroadIP
    }
  }
}

/// Событие об адресах, о котором стоит сообщить.
public enum AddressEvent: Equatable, Sendable {
  case vpnOn(interface: String)
  case vpnOff
  case externalIPChanged(Region, from: String, to: String)
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
  private var lastKnownIP: [Region: String] = [:]
  private var lastIPNotice: [Region: Date] = [:]

  public init() {}

  public mutating func observe(_ snapshot: AddressSnapshot, at time: Date) -> [AddressEvent] {
    var events: [AddressEvent] = []
    if let event = observeVPN(interface: snapshot.vpnInterface, at: time) {
      events.append(event)
    }
    for region in Region.allCases {
      if let event = observeIP(snapshot.externalIP(region), region: region, at: time) {
        events.append(event)
      }
    }
    return events
  }

  private mutating func observeVPN(interface: String?, at time: Date) -> AddressEvent? {
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
    if let interface { return .vpnOn(interface: interface) }
    return .vpnOff
  }

  private mutating func observeIP(_ ip: String?, region: Region, at time: Date) -> AddressEvent? {
    guard let ip else { return nil }  // не удалось узнать — это не смена
    guard let old = lastKnownIP[region] else {
      lastKnownIP[region] = ip
      return nil
    }
    guard old != ip else { return nil }
    lastKnownIP[region] = ip
    if let change = lastVPNChange,
      time.timeIntervalSince(change) < Self.vpnExplainsIPChangeSeconds
    {
      return nil
    }
    if let last = lastIPNotice[region], time.timeIntervalSince(last) < Self.repeatCooldown {
      return nil
    }
    lastIPNotice[region] = time
    return .externalIPChanged(region, from: old, to: ip)
  }
}

/// Откуда и как часто узнавать внешний IP.
///
/// Только HTTPS: по простому HTTP служба Яндекса через VPN владельца отвечала «127.0.0.1»
/// (проверено 2026-11-06). Ответ сверяется строгим разбором `IPAddressText`.
public enum AddressPlan {
  public static let refreshSeconds: TimeInterval = 60
  public static let russia = [
    "https://ipv4-internet.yandex.net/api/v0/ip",
    "https://yandex.ru/internet/api/v0/ip",
  ]
  public static let abroad = [
    "https://api.ipify.org",
    "https://icanhazip.com",
    "https://checkip.amazonaws.com",
  ]

  public static func services(for region: Region) -> [String] {
    switch region {
    case .russia: russia
    case .abroad: abroad
    }
  }

  /// Пора ли узнавать внешний IP: впервые, раз в минуту или сразу после смены VPN/локального IP.
  public static func needsExternalRefresh(lastRefresh: Date?, now: Date, addressesChanged: Bool)
    -> Bool
  {
    guard let lastRefresh else { return true }
    return addressesChanged || now.timeIntervalSince(lastRefresh) >= refreshSeconds
  }
}
