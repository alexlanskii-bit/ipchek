import Foundation

/// Строгий разбор IP-адреса из ответа службы: всё, что не IP, отбрасывается.
public enum IPAddressText {
  /// Адрес без кавычек и пробелов, если текст — ровно один IPv4 или IPv6 адрес; иначе `nil`.
  public static func parse(_ text: String) -> String? {
    let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines.union(["\""]))
    guard !candidate.isEmpty, candidate.count <= 45 else { return nil }
    var v4 = in_addr()
    var v6 = in6_addr()
    // inet_pton — системная строгая проверка: «1.2.3», «256.1.1.1», «a::b::c» отвергаются.
    let isV4 = candidate.withCString { inet_pton(AF_INET, $0, &v4) } == 1
    let isV6 = candidate.withCString { inet_pton(AF_INET6, $0, &v6) } == 1
    return isV4 || isV6 ? candidate : nil
  }
}

extension IPAddressText {
  /// Публичный ли адрес — может ли он быть внешним IP. Служебные диапазоны (петля, домашние сети,
  /// адреса провайдера 100.64/10, 198.18/15, документационные, групповые и т. п.) — нет.
  /// Найдено 2026-11-06: служба Яндекса отдавала 127.0.0.1, и он показывался как внешний IP.
  public static func isPublic(_ address: String) -> Bool {
    var v4 = in_addr()
    if address.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 {
      return isPublicIPv4(UInt32(bigEndian: v4.s_addr))
    }
    var v6 = in6_addr()
    guard address.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 else { return false }
    let bytes = withUnsafeBytes(of: v6) { Array($0) }
    // ::ffff:a.b.c.d — IPv4 внутри IPv6: судим по IPv4-части.
    if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
      let embedded = bytes[12...].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
      return isPublicIPv4(embedded)
    }
    // Публичные IPv6 — только глобальные 2000::/3, кроме документационных 2001:db8::/32.
    let isGlobal = bytes[0] & 0xE0 == 0x20
    let isDocumentation = bytes[0..<4] == [0x20, 0x01, 0x0D, 0xB8]
    return isGlobal && !isDocumentation
  }

  /// Зарезервированные диапазоны IPv4 (RFC 6890 и др.): сеть и длина префикса.
  private static let reservedIPv4: [(network: UInt32, prefix: UInt32)] = [
    (ipv4(0, 0, 0, 0), 8),  // «этот» адрес
    (ipv4(10, 0, 0, 0), 8),  // частная сеть
    (ipv4(100, 64, 0, 0), 10),  // адреса провайдера (CGNAT)
    (ipv4(127, 0, 0, 0), 8),  // петля
    (ipv4(169, 254, 0, 0), 16),  // без сети (link-local)
    (ipv4(172, 16, 0, 0), 12),  // частная сеть
    (ipv4(192, 0, 0, 0), 24),  // служебные протоколов
    (ipv4(192, 0, 2, 0), 24),  // документация
    (ipv4(192, 168, 0, 0), 16),  // частная сеть
    (ipv4(198, 18, 0, 0), 15),  // тесты производительности; его же берут VPN-программы
    (ipv4(198, 51, 100, 0), 24),  // документация
    (ipv4(203, 0, 113, 0), 24),  // документация
    (ipv4(224, 0, 0, 0), 4),  // групповая рассылка
    (ipv4(240, 0, 0, 0), 4),  // зарезервировано, включая 255.255.255.255
  ]

  private static func isPublicIPv4(_ value: UInt32) -> Bool {
    !reservedIPv4.contains { range in
      let mask = range.prefix == 0 ? 0 : UInt32.max << (32 - range.prefix)
      return value & mask == range.network
    }
  }

  private static func ipv4(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) -> UInt32 {
    a << 24 | b << 16 | c << 8 | d
  }
}

/// Адрес на сетевом интерфейсе Mac (из системного списка интерфейсов).
public struct InterfaceAddress: Equatable, Sendable {
  public let interface: String
  public let address: String
  public let isIPv6: Bool

  public init(interface: String, address: String, isIPv6: Bool) {
    self.interface = interface
    self.address = address
    self.isIPv6 = isIPv6
  }
}

/// Что видно по интерфейсам: VPN и локальный IP.
public enum NetworkAddresses {
  /// Имя VPN-интерфейса, если VPN включён; иначе `nil`.
  /// Туннельные интерфейсы. У системных туннелей macOS (utun0–3 и др.) только локальный IPv6,
  /// а у включённого VPN — IPv4-адрес (у VPN владельца — из диапазона 198.18.0.0/15).
  static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]

  public static func vpnInterface(in addresses: [InterfaceAddress]) -> String? {
    addresses.first { item in
      tunnelPrefixes.contains { item.interface.hasPrefix($0) } && isUsableIPv4(item)
    }?.interface
  }

  /// Локальный IPv4 Mac в домашней сети: сначала на интерфейсе, который macOS считает
  /// основным (Wi-Fi или кабель), иначе — на первом `en*`.
  public static func localIPv4(in addresses: [InterfaceAddress], preferred: String?) -> String? {
    let usable = addresses.filter(isUsableIPv4)
    if let preferred, let match = usable.first(where: { $0.interface == preferred }) {
      return match.address
    }
    return usable.first { $0.interface.hasPrefix("en") }?.address
  }

  /// IPv4, не петля и не 169.254.x.x (адрес «без сети»).
  private static func isUsableIPv4(_ item: InterfaceAddress) -> Bool {
    !item.isIPv6 && !item.address.hasPrefix("127.") && !item.address.hasPrefix("169.254.")
  }
}
