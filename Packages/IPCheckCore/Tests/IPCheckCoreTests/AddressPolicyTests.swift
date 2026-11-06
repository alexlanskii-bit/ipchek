import Foundation
import IPCheckCore
import Testing

@Suite("Уведомления о VPN и внешнем IP")
struct AddressPolicyTests {
  @Test("Первое наблюдение после запуска — без уведомлений")
  func firstObservationIsSilent() {
    var policy = AddressPolicy()

    let events = policy.observe(addr(vpn: "utun4", russia: home, abroad: vpnExit), at: at(0))

    #expect(events.isEmpty)
  }

  @Test("VPN отключился и не включился 10 секунд — «VPN отключён»")
  func vpnOffAfterTenSeconds() {
    var policy = AddressPolicy()
    _ = policy.observe(addr(vpn: "utun4"), at: at(0))

    let start = policy.observe(addr(vpn: nil), at: at(10))
    let nineSeconds = policy.observe(addr(vpn: nil), at: at(19))
    let tenSeconds = policy.observe(addr(vpn: nil), at: at(20))
    let later = policy.observe(addr(vpn: nil), at: at(25))

    #expect(start.isEmpty && nineSeconds.isEmpty)
    #expect(tenSeconds == [.vpnOff])
    #expect(later.isEmpty)
  }

  @Test("VPN включился — «VPN включён» с именем интерфейса")
  func vpnOn() {
    var policy = AddressPolicy()
    _ = policy.observe(addr(vpn: nil), at: at(0))
    _ = policy.observe(addr(vpn: "utun4"), at: at(10))

    let events = policy.observe(addr(vpn: "utun4"), at: at(20))

    #expect(events == [.vpnOn(interface: "utun4")])
  }

  @Test("VPN мигнул на 5 секунд при переподключении — без уведомлений")
  func vpnBlinkIsSilent() {
    var policy = AddressPolicy()
    _ = policy.observe(addr(vpn: "utun4"), at: at(0))

    let events = [
      policy.observe(addr(vpn: nil), at: at(10)),
      policy.observe(addr(vpn: "utun4"), at: at(15)),
      policy.observe(addr(vpn: "utun4"), at: at(30)),
    ]
    // Позже VPN выключился по-настоящему: 10 секунд считаются заново, а не от мигания.
    let realOff = policy.observe(addr(vpn: nil), at: at(40))
    let confirmed = policy.observe(addr(vpn: nil), at: at(50))

    #expect(events.allSatisfy { $0.isEmpty })
    #expect(realOff.isEmpty)
    #expect(confirmed == [.vpnOff])
  }

  @Test("Внешний IP сменился без участия VPN — «было → стало»")
  func ipChanged() {
    var policy = AddressPolicy()
    _ = policy.observe(addr(abroad: vpnExit), at: at(0))

    let events = policy.observe(addr(abroad: otherExit), at: at(300))

    #expect(events == [.externalIPChanged(.abroad, from: vpnExit, to: otherExit)])
  }

  @Test("Смена IP из-за включения или выключения VPN — отдельно не сообщаем")
  func ipChangeExplainedByVPN() {
    var policy = AddressPolicy()
    _ = policy.observe(addr(vpn: "utun4", abroad: vpnExit), at: at(0))
    _ = policy.observe(addr(vpn: nil, abroad: vpnExit), at: at(10))
    let vpnEvent = policy.observe(addr(vpn: nil, abroad: vpnExit), at: at(20))

    let ipEvent = policy.observe(addr(vpn: nil, abroad: home), at: at(40))

    #expect(vpnEvent == [.vpnOff])
    #expect(ipEvent.isEmpty)
  }

  @Test("Через 2 минуты после изменения VPN смена IP снова объявляется")
  func vpnExplanationExpires() {
    var policy = AddressPolicy()
    _ = policy.observe(addr(vpn: "utun4", abroad: vpnExit), at: at(0))
    _ = policy.observe(addr(vpn: nil, abroad: vpnExit), at: at(10))
    _ = policy.observe(addr(vpn: nil, abroad: home), at: at(20))

    let events = policy.observe(addr(vpn: nil, abroad: otherExit), at: at(130))

    #expect(events == [.externalIPChanged(.abroad, from: home, to: otherExit)])
  }

