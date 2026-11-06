import Foundation
import IPCheckCore
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
  /// Есть ли сейчас интернет: без него внешний IP не узнать, и старый показывать нельзя.
  @ObservationIgnored var internetAvailable = false {
    didSet { if internetAvailable && !oldValue { refreshRequested = true } }
  }
  @ObservationIgnored private var lastExternalRefresh: Date?
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

    if !internetAvailable {
      next.russiaIP = nil
      next.abroadIP = nil
    } else if refreshRequested
      || AddressPlan.needsExternalRefresh(
        lastRefresh: lastExternalRefresh, now: .now, addressesChanged: addressesChanged)
    {
      refreshRequested = false
      lastExternalRefresh = .now
      async let russia = ExternalIPFetcher.fetch(.russia)
      async let abroad = ExternalIPFetcher.fetch(.abroad)
      next.russiaIP = await russia
      next.abroadIP = await abroad
      failedRegions = Set(Region.allCases.filter { next.externalIP($0) == nil })
      // Без самих адресов: в журнал IP не пишем.
      Log.address.info(
        "Внешний IP: Россия — \(next.russiaIP == nil ? "не узнали" : "узнали", privacy: .public), зарубеж — \(next.abroadIP == nil ? "не узнали" : "узнали", privacy: .public)"
      )
    }

    if next != snapshot { snapshot = next }
    onSnapshot?(next)
  }
}
