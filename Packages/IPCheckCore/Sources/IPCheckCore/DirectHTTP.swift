import Foundation

/// Короткий HTTP-запрос в обход VPN: системная библиотека URLSession не умеет привязываться к Wi-Fi,
/// поэтому запрос идёт через Network.framework (TLS делает macOS), а здесь — сборка запроса и разбор
/// ответа. Запрос — HTTP/1.0: сервер отвечает одним куском, без «chunked».
public enum DirectHTTP {
  /// Ответ длиннее — точно не короткий ответ службы.
  public static let maxResponseBytes = 8192

  /// Текст запроса GET для адреса `https://host/path`; `nil` для неподходящего адреса.
  public static func request(for url: String) -> Data? {
    guard let components = URLComponents(string: url), components.scheme == "https",
      let host = components.host, !host.isEmpty, components.port == nil,
      components.query == nil, components.user == nil,
      host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
    else { return nil }
    // Путь — в закодированном виде: «%0D%0A» не должен превратиться в новую строку запроса.
    let encoded = components.percentEncodedPath
    let path = encoded.isEmpty ? "/" : encoded
    let text =
      "GET \(path) HTTP/1.0\r\nHost: \(host)\r\nUser-Agent: \(ClientIdentity.userAgent)\r\n"
      + "Accept: */*\r\nConnection: close\r\n\r\n"
    return Data(text.utf8)
  }

  /// Код ответа и содержимое; `nil`, если ответ неполный или не похож на HTTP.
  public static func parse(_ response: Data) -> (status: Int, body: Data)? {
    guard response.count <= maxResponseBytes,
      let separator = response.range(of: Data("\r\n\r\n".utf8)),
      let head = String(data: response[..<separator.lowerBound], encoding: .utf8)
    else { return nil }

    var lines = head.components(separatedBy: "\r\n")
    let statusParts = lines.removeFirst().split(separator: " ", maxSplits: 2)
    guard statusParts.count >= 2, statusParts[0].hasPrefix("HTTP/1."),
      let status = Int(statusParts[1]), (100...599).contains(status)
    else { return nil }

    var contentLength: Int?
    for line in lines {
      let pair = line.split(separator: ":", maxSplits: 1)
      guard pair.count == 2 else { continue }
      let name = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
      let value = pair[1].trimmingCharacters(in: .whitespaces)
      // Просили HTTP/1.0 — «кусочный» ответ значит, что сервер ответил не так, как ждали.
      if name == "transfer-encoding", value.lowercased() != "identity" { return nil }
      if name == "content-length" {
        guard let length = Int(value), length >= 0 else { return nil }
        contentLength = length
      }
    }

    var body = Data(response[separator.upperBound...])
    if let contentLength {
      guard body.count >= contentLength else { return nil }  // ответ пришёл не целиком
      body = Data(body.prefix(contentLength))
    }
    return (status, body)
  }
}