  @Test("IP не удалось узнать — это не смена; потом тот же — тишина, другой — смена")
  func unknownIPIsNotAChange() {
    var policy = AddressPolicy()
    _ = policy.observe(addr(russia: home), at: at(0))

    let unknown = policy.observe(addr(russia: nil), at: at(60))
    let same = policy.observe(addr(russia: home), at: at(120))
    _ = policy.observe(addr(russia: nil), at: at(180))
    let different = policy.observe(addr(russia: otherHome), at: at(240))

    #expect(unknown.isEmpty && same.isEmpty)
    #expect(different == [.externalIPChanged(.russia, from: home, to: otherHome)])
  }

  @Test("О смене IP одного региона — не чаще раза в 10 минут, «было» — последний известный")
  func ipChangeCooldown() {
    var policy = AddressPolicy()
    _ = policy.observe(addr(abroad: vpnExit), at: at(0))

    let first = policy.observe(addr(abroad: otherExit), at: at(300))
    let tooSoon = policy.observe(addr(abroad: vpnExit), at: at(400))
    let later = policy.observe(addr(abroad: otherExit), at: at(900))

    #expect(first == [.externalIPChanged(.abroad, from: vpnExit, to: otherExit)])
    #expect(tooSoon.isEmpty)
    #expect(later == [.externalIPChanged(.abroad, from: vpnExit, to: otherExit)])  // ровно 600 с
  }

  @Test("Регионы независимы: сменились оба — два уведомления, сначала Россия")
  func regionsAreIndependent() {
    var policy = AddressPolicy()
    _ = policy.observe(addr(russia: home, abroad: vpnExit), at: at(0))

    let events = policy.observe(addr(russia: otherHome, abroad: otherExit), at: at(300))

    #expect(
      events == [
        .externalIPChanged(.russia, from: home, to: otherHome),
        .externalIPChanged(.abroad, from: vpnExit, to: otherExit),
      ])
  }
}

// MARK: - Помощники (адреса из документационных диапазонов RFC 5737)

private let home = "203.0.113.10"
private let otherHome = "203.0.113.20"
private let vpnExit = "198.51.100.7"
private let otherExit = "198.51.100.9"
private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ second: Double) -> Date { start.addingTimeInterval(second) }

private func addr(vpn: String? = nil, russia: String? = nil, abroad: String? = nil)
  -> AddressSnapshot
{
  AddressSnapshot(localIP: "192.168.1.23", vpnInterface: vpn, russiaIP: russia, abroadIP: abroad)
}

@Suite("Когда узнавать внешний IP")
struct AddressPlanTests {
  @Test("Впервые, раз в минуту и сразу после смены VPN или локального IP")
  func refreshSchedule() {
    #expect(AddressPlan.needsExternalRefresh(lastRefresh: nil, now: at(0), addressesChanged: false))
    #expect(
      !AddressPlan.needsExternalRefresh(lastRefresh: at(0), now: at(59), addressesChanged: false))
    #expect(
      AddressPlan.needsExternalRefresh(lastRefresh: at(0), now: at(60), addressesChanged: false))
    #expect(
      AddressPlan.needsExternalRefresh(lastRefresh: at(0), now: at(5), addressesChanged: true))
  }

  @Test("У каждого региона не меньше двух служб, все по HTTPS")
  func servicesAreHTTPS() {
    for region in Region.allCases {
      let services = AddressPlan.services(for: region)
      #expect(services.count >= 2, "регион \(region)")
      #expect(services.allSatisfy { URL(string: $0)?.scheme == "https" })
    }
    #expect(AddressPlan.services(for: .russia) == AddressPlan.russia)
    #expect(AddressPlan.services(for: .abroad) == AddressPlan.abroad)
  }
}
