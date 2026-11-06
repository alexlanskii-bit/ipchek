import IPCheckCore
import Testing

@Suite("IP-адреса и VPN")
struct NetworkAddressesTests {
  @Test(
    "Ответ службы — IP-адрес",
    arguments: [
      ("95.24.1.2", "95.24.1.2"), ("\"95.24.1.2\"", "95.24.1.2"), ("95.24.1.2\n", "95.24.1.2"),
      ("2a02:6b8::1", "2a02:6b8::1"), ("\"2a02:6b8::1\"\n", "2a02:6b8::1"),
    ])
  func validAddresses(text: String, expected: String) {
    #expect(IPAddressText.parse(text) == expected)
  }

  @Test(
    "Не IP-адрес — отбрасывается",
    arguments: [
      "", "256.1.1.1", "1.2.3", "1.2.3.4.5", "a.b.c.d", "<html>Войдите</html>", "2a02::6b8::1",
      "95.24.1.2 extra", "12345", "cafe",
    ])
  func invalidAddresses(text: String) {
    #expect(IPAddressText.parse(text) == nil)
  }

  @Test("Системные туннели macOS с локальным IPv6 — не VPN")
  func systemTunnelsAreNotVPN() {
    let addresses = [
      v6("utun0", "fe80::1"), v6("utun1", "fe80::2"), v4("en0", "192.168.1.23"),
      v4("lo0", "127.0.0.1"),
    ]

    #expect(NetworkAddresses.vpnInterface(in: addresses) == nil)
  }

  @Test(
    "Туннель с IPv4-адресом — VPN включён",
    arguments: [("utun4", "198.18.0.1"), ("ppp0", "10.8.0.2"), ("ipsec0", "10.0.0.5")])
  func tunnelWithIPv4IsVPN(interface: String, address: String) {
    let addresses = [v6("utun0", "fe80::1"), v4("en0", "192.168.1.23"), v4(interface, address)]

    #expect(NetworkAddresses.vpnInterface(in: addresses) == interface)
  }

  @Test("Туннель с адресом 169.254.x.x (без настоящей сети) — не VPN")
  func linkLocalTunnelIsNotVPN() {
    #expect(NetworkAddresses.vpnInterface(in: [v4("utun3", "169.254.10.1")]) == nil)
  }

  @Test("Локальный IP — IPv4 на основном интерфейсе")
  func localOnPreferredInterface() {
    // en0 стоит раньше: запасное правило «первый en*» выбрало бы его, но основной — en1.
    let addresses = [
      v4("bridge100", "192.168.64.1"), v4("en0", "192.168.1.23"), v6("en0", "2a02::23"),
      v6("en1", "fe80::5"), v4("en1", "10.0.0.7"),
    ]

    #expect(NetworkAddresses.localIPv4(in: addresses, preferred: "en1") == "10.0.0.7")
  }

  @Test("Основной интерфейс неизвестен — первый en* с IPv4, без петли и 169.254")
  func localFallback() {
    let addresses = [
      v4("lo0", "127.0.0.1"), v4("bridge100", "192.168.64.1"), v4("en0", "169.254.3.3"),
      v4("en1", "192.168.1.23"),
    ]

    #expect(NetworkAddresses.localIPv4(in: addresses, preferred: nil) == "192.168.1.23")
  }

  @Test("Нет подходящего адреса — локального IP нет")
  func noLocalAddress() {
    #expect(
      NetworkAddresses.localIPv4(
        in: [v6("en0", "fe80::1"), v4("lo0", "127.0.0.1")], preferred: "en0")
        == nil)
  }
}

private func v4(_ interface: String, _ address: String) -> InterfaceAddress {
  InterfaceAddress(interface: interface, address: address, isIPv6: false)
}

private func v6(_ interface: String, _ address: String) -> InterfaceAddress {
  InterfaceAddress(interface: interface, address: address, isIPv6: true)
}

@Suite("Публичный ли адрес — может ли он быть внешним IP")
struct PublicAddressTests {
  @Test(
    "Публичные адреса",
    arguments: [
      "8.8.8.8", "1.1.1.1", "77.88.8.8", "100.63.255.255", "100.128.0.0", "172.15.255.255",
      "172.32.0.0", "198.17.255.255", "198.20.0.0", "2a02:6b8::1", "2001:4860:4860::8888",
    ])
  func publicAddresses(address: String) {
    #expect(IPAddressText.isPublic(address))
  }

  @Test(
    "Служебные адреса — не внешний IP",
    arguments: [
      "127.0.0.1", "127.255.255.254", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1",
      "100.64.0.1", "100.127.255.255", "169.254.1.1", "198.18.0.1", "198.19.255.255", "0.0.0.0",
      "224.0.0.1", "255.255.255.255", "240.0.0.1", "192.0.2.1", "198.51.100.7", "203.0.113.5",
      "::1", "::", "fe80::1", "fd00::1", "fc00::1", "ff02::1", "2001:db8::1", "::ffff:127.0.0.1",
      "не адрес",
    ])
  func reservedAddresses(address: String) {
    #expect(!IPAddressText.isPublic(address))
  }
}
