import Foundation
import IPCheckCore
import Testing

@Suite("О чём сообщать уведомлением")
struct NotificationPolicyTests {
  @Test("Работало → разрыв: одно уведомление «пропал» с причиной")
  func outageNotified() {
    var policy = workingPolicy()

    let events = policy.observe(snap(.offline(.serversNotResponding), since: 20), at: at(20))

    #expect(events == [.outage(.serversNotResponding, link: .wifi)])
  }

  @Test("Разрыв продолжается или на миг «проверяю» — повторных уведомлений нет")
  func outageNotRepeated() {
    var policy = workingPolicy()
    _ = policy.observe(snap(.offline(.serversNotResponding), since: 20), at: at(20))

    let same = policy.observe(snap(.offline(.serversNotResponding), since: 20), at: at(25))
    let checking = policy.observe(snap(.checking, since: 30), at: at(30))
    let again = policy.observe(snap(.offline(.serversNotResponding), since: 31), at: at(31))

    #expect(same.isEmpty && checking.isEmpty && again.isEmpty)
  }

  @Test("Интернет вернулся — уведомление с длительностью от начала разрыва")
  func restoredWithDowntime() {
    var policy = workingPolicy()
    _ = policy.observe(snap(.offline(.noLink), since: 20), at: at(20))
    _ = policy.observe(snap(.checking, since: 30), at: at(30))

    let events = policy.observe(snap(.online, since: 35), at: at(35))

    #expect(events == [.restored(downtimeSeconds: 15)])
  }

  @Test("Запуск без интернета — ни «пропал», ни потом «вернулся»")
  func noNoiseAtStartup() {
    var policy = NotificationPolicy()

    let events = [
      policy.observe(snap(.checking, since: 0), at: at(0)),
      policy.observe(snap(.offline(.noLink), since: 1), at: at(1)),
      policy.observe(snap(.checking, since: 20), at: at(20)),
      policy.observe(snap(.online, since: 25), at: at(25)),
    ]

    #expect(events.allSatisfy { $0.isEmpty })
  }

  @Test("Нестабильно — уведомление; повтор не раньше чем через 10 минут")
  func unstableCooldown() {
    var policy = workingPolicy()
    let slow = ConnectionState.unstable(.highLatency(ms: 420, threshold: 300))

    let first = policy.observe(snap(slow, since: 100), at: at(100))
    _ = policy.observe(snap(.online, since: 150), at: at(150))
    let tooSoon = policy.observe(snap(slow, since: 699), at: at(699))
    _ = policy.observe(snap(.online, since: 700), at: at(700))
    let later = policy.observe(snap(slow, since: 700), at: at(700))

    #expect(first == [.unstable(.highLatency(ms: 420, threshold: 300))])
    #expect(tooSoon.isEmpty)  // 599 с после первого
    #expect(later == [.unstable(.highLatency(ms: 420, threshold: 300))])  // ровно 600 с
  }

  @Test("Связь остаётся нестабильной 20 минут — уведомление одно, при входе в это состояние")
  func longUnstableNotifiedOnce() {
    var policy = workingPolicy()
    let slow = ConnectionState.unstable(.highLatency(ms: 420, threshold: 300))

    let first = policy.observe(snap(slow, since: 100), at: at(100))
    let later = policy.observe(snap(slow, since: 100), at: at(1300))

    #expect(first.count == 1)
    #expect(later.isEmpty)
  }

  @Test("Уведомления о нестабильной связи выключены — молчим")
  func unstableSwitchedOff() {
    var policy = workingPolicy()

    let events = policy.observe(
      snap(.unstable(.packetLoss(percent: 15, threshold: 10)), since: 100), at: at(100),
      notifyUnstable: false)

    #expect(events.isEmpty)
  }

  @Test("Часть сайтов недоступна — уведомление; снова доступны — с длительностью")
  func partialAndResolved() {
    var policy = workingPolicy()

    let partial = policy.observe(snap(.partial(reachable: .russia), since: 50), at: at(50))
    let resolved = policy.observe(snap(.online, since: 230), at: at(230))

    #expect(partial == [.partial(reachable: .russia)])
    #expect(resolved == [.partialResolved(unreachable: .abroad, downtimeSeconds: 180)])
  }

  @Test("«Частично» снова в течение 10 минут — молчим, и о возврате тоже")
  func partialCooldownSilencesBoth() {
    var policy = workingPolicy()
    _ = policy.observe(snap(.partial(reachable: .russia), since: 50), at: at(50))
    _ = policy.observe(snap(.online, since: 100), at: at(100))

    let again = policy.observe(snap(.partial(reachable: .russia), since: 300), at: at(300))
    let resolvedAgain = policy.observe(snap(.online, since: 320), at: at(320))

    #expect(again.isEmpty)
    #expect(resolvedAgain.isEmpty)
  }

  @Test(
    "Разрыв во время «частично»: сообщаем о разрыве и о возврате интернета, без «сайты доступны»")
  func outageDuringPartial() {
    var policy = workingPolicy()
    _ = policy.observe(snap(.partial(reachable: .russia), since: 50), at: at(50))

    let outage = policy.observe(snap(.offline(.serversNotResponding), since: 80), at: at(80))
    let restored = policy.observe(snap(.online, since: 100), at: at(100))

    #expect(outage == [.outage(.serversNotResponding, link: .wifi)])
    #expect(restored == [.restored(downtimeSeconds: 20)])
  }

  @Test("Интернет вернулся, но часть сайтов недоступна — оба уведомления")
  func restoredIntoPartial() {
    var policy = workingPolicy()
    _ = policy.observe(snap(.offline(.serversNotResponding), since: 20), at: at(20))

    let events = policy.observe(snap(.partial(reachable: .russia), since: 40), at: at(40))

    #expect(events == [.restored(downtimeSeconds: 20), .partial(reachable: .russia)])
  }

  @Test("Состояние не изменилось — уведомлений нет")
  func unchangedStateIsSilent() {
    var policy = workingPolicy()

    let events = policy.observe(snap(.online, since: 5), at: at(10))

    #expect(events.isEmpty)
  }
}

// MARK: - Помощники

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ second: Double) -> Date { start.addingTimeInterval(second) }

private func snap(_ state: ConnectionState, since second: Double, link: LinkStatus = .wifi)
  -> ConnectivitySnapshot
{
  var snapshot = ConnectivitySnapshot()
  snapshot.state = state
  snapshot.stateSince = at(second)
  snapshot.link = link
  return snapshot
}

extension NotificationPolicy {
  fileprivate mutating func observe(_ snapshot: ConnectivitySnapshot, at time: Date)
    -> [ConnectivityEvent]
  {
    observe(snapshot, at: time, notifyUnstable: true)
  }
}

/// Приложение видело работающий интернет (на 5-й секунде).
private func workingPolicy() -> NotificationPolicy {
  var policy = NotificationPolicy()
  _ = policy.observe(snap(.checking, since: 0), at: at(0))
  _ = policy.observe(snap(.online, since: 5), at: at(5))
  return policy
}
