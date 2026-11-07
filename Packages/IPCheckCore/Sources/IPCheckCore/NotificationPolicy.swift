import Foundation

/// Событие, о котором стоит сообщить человеку уведомлением.
public enum ConnectivityEvent: Equatable, Sendable {
  /// Интернет пропал.
  case outage(OfflineReason, link: LinkStatus?)
  /// Интернет вернулся; сколько его не было.
  case restored(downtimeSeconds: Int)
  case unstable(UnstableReason)
  /// Часть сайтов недоступна: отвечает только `reachable`.
  case partial(reachable: Region)
  /// Недоступная часть сайтов снова открывается; сколько не открывалась.
  case partialResolved(unreachable: Region, downtimeSeconds: Int)
}

/// Решает, о каких изменениях состояния сообщать.
public struct NotificationPolicy: Sendable {
  /// Нестабильность и «часть сайтов недоступна» — не чаще раза в 10 минут.
  public static let repeatCooldown: TimeInterval = 600
  /// О пропаже Wi-Fi или кабеля — если не вернулись за 5 секунд (решение владельца 2026-11-07):
  /// смена сети и короткие провалы проходят без тревоги. Значок краснеет сразу.
  public static let linkLossConfirmSeconds: TimeInterval = 5

  /// Видели ли работающий интернет с момента запуска. До этого молчим: при входе в систему
  /// Wi-Fi часто подключается позже приложения, и «пропал» был бы ложной тревогой.
  private var hasSeenWorking = false
  private var lastKind: ConnectionState.Kind?
  private var outageStartedAt: Date?
  /// Wi-Fi и кабель пропали в этот момент, но ещё не прошло `linkLossConfirmSeconds`.
  private var pendingLinkLoss: Date?
  private var partial: (startedAt: Date, unreachable: Region, notified: Bool)?
  private var lastUnstableNotice: Date?
  private var lastPartialNotice: Date?

  public init() {}

  /// Когда показать текущее состояние ещё раз, даже если оно не изменится: без Wi-Fi проверки
  /// не идут, и иначе подтверждение пропажи не наступило бы.
  public var recheckAt: Date? {
    pendingLinkLoss?.addingTimeInterval(Self.linkLossConfirmSeconds)
  }

  /// Mac проспал `seconds`: минуты сна не считаются разрывом, поэтому начало открытых историй
  /// сдвигается вперёд на время сна.
  public mutating func excludeSleep(seconds: TimeInterval) {
    guard seconds > 0 else { return }
    outageStartedAt = outageStartedAt?.addingTimeInterval(seconds)
    pendingLinkLoss = pendingLinkLoss?.addingTimeInterval(seconds)
    if let episode = partial {
      partial = (
        episode.startedAt.addingTimeInterval(seconds), episode.unreachable, episode.notified
      )
    }
  }

  /// Вызывается на каждое обновление состояния; возвращает события для уведомлений.
  public mutating func observe(
    _ snapshot: ConnectivitySnapshot, at time: Date, notifyUnstable: Bool
  ) -> [ConnectivityEvent] {
    let kind = snapshot.state.kind
    defer { lastKind = kind }
    if snapshot.state != .offline(.noLink) { pendingLinkLoss = nil }
    var events: [ConnectivityEvent] = []
    // Конец истории — когда состояние сменилось, а не когда мы это увидели (например, после паузы).
    let changedAt = snapshot.stateSince ?? time

    switch snapshot.state {
    case .checking:
      break

    case .offline(let reason):
      // Одна история разрыва: «проверяю» между неудачами её не прерывает.
      guard hasSeenWorking, outageStartedAt == nil else { break }
      var startedAt = changedAt
      if reason == .noLink {
        let lostAt = pendingLinkLoss ?? changedAt
        guard time.timeIntervalSince(lostAt) >= Self.linkLossConfirmSeconds else {
          pendingLinkLoss = lostAt
          break
        }
        startedAt = lostAt
      }
      pendingLinkLoss = nil
      outageStartedAt = startedAt
      partial = nil
      events.append(.outage(reason, link: snapshot.link))

    case .online, .unstable, .partial:
      guard hasSeenWorking else {
        hasSeenWorking = true
        break
      }
      if let started = outageStartedAt {
        events.append(.restored(downtimeSeconds: seconds(from: started, to: changedAt)))
        outageStartedAt = nil
      }
      if case .partial(let reachable) = snapshot.state {
        if partial == nil {
          let notify = isCooledDown(lastPartialNotice, at: time)
          partial = (snapshot.stateSince ?? time, reachable.other, notify)
          if notify {
            lastPartialNotice = time
            events.append(.partial(reachable: reachable))
          }
        }
      } else if let episode = partial {
        if episode.notified {
          events.append(
            .partialResolved(
              unreachable: episode.unreachable,
              downtimeSeconds: seconds(from: episode.startedAt, to: changedAt)))
        }
        partial = nil
      }
      if case .unstable(let reason) = snapshot.state, lastKind != .unstable, notifyUnstable,
        isCooledDown(lastUnstableNotice, at: time)
      {
        lastUnstableNotice = time
        events.append(.unstable(reason))
      }
    }
    return events
  }

  private func isCooledDown(_ last: Date?, at time: Date) -> Bool {
    guard let last else { return true }
    return time.timeIntervalSince(last) >= Self.repeatCooldown
  }

  private func seconds(from start: Date, to end: Date) -> Int {
    max(0, Int(end.timeIntervalSince(start).rounded()))
  }
}

extension Region {
  /// Второй регион.
  public var other: Region {
    switch self {
    case .russia: .abroad
    case .abroad: .russia
    }
  }
}
