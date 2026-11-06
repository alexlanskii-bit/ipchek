import Foundation
import IPCheckCore

/// Узнаёт страну IP у двух независимых служб одновременно и сверяет ответы
/// (решение владельца — «полный контроль на случай подмены»). Только HTTPS; ответ — строго
/// две латинские буквы, иначе «служба не ответила».
enum CountryFetcher {
  static let timeoutSeconds: TimeInterval = 5
  /// Ответ служб — код страны с переводом строки, 2–3 байта; больше — точно не код.
  static let maxBodyBytes = 16

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
    return URLSession(configuration: configuration)
  }()

  static func lookup(_ ip: String) async -> CountryVerdict {
    async let first = fetch(from: CountryPlan.first, ip: ip)
    async let second = fetch(from: CountryPlan.second, ip: ip)
    return CountryVerdict.combine(await first, await second)
  }

  private static func fetch(from service: CountryService, ip: String) async -> String? {
    guard let url = service.url(for: ip) else { return nil }
    do {
      let (body, response) = try await session.data(from: url)
      guard (response as? HTTPURLResponse)?.statusCode == 200, body.count <= maxBodyBytes,
        let text = String(data: body, encoding: .utf8), let code = CountryCode.parse(text)
      else {
        Log.address.debug("\(service.name, privacy: .public): ответ не похож на код страны")
        return nil
      }
      return code
    } catch {
      Log.address.debug(
        "\(service.name, privacy: .public) не ответил: \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }
}
