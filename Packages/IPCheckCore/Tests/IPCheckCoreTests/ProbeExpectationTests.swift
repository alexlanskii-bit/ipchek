import Foundation
import IPCheckCore
import Testing

@Suite("Настоящий ли ответ сервера")
struct ProbeExpectationTests {
  @Test(
    "Google и Cloudflare: засчитывается только код 204",
    arguments: [(204, true), (200, false), (302, false), (500, false)])
  func noContent(status: Int, accepted: Bool) {
    #expect(ProbeExpectation.noContent.accepts(status: status, body: Data()) == accepted)
  }

  @Test("Страница входа в Wi-Fi с кодом 200 не засчитывается как ответ Google")
  func captivePortalIsRejected() {
    let page = Data("<html><body>Войдите в сеть отеля</body></html>".utf8)

    #expect(!ProbeExpectation.noContent.accepts(status: 200, body: page))
    #expect(!ProbeExpectation.ipAddressText.accepts(status: 200, body: page))
  }

  @Test(
    "Яндекс: код 200 и IP-адрес в тексте",
    arguments: [
      (200, "\"95.24.1.2\"", true),
      (200, "95.24.1.2\n", true),
      (200, "\"2a02:6b8::1\"", true),
      (200, "", false),
      (200, "<html>", false),
      (200, "ok", false),
      (200, "12345", false),
      (200, "cafe", false),
      (502, "\"95.24.1.2\"", false),
    ])
  func ipAddressText(status: Int, body: String, accepted: Bool) {
    #expect(
      ProbeExpectation.ipAddressText.accepts(status: status, body: Data(body.utf8)) == accepted)
  }

  @Test("VK: засчитывается только код 200", arguments: [(200, true), (301, false), (204, false)])
  func ok(status: Int, accepted: Bool) {
    #expect(ProbeExpectation.ok.accepts(status: status, body: Data()) == accepted)
  }
}
