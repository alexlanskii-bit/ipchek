import Foundation

/// Код страны ISO 3166-1 (две латинские буквы) из ответа службы.
public enum CountryCode {
  /// Код заглавными буквами, если ответ — ровно две латинские буквы; иначе `nil`.
  public static func parse(_ text: String) -> String? {
    let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard candidate.count == 2, candidate.allSatisfy({ $0.isASCII && $0.isLetter }) else {
      return nil
    }
    return candidate.uppercased()
  }

  /// Флаг страны из кода («NL» → 🇳🇱); для неверного кода — пустая строка.
  public static func flag(_ code: String) -> String {
    guard parse(code) == code else { return "" }
    // Флаг — две «региональные буквы» Unicode: A → 🇦 (U+1F1E6) и далее по алфавиту.
    let base: UInt32 = 0x1F1E6 - 0x41
    let scalars = code.unicodeScalars.compactMap { Unicode.Scalar(base + $0.value) }
    return String(String.UnicodeScalarView(scalars))
  }
}

/// Что сказали две службы о стране одного IP.
public enum CountryVerdict: Equatable, Sendable {
  case unknown
  /// Ответила только одна служба.
  case single(String)
  case agreed(String)
  /// Службы назвали разные страны — возможна подмена или ошибка базы.
  case disputed(first: String, second: String)

  public static func combine(_ first: String?, _ second: String?) -> CountryVerdict {
    switch (first, second) {
    case (nil, nil): .unknown
    case (let code?, nil), (nil, let code?): .single(code)
    case (let one?, let other?): one == other ? .agreed(one) : .disputed(first: one, second: other)
    }
  }

  /// Страна, которой можно верить: обе согласны или ответила одна; иначе `nil`.
  public var effective: String? {
    switch self {
    case .agreed(let code), .single(let code): code
    case .disputed, .unknown: nil
    }
  }
}

/// Служба, определяющая страну по IP.
public struct CountryService: Equatable, Sendable {
  public let name: String
  /// Адрес с местом для IP: `{ip}`.
  public let template: String

  public init(name: String, template: String) {
    self.name = name
    self.template = template
  }

  /// Ссылка для IP. В ссылку попадает только строго проверенный IP-адрес.
  public func url(for ip: String) -> URL? {
    guard IPAddressText.parse(ip) == ip else { return nil }
    return URL(string: template.replacingOccurrences(of: "{ip}", with: ip))
  }
}

/// Что запомнили о стране IP: для какого адреса, что ответили службы и когда.
public struct CountryCacheEntry: Equatable, Sendable {
  public let ip: String
  public let verdict: CountryVerdict
  public let at: Date

  public init(ip: String, verdict: CountryVerdict, at: Date) {
    self.ip = ip
    self.verdict = verdict
    self.at = at
  }
}

/// Откуда и когда узнавать страну (решение владельца — две службы со сверкой).
public enum CountryPlan {
  public static let first = CountryService(
    name: "ipinfo", template: "https://ipinfo.io/{ip}/country")
  public static let second = CountryService(
    name: "ipapi", template: "https://ipapi.co/{ip}/country/")
  /// Для того же IP — раз в сутки.
  public static let refreshSeconds: TimeInterval = 86_400
  /// Если в прошлый раз обе службы промолчали — повтор через 5 минут.
  public static let retryUnknownSeconds: TimeInterval = 300

  /// Страну вашего IP и IP VPN-сервера спрашиваем не ближе минуты друг к другу: службы стран
  /// общие, и два запроса с разных адресов в одну секунду легко связать.
  public static let staggerSeconds: TimeInterval = 60
  /// Сначала — страна зарубежного IP: её называет уведомление о VPN.
  public static let lookupOrder: [Region] = [.abroad, .russia]

  public static func needsLookup(cached: CountryCacheEntry?, ip: String, now: Date) -> Bool {
    guard let cached, cached.ip == ip else { return true }
    let age = now.timeIntervalSince(cached.at)
    if cached.verdict == .unknown { return age >= retryUnknownSeconds }
    return age >= refreshSeconds
  }

  /// Что известно о стране `ip`: ответ служб, только если спрашивали именно об этом адресе.
  public static func verdict(cached: CountryCacheEntry?, ip: String?) -> CountryVerdict {
    guard let ip, let cached, cached.ip == ip else { return .unknown }
    return cached.verdict
  }

  /// О стране какого региона спросить сейчас — не больше одного за раз. Регион ждёт, если другой
  /// спрашивали меньше `staggerSeconds` назад; свой прошлый запрос не задерживает.
  public static func nextLookup(
    ips: [Region: String], cache: [Region: CountryCacheEntry], now: Date
  ) -> Region? {
    lookupOrder.first { region in
      guard let ip = ips[region], needsLookup(cached: cache[region], ip: ip, now: now) else {
        return false
      }
      return !cache.contains { other, entry in
        other != region && now.timeIntervalSince(entry.at) < staggerSeconds
      }
    }
  }
}
