import Foundation

/// Регион проверочных серверов.
public enum Region: String, CaseIterable, Sendable {
  case russia
  case abroad
}

/// Как Mac подключён к сети — по данным macOS.
public enum LinkStatus: Equatable, Sendable {
  /// Нет ни Wi-Fi, ни кабеля.
  case none
  case wifi
  case wired
  case other
}

/// Итог проверки одного региона в одном раунде.
public enum RegionResult: Equatable, Sendable {
  /// Сервер ответил; `via` — какой именно (для панели).
  case reachable(latencyMs: Int, via: String)
  /// Не ответил ни один сервер региона.
  case unreachable

  public var isReachable: Bool {
    if case .reachable = self { true } else { false }
  }
}

/// Один раунд проверок: по одному результату на регион.
public struct CheckRound: Equatable, Sendable {
  public let at: Date
  public let russia: RegionResult
  public let abroad: RegionResult

  public init(at: Date, russia: RegionResult, abroad: RegionResult) {
    self.at = at
    self.russia = russia
    self.abroad = abroad
  }
}

public enum OfflineReason: Equatable, Sendable {
  /// Wi-Fi и кабель отключены.
  case noLink
  /// Подключение есть, но серверы не отвечают.
  case serversNotResponding
}

public enum UnstableReason: Equatable, Sendable {
  case highLatency(ms: Int, threshold: Int)
  case packetLoss(percent: Int, threshold: Int)
}

/// Состояние связи, которое видит человек.
public enum ConnectionState: Equatable, Sendable {
  case checking
  case online
  case unstable(UnstableReason)
  /// Один регион отвечает, другой — нет.
  case partial(reachable: Region)
  case offline(OfflineReason)
}

/// Всё, что показывает панель о связи.
public struct ConnectivitySnapshot: Equatable, Sendable {
  public var state: ConnectionState = .checking
  public var link: LinkStatus?
  /// Средняя задержка за последнюю минуту.
  public var latencyMs: Int?
  /// Потери за последнюю минуту, в процентах.
  public var lossPercent: Int?
  public var russia: RegionResult?
  public var abroad: RegionResult?
  /// Когда началось текущее состояние.
  public var stateSince: Date?
  public var updatedAt: Date?

  public init() {}
}

/// Превращает поток проверок в состояние связи.
///
/// Правила (паспорт, раздел 9):
/// - нет Wi-Fi и кабеля — сразу «нет интернета»;
/// - не ответил ни один регион `failuresBeforeOutage` раз подряд — «нет интернета»;
/// - после разрыва нужно `recoveryRounds` удачных раундов подряд, до этого — «проверяю»;
/// - один регион не отвечает `failuresBeforeOutage` раз подряд — «частично»;
/// - за последнюю минуту потери или средняя задержка выше порогов — «нестабильно»
///   (судим, только когда проверок набралось не меньше `minimumChecksForQuality`);
///   для «нестабильно по потерям» нужно ещё и не меньше `minimumLostChecksForInstability`
///   потерянных проверок: одна-единственная неудача — это медленный запрос, а не плохая связь
///   (иначе при запуске 1 неудача из 6 = 17 % давала ложную тревогу — найдено 2026-11-06).
///
/// Потери — это случайные сбои. Неудачи, из которых сложился разрыв или «частично», в потери
/// не идут: о них уже сказано. Свежие неудачи подряд, которые ещё могут оказаться разрывом,
/// пока не учитываются; если связь восстановилась раньше порога — засчитываются как потери.
public struct ConnectivityEvaluator: Sendable {
  public static let window: TimeInterval = 60
  public static let recoveryRounds = 2
  public static let minimumChecksForQuality = 6
  public static let minimumLostChecksForInstability = 2

  public private(set) var snapshot = ConnectivitySnapshot()

