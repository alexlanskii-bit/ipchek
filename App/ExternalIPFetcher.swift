import Foundation
import IPCheckCore

/// Узнаёт внешний IP у служб из `AddressPlan` (только HTTPS). Ответ сверяется строгим разбором:
/// что угодно, кроме IP-адреса, считается «не удалось узнать».
enum ExternalIPFetcher {
  static let timeoutSeconds: TimeInterval = 5
  /// Ответ служб — 7–40 байт; больше — точно не IP.
  static let maxBodyBytes = 64

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

  /// Внешний IP региона или `nil`, если ни одна служба не ответила адресом.
  static func fetch(_ region: Region) async -> String? {
    for service in AddressPlan.services(for: region) {
      if let address = await fetch(from: service) { return address }
    }
    return nil
  }

  private static func fetch(from service: String) async -> String? {
    guard let url = URL(string: service) else { return nil }
    do {
      let (body, response) = try await session.data(from: url)
      guard (response as? HTTPURLResponse)?.statusCode == 200, body.count <= maxBodyBytes,
        let text = String(data: body, encoding: .utf8)
      else {
        Log.address.debug("\(service, privacy: .public): ответ не похож на IP")
        return nil
      }
      return IPAddressText.parse(text)
    } catch {
      Log.address.debug(
        "\(service, privacy: .public) не ответил: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }
}
