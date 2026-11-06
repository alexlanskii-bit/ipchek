import Foundation
import IPCheckCore
import Testing

@Suite("Запрос в обход VPN: сборка и разбор")
struct DirectHTTPTests {
  @Test("Запрос GET с именем сервера и путём")
  func request() {
    let ipify = DirectHTTP.request(for: "https://api.ipify.org").map {
      String(decoding: $0, as: UTF8.self)
    }
    let amazon = DirectHTTP.request(for: "https://checkip.amazonaws.com/").map {
      String(decoding: $0, as: UTF8.self)
    }

    #expect(
      ipify
        == "GET / HTTP/1.0\r\nHost: api.ipify.org\r\nUser-Agent: Mozilla/5.0\r\nAccept: */*\r\nConnection: close\r\n\r\n"
    )
    #expect(amazon?.hasPrefix("GET / HTTP/1.0\r\nHost: checkip.amazonaws.com\r\n") == true)
  }

  @Test("Закодированный перевод строки в пути не становится новой строкой запроса")
  func encodedNewlineStaysEncoded() {
    let text = DirectHTTP.request(for: "https://ipinfo.io/a%0D%0AX-Evil:%201/country").map {
      String(decoding: $0, as: UTF8.self)
    }

    #expect(
      text?.hasPrefix("GET /a%0D%0AX-Evil:%201/country HTTP/1.0\r\nHost: ipinfo.io\r\n") == true)
    #expect(text?.contains("\r\nX-Evil") == false)
    // Перевод строки прямо в адресе — тоже не новая строка запроса.
    let raw = DirectHTTP.request(for: "https://ipinfo.io/a\r\nX-Evil: 1").map {
      String(decoding: $0, as: UTF8.self)
    }
    #expect(raw?.contains("\r\nX-Evil") != true)
  }

  @Test(
    "Только HTTPS и только имя сервера без лишнего",
    arguments: ["http://api.ipify.org", "ftp://x.org", "не адрес", "https://"])
  func requestRejects(url: String) {
    #expect(DirectHTTP.request(for: url) == nil)
  }

  @Test("Обычный ответ: код и содержимое")
  func parseOK() {
    let response = Data(
      "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 12\r\n\r\n203.0.113.5\n".utf8)

    let parsed = DirectHTTP.parse(response)

    #expect(parsed?.status == 200)
    #expect(parsed.map { String(decoding: $0.body, as: UTF8.self) } == "203.0.113.5\n")
  }

  @Test("Ответ без содержимого")
  func parseEmptyBody() {
    let parsed = DirectHTTP.parse(Data("HTTP/1.0 404 Not Found\r\n\r\n".utf8))

    #expect(parsed?.status == 404)
    #expect(parsed?.body.isEmpty == true)
  }

  @Test("Лишнее после указанной длины отрезается")
  func parseTrimsToContentLength() {
    let parsed = DirectHTTP.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nNLmore".utf8))

    #expect(parsed.map { String(decoding: $0.body, as: UTF8.self) } == "NL")
  }

  @Test(
    "Неполный или странный ответ — отбрасывается",
    arguments: [
      "HTTP/1.1 200 OK\r\nContent-Length: 20\r\n\r\nкоротко",
      "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nc\r\n203.0.113.5\n\r\n0\r\n\r\n",
      "HTTP/1.1 200 OK\r\nбез конца заголовков",
      "SSH-2.0-OpenSSH\r\n\r\n",
      "ICY 200 OK\r\n\r\nданные",
      "HTTP/1.1 abc OK\r\n\r\n",
      "",
    ])
  func parseRejects(text: String) {
    #expect(DirectHTTP.parse(Data(text.utf8)) == nil)
  }
}