  private var settings: MonitorSettings
  private var samples: [Sample] = []
  private var countedChecks = 0
  private var countedLostChecks = 0
  private var failedRoundsInRow = 0
  private var goodRoundsInRow = 0
  private var regionFailuresInRow: [Region: Int] = [:]
  private var recovering = false
  /// Проверки, начатые раньше этого момента (до пробуждения Mac), не учитываются.
  private var ignoreRoundsBefore: Date?

  private struct Sample: Sendable {
    let at: Date
    let region: Region
    /// `nil` — сервер не ответил.
    let latencyMs: Int?
    /// Неудача — часть разрыва или «частично», а не случайный сбой.
    var partOfOutage = false
  }

  public init(settings: MonitorSettings) {
    self.settings = settings
  }

  /// Новые настройки применяются сразу; накопленная статистика сохраняется.
  @discardableResult
  public mutating func update(settings newSettings: MonitorSettings) -> ConnectivitySnapshot {
    settings = newSettings
    updateQualityNumbers()
    switch snapshot.state.kind {
    case .online, .unstable, .partial:
      setState(qualityState(), at: snapshot.updatedAt ?? .now)
    case .checking, .offline:
      break  // разрыв и проверка решаются следующими раундами
    }
    return snapshot
  }

  /// Были неудачи, но разрыв или «частично» ещё не решены — следующую проверку стоит сделать
  /// раньше обычного, чтобы быстрее подтвердить или снять подозрение.
  public var needsConfirmation: Bool {
    guard snapshot.link != LinkStatus.none else { return false }
    let threshold = settings.failuresBeforeOutage
    let undecidedRound = failedRoundsInRow > 0 && failedRoundsInRow < threshold
    let undecidedRegion = regionFailuresInRow.values.contains { $0 > 0 && $0 < threshold }
    return undecidedRound || undecidedRegion
  }

  @discardableResult
  public mutating func linkChanged(to link: LinkStatus, at time: Date) -> ConnectivitySnapshot {
    let previous = snapshot.link
    snapshot.link = link
    if link == .none {
      markStreaksAsOutage(Region.allCases)
      resetCounters()
      recovering = true
      setState(.offline(.noLink), at: time)
    } else if previous == LinkStatus.none {
      resetCounters()
      recovering = true
      setState(.checking, at: time)
    }
    updateQualityNumbers()
    return snapshot
  }

  @discardableResult
  public mutating func record(_ round: CheckRound) -> ConnectivitySnapshot {
    // Начата до пробуждения: ответа не дождалась из-за сна, а не из-за сети.
    if let ignoreRoundsBefore, round.at < ignoreRoundsBefore { return snapshot }
    snapshot.russia = round.russia
    snapshot.abroad = round.abroad
    snapshot.updatedAt = round.at
    // Без Wi-Fi и кабеля проверки заведомо не проходят — в статистику их не берём.
    guard snapshot.link != LinkStatus.none else { return snapshot }

    for (region, result) in [(Region.russia, round.russia), (.abroad, round.abroad)] {
      var latency: Int?
      if case .reachable(let value, _) = result { latency = value }
      samples.append(Sample(at: round.at, region: region, latencyMs: latency))
      regionFailuresInRow[region] = result.isReachable ? 0 : (regionFailuresInRow[region] ?? 0) + 1
    }
    samples.removeAll { round.at.timeIntervalSince($0.at) > Self.window }

    let anyReachable = round.russia.isReachable || round.abroad.isReachable
    failedRoundsInRow = anyReachable ? 0 : failedRoundsInRow + 1
    goodRoundsInRow = anyReachable ? goodRoundsInRow + 1 : 0
    markStreaksAsOutage(
      Region.allCases.filter { (regionFailuresInRow[$0] ?? 0) >= settings.failuresBeforeOutage })
    updateQualityNumbers()

    if failedRoundsInRow >= settings.failuresBeforeOutage {
      recovering = true
      setState(.offline(.serversNotResponding), at: round.at)
      return snapshot
    }
    guard anyReachable else { return snapshot }
    if recovering {
      guard goodRoundsInRow >= Self.recoveryRounds else {
        setState(.checking, at: round.at)
        return snapshot
      }
      recovering = false
    }
    setState(qualityState(), at: round.at)
    return snapshot
  }

