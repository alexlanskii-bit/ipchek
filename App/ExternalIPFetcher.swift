import Foundation
import IPCheckCore
import Network

/// Узнаёт внешний IP у служб из `AddressPlan` (только HTTPS). Ответ сверяется строгим разбором:
/// что угодно, кроме публичного IP-адреса, считается «не удалось узнать».
enum ExternalIPFetcher {
  /// Ответ служб — 7–40 байт; больше — точно не IP.
  static let maxBodyBytes = 64

  /// Внешний IP региона или `nil`, если ни одна служба не ответила публичным адресом.
  /// Ваш IP (`AddressPlan.isDirect`) узнаётся напрямую через `direct` — Wi-Fi или кабель.
  static func fetch(_ region: Region, direct: NWInterface?) async -> String? {
    let route = AddressPlan.isDirect(region) ? direct : nil
    if AddressPlan.isDirect(region) && route == nil { return nil }  // нет Wi-Fi/кабеля
    for service in AddressPlan.services(for: region) {
      guard let url = URL(string: service) else { continue }
      let response = await ServiceClient.get(url, direct: route, limit: maxBodyBytes, name: service)
      if let address = address(in: response, from: service) { return address }
    }
    return nil
  }

  /// Адрес из ответа — только если это ровно один IP и он публичный.
  private static func address(in response: (status: Int, body: Data)?, from service: String)
    -> String?
  {
    guard let response, response.status == 200,
      let text = String(data: response.body, encoding: .utf8),
      let address = IPAddressText.parse(text)
    else {
      Log.address.debug("\(service, privacy: .public): ответ не похож на IP")
      return nil
    }
    // Служебный адрес (127.x, 192.168.x, 100.64.x…) — не внешний IP (найдено 2026-11-06).
    guard IPAddressText.isPublic(address) else {
      Log.address.notice("\(service, privacy: .public): вернула служебный адрес — пропускаю")
      return nil
    }
    return address
  }
}
