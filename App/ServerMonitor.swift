import Foundation
import IPCheckCore
import Network
import Observation

/// Проверяет VPN-сервер раз в 15 секунд (решение владельца), при подозрении на сбой — через 1 с.
/// Решения о состоянии — `ServerEvaluator`, об уведомлениях — `ServerPolicy` (покрыты тестами).
@MainActor
@Observable
final class ServerMonitor {
  private(set) var snapshot = ServerSnapshot()
  /// Адрес сервера вписан в настройках.
  private(set) var isConfigured: Bool

  @ObservationIgnored var onSnapshot: ((ServerSnapshot) -> Void)?
  /// Вызывается, когда сменился сервер или способ проверки: история начинается заново.
  @ObservationIgnored var onReset: (() -> Void)?
  /// Физический интерфейс (Wi-Fi или кабель) для проверки в обход VPN.
  @ObservationIgnored var directInterface: () -> NWInterface? = { nil }
  /// Работает ли домашний интернет. Без него молчание сервера ничего не значит.
  @ObservationIgnored var internetWorking = false {
    // Интернет появился — проверяем сразу, а не через 15 секунд.
    didSet { if internetWorking && !oldValue { checkNow = true } }
  }
  /// Способ, который сработал в прошлый раз, — его пробуем первым.
  @ObservationIgnored private var lastWorkingStep: ServerProbeStep?
  @ObservationIgnored private var settings: MonitorSettings
  @ObservationIgnored private var evaluator: ServerEvaluator
  @ObservationIgnored private var checkNow = false
  @ObservationIgnored private var task: Task<Void, Never>?

  init(settings: MonitorSettings) {
    self.settings = settings
    evaluator = ServerEvaluator(failuresBeforeDown: settings.failuresBeforeOutage)
    isConfigured = !settings.serverHost.isEmpty
  }

  func start() {
    guard task == nil else { return }
    task = Task { await self.run() }
  }

  /// Mac проснулся: неудачи до сна забыты, проверка — как только появится интернет.
  func systemDidWake(at time: Date) {
    snapshot = evaluator.systemDidWake(at: time)
    onSnapshot?(snapshot)
    checkNow = true
  }

  func apply(settings newSettings: MonitorSettings) {
    let changed =
      newSettings.serverHost != settings.serverHost
      || newSettings.serverCheck != settings.serverCheck
      || newSettings.serverPort != settings.serverPort
      || newSettings.failuresBeforeOutage != settings.failuresBeforeOutage
    settings = newSettings
    isConfigured = !newSettings.serverHost.isEmpty
    guard changed else { return }
    evaluator = ServerEvaluator(failuresBeforeDown: newSettings.failuresBeforeOutage)
    snapshot = evaluator.snapshot
    lastWorkingStep = nil
    onReset?()
    checkNow = true
    Log.server.notice("Настройки сервера изменены — проверка начинается заново")
  }

  private func run() async {
    while !Task.isCancelled {
      checkNow = false
      if isConfigured { await check() }
      let pause = ServerProbePlan.pauseSeconds(needsConfirmation: evaluator.needsConfirmation)
      for _ in 0..<pause where !checkNow {
        do {
          try await Task.sleep(for: .seconds(1))
        } catch {
          return  // задачу отменили — цикл заканчивается
        }
      }
    }
  }

  private func check() async {
    let host = settings.serverHost
    let steps = ServerProbePlan.ordered(
      ServerProbePlan.steps(method: settings.serverCheck, port: settings.serverPort),
      preferring: lastWorkingStep)
    let interface = directInterface()
    let canCheck = internetWorking && interface != nil
    // Время начала: проверку, начатую до сна, оценка после пробуждения не учитывает.
    let startedAt = Date.now
    var result = ServerProbeResult.unreachable
    if canCheck, let interface {
      result = await Self.probe(host: host, steps: steps, via: interface)
    }
    // Пока шла проверка, адрес могли поменять — тогда этот результат уже не про тот сервер.
    guard host == settings.serverHost else { return }
    if case .reachable(_, let step) = result { lastWorkingStep = step }
    let next = evaluator.record(result, internetWorking: canCheck, at: startedAt)
    if next.status != snapshot.status {
      // Без адреса сервера: в журнал его не пишем.
      Log.server.notice("Сервер: \(String(describing: next.status), privacy: .public)")
    }
    snapshot = next
    onSnapshot?(next)
  }

  nonisolated private static func probe(
    host: String, steps: [ServerProbeStep], via interface: NWInterface
  ) async -> ServerProbeResult {
    await ServerProbePlan.check(steps) { step in
      await ServerProbe.latency(of: step, host: host, via: interface)
    }
  }
}