  /// Mac проснулся: всё, что было до сна, — устарело. Начинаем как при запуске, но Wi-Fi/кабель
  /// помним: о них macOS сообщает сама. Неудачи, накопленные во сне, и статистика за минуту до сна
  /// не превращаются в «разрыв» или «нестабильно».
  @discardableResult
  public mutating func systemDidWake(at time: Date) -> ConnectivitySnapshot {
    samples = []
    resetCounters()
    recovering = false
    ignoreRoundsBefore = time
    updateQualityNumbers()  // без проверок — ни задержки, ни потерь
    snapshot.russia = nil
    snapshot.abroad = nil
    snapshot.updatedAt = time
    snapshot.state = snapshot.link == LinkStatus.none ? .offline(.noLink) : .checking
    snapshot.stateSince = time  // минуты сна в длительность не идут
    return snapshot
  }

  // MARK: - Внутреннее

  private mutating func resetCounters() {
    failedRoundsInRow = 0
    goodRoundsInRow = 0
    regionFailuresInRow = [:]
  }

  /// Помечает текущие неудачи подряд у регионов как часть разрыва.
  private mutating func markStreaksAsOutage(_ regions: [Region]) {
    for region in regions {
      for index in samples.indices.reversed() where samples[index].region == region {
        guard samples[index].latencyMs == nil else { break }
        samples[index].partOfOutage = true
      }
    }
  }

  private mutating func updateQualityNumbers() {
    let latencies = samples.compactMap(\.latencyMs)
    var counted = 0
    var failed = 0
    for region in Region.allCases {
      let streak = regionFailuresInRow[region] ?? 0
      var undecided = streak < settings.failuresBeforeOutage ? streak : 0
      for sample in samples.reversed() where sample.region == region {
        if sample.latencyMs == nil && undecided > 0 {
          undecided -= 1
          continue
        }
        guard !sample.partOfOutage else { continue }
        counted += 1
        if sample.latencyMs == nil { failed += 1 }
      }
    }
    countedChecks = counted
    countedLostChecks = failed
    snapshot.latencyMs =
      latencies.isEmpty
      ? nil : Int((Double(latencies.reduce(0, +)) / Double(latencies.count)).rounded())
    snapshot.lossPercent =
      counted == 0 ? nil : Int((Double(failed) * 100 / Double(counted)).rounded())
  }

  private func qualityState() -> ConnectionState {
    for region in Region.allCases {
      let other: Region = region == .russia ? .abroad : .russia
      if (regionFailuresInRow[other] ?? 0) >= settings.failuresBeforeOutage {
        return .partial(reachable: region)
      }
    }
    guard countedChecks >= Self.minimumChecksForQuality else { return .online }
    if let loss = snapshot.lossPercent, loss > settings.unstableLossPercent,
      countedLostChecks >= Self.minimumLostChecksForInstability
    {
      return .unstable(.packetLoss(percent: loss, threshold: settings.unstableLossPercent))
    }
    if let latency = snapshot.latencyMs, latency > settings.unstableLatencyMs {
      return .unstable(.highLatency(ms: latency, threshold: settings.unstableLatencyMs))
    }
    return .online
  }

  /// Время начала меняется, только когда меняется вид состояния: продолжающийся разрыв
  /// или смена причины нестабильности его не сдвигают.
  private mutating func setState(_ state: ConnectionState, at time: Date) {
    if state.kind != snapshot.state.kind || snapshot.stateSince == nil {
      snapshot.stateSince = time
    }
    snapshot.state = state
  }
}

extension ConnectionState {
  /// Вид состояния без подробностей.
  public enum Kind: Sendable {
    case checking, online, unstable, partial, offline
  }

  public var kind: Kind {
    switch self {
    case .checking: .checking
    case .online: .online
    case .unstable: .unstable
    case .partial: .partial
    case .offline: .offline
    }
  }
}
