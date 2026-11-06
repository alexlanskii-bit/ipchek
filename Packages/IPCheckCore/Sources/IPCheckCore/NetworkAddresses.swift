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
