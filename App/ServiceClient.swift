import Foundation
import IPCheckCore
import Network

/// Короткие GET-запросы к службам IP и стран — обычным путём (URLSession: через VPN, если он
/// включён) или напрямую через Wi-Fi/кабель в обход VPN (`DirectFetcher`).
///
/// Подпись запросов — обычная (`ClientIdentity`), переадресации не выполняются, ответ длиннее
/// `limit` дальше не читается и отбрасывается.
enum ServiceClient {
  static let timeoutSeconds: TimeInterval = 5

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeoutSeconds
    configuration.timeoutIntervalForResource = timeoutSeconds
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.httpAdditionalHeaders = ["User-Agent": ClientIdentity.userAgent]
    return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
  }()

  /// Код ответа и содержимое или `nil`, если ответа не было или он длиннее `limit`.
  /// `direct` — Wi-Fi или кабель: запрос пойдёт через него, в обход VPN.
  static func get(_ url: URL, direct: NWInterface?, limit: Int, name: String) async
    -> (status: Int, body: Data)?
  {
    if let direct {
      guard let response = await DirectFetcher.get(url.absoluteString, via: direct),
        response.body.count <= limit
      else {
        Log.address.debug("\(name, privacy: .public) напрямую: ответа нет или он слишком длинный")
        return nil
      }
      return response
    }
    do {
      let (bytes, response) = try await session.bytes(from: url)
      // Длинный ответ дочитывать незачем: обрываем запрос.
      defer { bytes.task.cancel() }
      guard let http = response as? HTTPURLResponse else { return nil }
      guard let body = try await BoundedBody.read(bytes, limit: limit) else {
        Log.address.debug("\(name, privacy: .public): ответ слишком длинный")
        return nil
      }
      return (http.statusCode, body)
    } catch {
      Log.address.debug(
        "\(name, privacy: .public) не ответил: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }
}
