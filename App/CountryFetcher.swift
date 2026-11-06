import Foundation
import IPCheckCore
import Network

/// Узнаёт страну IP у двух независимых служб одновременно и сверяет ответы
/// (решение владельца — «полный контроль на случай подмены»). Только HTTPS; ответ — строго
/// две латинские буквы, иначе «служба не ответила».
///
/// О вашем IP спрашиваем тем же путём, каким его узнали, — напрямую: так служба видит запрос
/// с того же адреса, о котором её спрашивают, и не узнаёт ничего сверх этого.
enum CountryFetcher {
  /// Ответ служб — код страны с переводом строки, 2–3 байта; больше — точно не код.
  static let maxBodyBytes = 16

  static func lookup(_ ip: String, region: Region, direct: NWInterface?) async -> CountryVerdict {
    let route = AddressPlan.isDirect(region) ? direct : nil
    if AddressPlan.isDirect(region) && route == nil { return .unknown }  // нет Wi-Fi/кабеля
    async let first = fetch(from: CountryPlan.first, ip: ip, route: route)
    async let second = fetch(from: CountryPlan.second, ip: ip, route: route)
    return CountryVerdict.combine(await first, await second)
  }

  private static func fetch(from service: CountryService, ip: String, route: NWInterface?) async
    -> String?
  {
    guard let url = service.url(for: ip) else { return nil }
    // В журнал — только имя службы: в ссылке есть IP.
    guard
      let response = await ServiceClient.get(
        url, direct: route, limit: maxBodyBytes, name: service.name),
      response.status == 200, let text = String(data: response.body, encoding: .utf8),
      let code = CountryCode.parse(text)
    else {
      Log.address.debug("\(service.name, privacy: .public): ответ не похож на код страны")
      return nil
    }
    return code
  }
}
