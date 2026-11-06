import Foundation
import IPCheckCore
import Testing

@Suite("Страна по IP")
struct CountryTests {
  @Test(
    "Ответ службы — код страны", arguments: [("NL\n", "NL"), ("ru", "RU"), (" DE ", "DE")])
  func validCodes(text: String, expected: String) {
    #expect(CountryCode.parse(text) == expected)
  }

  @Test(
    "Не код страны — отбрасывается",
    arguments: [
      "", "N", "NLD", "Undefined", "<html>", "1A", "N1", "{\"error\":true}", "Нл", "N L",
    ])
  func invalidCodes(text: String) {
    #expect(CountryCode.parse(text) == nil)
  }

  @Test("Флаг из кода страны")
  func flags() {
    #expect(CountryCode.flag("NL") == "🇳🇱")
    #expect(CountryCode.flag("RU") == "🇷🇺")
    #expect(CountryCode.flag("N") == "")
    #expect(CountryCode.flag("1A") == "")
  }

  @Test("Сверка двух служб")
  func combine() {
    #expect(CountryVerdict.combine("NL", "NL") == .agreed("NL"))
    #expect(CountryVerdict.combine("NL", nil) == .single("NL"))
    #expect(CountryVerdict.combine(nil, "DE") == .single("DE"))
    #expect(CountryVerdict.combine("NL", "DE") == .disputed(first: "NL", second: "DE"))
    #expect(CountryVerdict.combine(nil, nil) == .unknown)
  }

  @Test("Верить можно, когда службы согласны или ответила одна; при расхождении — нет")
  func effective() {
    #expect(CountryVerdict.agreed("NL").effective == "NL")
    #expect(CountryVerdict.single("NL").effective == "NL")
    #expect(CountryVerdict.disputed(first: "NL", second: "DE").effective == nil)
    #expect(CountryVerdict.unknown.effective == nil)
  }

  @Test("В ссылку службы попадает только проверенный IP")
  func serviceURL() {
    #expect(
      CountryPlan.first.url(for: "203.0.113.5")?.absoluteString
        == "https://ipinfo.io/203.0.113.5/country")
    #expect(
      CountryPlan.second.url(for: "203.0.113.5")?.absoluteString
        == "https://ipapi.co/203.0.113.5/country/")
    #expect(CountryPlan.first.url(for: "2001:db8::1") != nil)
    #expect(CountryPlan.first.url(for: "203.0.113.5/../json") == nil)
    #expect(CountryPlan.first.url(for: "example.com") == nil)
  }

  @Test("Когда спрашивать страну снова")
  func needsLookup() {
    let ip = "203.0.113.5"
    let known = CountryCacheEntry(ip: ip, verdict: .agreed("NL"), at: at(0))
    let unknown = CountryCacheEntry(ip: ip, verdict: .unknown, at: at(0))

    #expect(CountryPlan.needsLookup(cached: nil, ip: ip, now: at(0)))
    #expect(CountryPlan.needsLookup(cached: known, ip: "203.0.113.6", now: at(10)))
    #expect(!CountryPlan.needsLookup(cached: known, ip: ip, now: at(3600)))
    #expect(CountryPlan.needsLookup(cached: known, ip: ip, now: at(86_400)))
    #expect(!CountryPlan.needsLookup(cached: unknown, ip: ip, now: at(299)))
    #expect(CountryPlan.needsLookup(cached: unknown, ip: ip, now: at(300)))
  }

  @Test("Страна показывается только для того IP, о котором спрашивали")
  func verdictForCurrentIP() {
    let known = CountryCacheEntry(ip: "203.0.113.5", verdict: .agreed("NL"), at: at(0))

    #expect(CountryPlan.verdict(cached: known, ip: "203.0.113.5") == .agreed("NL"))
    #expect(CountryPlan.verdict(cached: known, ip: "203.0.113.6") == .unknown)
    #expect(CountryPlan.verdict(cached: known, ip: nil) == .unknown)
    #expect(CountryPlan.verdict(cached: nil, ip: "203.0.113.5") == .unknown)
  }

  @Test("Сначала страна зарубежного IP, страна вашего — не раньше чем через минуту")
  func lookupsAreSpreadOut() {
    let ips: [Region: String] = [.russia: home, .abroad: vpnExit]
    var cache: [Region: CountryCacheEntry] = [:]

    #expect(CountryPlan.nextLookup(ips: ips, cache: cache, now: at(0)) == .abroad)
    cache[.abroad] = CountryCacheEntry(ip: vpnExit, verdict: .agreed("NL"), at: at(1))
    #expect(CountryPlan.nextLookup(ips: ips, cache: cache, now: at(60)) == nil)
    #expect(CountryPlan.nextLookup(ips: ips, cache: cache, now: at(61)) == .russia)
    cache[.russia] = CountryCacheEntry(ip: home, verdict: .agreed("RU"), at: at(62))
    #expect(CountryPlan.nextLookup(ips: ips, cache: cache, now: at(200)) == nil)
  }

  @Test("Свой прошлый запрос не задерживает: сменился зарубежный IP — спрашиваем сразу")
  func sameRegionIsNotDelayed() {
    let cache: [Region: CountryCacheEntry] = [
      .russia: CountryCacheEntry(ip: home, verdict: .agreed("RU"), at: at(0)),
      .abroad: CountryCacheEntry(ip: home, verdict: .agreed("RU"), at: at(100)),
    ]

    let next = CountryPlan.nextLookup(
      ips: [.russia: home, .abroad: vpnExit], cache: cache, now: at(110))

    #expect(next == .abroad)
  }

  @Test("Без IP страну не спрашиваем; ждёт один регион — другой не задерживается")
  func lookupSkipsBlockedAndMissing() {
    #expect(CountryPlan.nextLookup(ips: [:], cache: [:], now: at(0)) == nil)
    // Ваш IP спрашивали 10 секунд назад, а теперь сменились оба: зарубежный подождёт,
    // а ваш спросим снова сразу.
    let cache: [Region: CountryCacheEntry] = [
      .russia: CountryCacheEntry(ip: home, verdict: .agreed("RU"), at: at(0))
    ]
    let next = CountryPlan.nextLookup(
      ips: [.russia: "203.0.113.99", .abroad: vpnExit], cache: cache, now: at(10))

    #expect(next == .russia)
  }
}

private let home = "203.0.113.10"
private let vpnExit = "198.51.100.7"

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ second: Double) -> Date { start.addingTimeInterval(second) }
