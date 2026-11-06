import Foundation

/// Какой ответ сервера считается настоящим. Строго, чтобы страница входа в гостиничный Wi-Fi
/// или ответ VPN-программы не сошли за работающий интернет.
public enum ProbeExpectation: Equatable, Sendable {
  /// Ровно код 204 без содержимого (служебные адреса Google и Cloudflare).
  case noContent
  /// Код 200, в тексте — IP-адрес (служебный адрес Яндекса).
  case ipAddressText
  /// Ровно код 200.
  case ok

  public func accepts(status: Int, body: Data) -> Bool {
    switch self {
    case .noContent:
      return status == 204
    case .ok:
      return status == 200
    case .ipAddressText:
      guard status == 200, body.count <= 64, let text = String(data: body, encoding: .utf8) else {
        return false
      }
      return IPAddressText.parse(text) != nil
    }
  }
}

/// Проверочный адрес: короткий HTTP-запрос, время до ответа — задержка.
public struct ProbeTarget: Equatable, Sendable {
  public let name: String
  public let url: String
  public let method: String
  public let expectation: ProbeExpectation

  public init(name: String, url: String, method: String = "GET", expectation: ProbeExpectation) {
    self.name = name
    self.url = url
    self.method = method
    self.expectation = expectation
  }
}

/// Какие адреса и как часто проверять.
///
/// Почему HTTP, а не «открылось ли соединение»: VPN-программа владельца сама отвечает на открытие
/// любого соединения, даже к несуществующим адресам (проверено 2026-11-06). Подделать настоящий
/// ответ сервера она не может. Простой HTTP вместо HTTPS — чтобы проверка была лёгкой: данных мы
/// не передаём, только смотрим код ответа. Замеры из сети владельца (повторные запросы):
/// Google 50 мс, Cloudflare 65 мс, Яндекс 93 мс.
public enum ProbePlan {
  public static let russia: [ProbeTarget] = [
    ProbeTarget(
      name: "Яндекс", url: "http://ipv4-internet.yandex.net/api/v0/ip",
      expectation: .ipAddressText),
    ProbeTarget(name: "VK", url: "http://vk.com/robots.txt", method: "HEAD", expectation: .ok),
  ]
  public static let abroad: [ProbeTarget] = [
    ProbeTarget(
      name: "Google", url: "http://connectivitycheck.gstatic.com/generate_204",
      expectation: .noContent),
    ProbeTarget(
      name: "Cloudflare", url: "http://cp.cloudflare.com/generate_204", expectation: .noContent),
  ]

  /// Во сколько раз реже проверять в «дорогой» сети (например, раздача с телефона).
  public static let expensiveNetworkSlowdown = 6

  public static func targets(for region: Region) -> [ProbeTarget] {
    switch region {
    case .russia: russia
    case .abroad: abroad
    }
  }

  /// Проверяет регион: серверы по очереди, до первого ответа.
  /// `probe` возвращает задержку в миллисекундах или `nil`, если сервер не ответил.
  public static func check(
    _ targets: [ProbeTarget], probe: (ProbeTarget) async -> Int?
  ) async -> RegionResult {
    for target in targets {
      if let latency = await probe(target) {
        return .reachable(latencyMs: latency, via: target.name)
      }
    }
    return .unreachable
  }

  /// Пауза перед проверкой, которая подтверждает или снимает подозрение на разрыв, в секундах.
  public static let confirmationIntervalSeconds = 1

  /// Пауза между раундами проверок, в секундах.
  public static func intervalSeconds(
    settings: MonitorSettings, isExpensive: Bool, needsConfirmation: Bool = false
  ) -> Int {
    if needsConfirmation { return confirmationIntervalSeconds }
    return settings.checkIntervalSeconds * (isExpensive ? expensiveNetworkSlowdown : 1)
  }
}
