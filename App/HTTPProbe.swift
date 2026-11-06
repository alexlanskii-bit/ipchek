import Foundation
import IPCheckCore

/// Проверка одного адреса: короткий HTTP-запрос, ответ сверяется строго (`ProbeExpectation`).
///
/// Соединение с каждым адресом держится открытым между проверками: задержка получается
/// честной (без поиска адреса и открытия соединения каждый раз), а трафик — меньше.
/// Адреса с простым HTTP разрешены точечно в App/Info.plist (App Transport Security).
enum HTTPProbe {
  /// Живые серверы отвечают за 0,05–0,45 с (замер 2026-11-06); дольше 2 с — считаем, что не ответил.
  static let timeoutSeconds: TimeInterval = 2

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeoutSeconds
    configuration.timeoutIntervalForResource = timeoutSeconds
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.httpAdditionalHeaders = ["User-Agent": "IPCHEK"]
    return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
  }()

  /// Задержка в миллисекундах или `nil`, если настоящего ответа не было.
  static func latency(of target: ProbeTarget) async -> Int? {
    guard let url = URL(string: target.url) else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = target.method
    let started = ContinuousClock.now
    do {
      let (body, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else { return nil }
      guard target.expectation.accepts(status: http.statusCode, body: body) else {
        Log.connectivity.debug(
          "\(target.name, privacy: .public): неожиданный ответ, код \(http.statusCode)")
        return nil
      }
      return Int(((ContinuousClock.now - started) / .milliseconds(1)).rounded())
    } catch {
      Log.connectivity.debug(
        "\(target.name, privacy: .public) не ответил: \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }
}

/// Переадресации не выполняем: страница входа в гостиничный Wi-Fi не должна сойти за ответ
/// сервера. По документации URLSession, `nil` отдаёт сам ответ-переадресацию (код 3xx).
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}
