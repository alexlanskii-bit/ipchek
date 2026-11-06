import Foundation
import IPCheckCore
import Network
import Observation

/// Цикл слежения за связью: Wi-Fi/кабель от macOS + проверки серверов по расписанию.
/// Решения о состоянии принимает `ConnectivityEvaluator` (логика покрыта тестами).
@MainActor
@Observable
final class ConnectivityMonitor {
  private(set) var snapshot = ConnectivitySnapshot()

  @ObservationIgnored private var evaluator: ConnectivityEvaluator
  @ObservationIgnored private let settings: MonitorSettings
  @ObservationIgnored private var isExpensive = false
  @ObservationIgnored private var roundRequested = false
  @ObservationIgnored private var tasks: [Task<Void, Never>] = []

  init(settings: MonitorSettings) {
    self.settings = settings
    evaluator = ConnectivityEvaluator(settings: settings)
  }

  func start() {
    guard tasks.isEmpty else { return }
    tasks = [
      Task { await self.watchLink() },
      Task { await self.runChecks() },
    ]
  }

  /// Сообщения macOS о Wi-Fi и кабеле приходят сразу; после каждого — внеочередная проверка.
  private func watchLink() async {
    for await path in NWPathMonitor() {
      isExpensive = path.isExpensive
      let link = LinkStatus(path)
      if link != snapshot.link {
        Log.connectivity.notice(
          "Подключение: \(String(describing: link), privacy: .public), дорогая сеть: \(path.isExpensive)"
        )
      }
      update(evaluator.linkChanged(to: link, at: .now))
      roundRequested = true
    }
  }

  private func runChecks() async {
    while !Task.isCancelled {
      roundRequested = false
      // Без Wi-Fi и кабеля проверять серверы бессмысленно.
      if snapshot.link != LinkStatus.none {
        let round = await Self.performRound()
        Log.connectivity.debug(
          "Проверка: Россия \(String(describing: round.russia), privacy: .public), зарубеж \(String(describing: round.abroad), privacy: .public)"
        )
        update(evaluator.record(round))
      }
      let seconds = ProbePlan.intervalSeconds(
        settings: settings, isExpensive: isExpensive,
        needsConfirmation: evaluator.needsConfirmation)
      for _ in 0..<seconds where !roundRequested {
        do {
          try await Task.sleep(for: .seconds(1))
        } catch {
          return  // задачу отменили — цикл заканчивается
        }
      }
    }
  }

  /// Российский и зарубежный регионы проверяются одновременно.
  nonisolated private static func performRound() async -> CheckRound {
    let startedAt = Date.now
    async let russia = ProbePlan.check(ProbePlan.russia, probe: HTTPProbe.latency(of:))
    async let abroad = ProbePlan.check(ProbePlan.abroad, probe: HTTPProbe.latency(of:))
    return CheckRound(at: startedAt, russia: await russia, abroad: await abroad)
  }

  private func update(_ new: ConnectivitySnapshot) {
    if new.state != snapshot.state {
      Log.connectivity.notice("Состояние связи: \(String(describing: new.state), privacy: .public)")
    }
    snapshot = new
  }
}

extension LinkStatus {
  /// «Нет подключения» — только когда macOS считает путь недоступным.
  init(_ path: NWPath) {
    if path.status == .unsatisfied {
      self = .none
    } else if path.usesInterfaceType(.wifi) {
      self = .wifi
    } else if path.usesInterfaceType(.wiredEthernet) {
      self = .wired
    } else {
      self = .other
    }
  }
}
