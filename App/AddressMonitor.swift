import Foundation
import IPCheckCore
import Network
import Observation

/// Раз в 5 секунд читает интерфейсы (локальный IP, VPN); внешний IP узнаёт раз в минуту
/// и сразу при смене VPN/локального IP или после возвращения интернета (`AddressPlan`).
@MainActor
@Observable
final class AddressMonitor {
  static let tickSeconds = 5

  private(set) var snapshot = AddressSnapshot()
  /// Регионы, для которых последняя попытка узнать внешний IP не удалась.
  private(set) var failedRegions: Set<Region> = []

  /// Вызывается на каждом шаге — правилам уведомлений нужны регулярные наблюдения.
  @ObservationIgnored var onSnapshot: ((AddressSnapshot) -> Void)?
  /// Имя основного интерфейса (Wi-Fi или кабель) — от слежения за связью.
  @ObservationIgnored var preferredInterface: () -> String? = { nil }
  /// Wi-Fi или кабель целиком — чтобы узнать ваш IP напрямую, в обход VPN.
  @ObservationIgnored var directInterface: () -> NWInterface? = { nil }
  /// Есть ли сейчас интернет: без него внешний IP не узнать, и старый показывать нельзя.
  @ObservationIgnored var internetAvailable = false {
    didSet { if internetAvailable && !oldValue { refreshRequested = true } }
  }
  @ObservationIgnored private var lastExternalRefresh: Date?
  /// Когда в последний раз сменились VPN или локальный IP: после этого внешний IP узнаём
  /// сразу и ещё раз, когда маршруты переключились (`AddressPlan.settleSeconds`).
  @ObservationIgnored private var lastAddressChange: Date?
  /// Что службы сказали о стране каждого внешнего IP: тот же IP — раз в сутки (`CountryPlan`).
  @ObservationIgnored private var countryCache: [Region: CountryCacheEntry] = [:]
  @ObservationIgnored private var refreshRequested = false
  @ObservationIgnored private var task: Task<Void, Never>?

  func start() {
    guard task == nil else { return }
    task = Task { await self.run() }
  }

  private func run() async {
    while !Task.isCancelled {
      await tick()
      do {
        try await Task.sleep(for: .seconds(Self.tickSeconds))
      } catch {
        return  // задачу отменили — цикл заканчивается
      }
    }
  }

  private func tick() async {
    let now = Date.now
    let interfaces = InterfaceReader.addresses()
    var next = snapshot
    next.localIP = NetworkAddresses.localIPv4(in: interfaces, preferred: preferredInterface())
    next.vpnInterface = NetworkAddresses.vpnInterface(in: interfaces)
    let addressesChanged =
      next.localIP != snapshot.localIP || next.vpnInterface != snapshot.vpnInterface
    if next.vpnInterface != snapshot.vpnInterface {
      Log.address.notice(
        "VPN: \(next.vpnInterface ?? "выключен", privacy: .public)")
    }
    if addressesChanged { lastAddressChange = now }
    let direct = directInterface()

    if !internetAvailable {
      next.russiaIP = nil
      next.abroadIP = nil
      next.russiaCountry = .unknown
      next.abroadCountry = .unknown
    } else if refreshRequested
      || AddressPlan.needsExternalRefresh(
        lastRefresh: lastExternalRefresh, lastAddressChange: lastAddressChange, now: now)
    {
      refreshRequested = false
      lastExternalRefresh = now
      async let russia = ExternalIPFetcher.fetch(.russia, direct: direct)
      async let abroad = ExternalIPFetcher.fetch(.abroad, direct: direct)
      next.russiaIP = await russia
      next.abroadIP = await abroad
      failedRegions = Set(Region.allCases.filter { next.externalIP($0) == nil })
      // Без самих адресов: в журнал IP не пишем.
      Log.address.info(
        "Внешний IP: Россия — \(next.russiaIP == nil ? "не узнали" : "узнали", privacy: .public), зарубеж — \(next.abroadIP == nil ? "не узнали" : "узнали", privacy: .public)"
      )
    }

    if internetAvailable {
      await lookUpCountry(ips: next, direct: direct)
      next.russiaCountry = CountryPlan.verdict(cached: countryCache[.russia], ip: next.russiaIP)
      next.abroadCountry = CountryPlan.verdict(cached: countryCache[.abroad], ip: next.abroadIP)
    }

    if next != snapshot { snapshot = next }
    onSnapshot?(next)
  }

  /// Спрашивает страну одного IP, если пора (`CountryPlan.nextLookup`): IP новый, прошли сутки
  /// или в прошлый раз службы молчали. Разные адреса — не ближе минуты друг к другу.
  private func lookUpCountry(ips snapshot: AddressSnapshot, direct: NWInterface?) async {
    var ips: [Region: String] = [:]
    for region in Region.allCases { ips[region] = snapshot.externalIP(region) }
    guard let region = CountryPlan.nextLookup(ips: ips, cache: countryCache, now: .now),
      let ip = ips[region]
    else { return }
    let verdict = await CountryFetcher.lookup(ip, region: region, direct: direct)
    countryCache[region] = CountryCacheEntry(ip: ip, verdict: verdict, at: .now)
    // Код страны — не адрес: его в журнал писать можно.
    Log.address.info(
      "Страна (\(region.rawValue, privacy: .public)): \(String(describing: verdict), privacy: .public)"
    )
  }
}
