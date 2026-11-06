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
}

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ second: Double) -> Date { start.addingTimeInterval(second) }
