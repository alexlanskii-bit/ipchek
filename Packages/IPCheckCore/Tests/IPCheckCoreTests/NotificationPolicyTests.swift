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
    _ = policy.observe(snap(.offline(.noLink), since: 20), at: at(25))  // подтверждено таймером
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

  @Test("Длительность — до момента, когда связь вернулась, а не когда это заметили")
  func downtimeEndsWhenRestored() {
    var policy = workingPolicy()
    _ = policy.observe(snap(.offline(.serversNotResponding), since: 20), at: at(20))

    let events = policy.observe(snap(.online, since: 50), at: at(80))

    #expect(events == [.restored(downtimeSeconds: 30)])
  }
}

@Suite("Пропажа Wi-Fi или кабеля: уведомление через 5 секунд (решение владельца)")
struct LinkLossConfirmationTests {
  @Test("Wi-Fi пропал и вернулся меньше чем за 5 секунд (смена сети) — ни «пропал», ни «вернулся»")
  func shortLinkLossIsSilent() {
    var policy = workingPolicy()

    let events = [
      policy.observe(snap(.offline(.noLink), since: 20, link: LinkStatus.none), at: at(20)),
      policy.observe(snap(.offline(.noLink), since: 20, link: LinkStatus.none), at: at(24.9)),
      policy.observe(snap(.checking, since: 23), at: at(24.9)),
      policy.observe(snap(.online, since: 30), at: at(30)),
    ]

    #expect(events.allSatisfy { $0.isEmpty })
  }

  @Test("Wi-Fi не вернулся за 5 секунд — «пропал»; длительность — с момента пропажи")
  func confirmedAfterFiveSeconds() {
    var policy = workingPolicy()
    _ = policy.observe(snap(.offline(.noLink), since: 20, link: LinkStatus.none), at: at(20))

    let outage = policy.observe(
      snap(.offline(.noLink), since: 20, link: LinkStatus.none), at: at(25))
    let restored = policy.observe(snap(.online, since: 60), at: at(60))

    #expect(outage == [.outage(.noLink, link: LinkStatus.none)])
    #expect(restored == [.restored(downtimeSeconds: 40)])
  }

  @Test("Пока ждём подтверждения — известно, когда спросить снова; после решения — нет")
  func recheckTime() {
    var policy = workingPolicy()
    #expect(policy.recheckAt == nil)

    _ = policy.observe(snap(.offline(.noLink), since: 20, link: LinkStatus.none), at: at(20))
    #expect(policy.recheckAt == at(25))

    _ = policy.observe(snap(.offline(.noLink), since: 20, link: LinkStatus.none), at: at(25))
    #expect(policy.recheckAt == nil)
  }

  @Test("Wi-Fi вернулся до подтверждения — спрашивать снова не нужно")
  func recheckClearedWhenLinkBack() {
    var policy = workingPolicy()
    _ = policy.observe(snap(.offline(.noLink), since: 20, link: LinkStatus.none), at: at(20))

    _ = policy.observe(snap(.checking, since: 22), at: at(22))

    #expect(policy.recheckAt == nil)
  }

  @Test("Серверы не отвечают при живом Wi-Fi — уведомление сразу, без ожидания")
  func serverOutageNotDelayed() {
    var policy = workingPolicy()

    let events = policy.observe(snap(.offline(.serversNotResponding), since: 20), at: at(20))

    #expect(events == [.outage(.serversNotResponding, link: .wifi)])
    #expect(policy.recheckAt == nil)
  }

  @Test("При запуске без Wi-Fi ждать нечего — уведомлений и проверок по таймеру нет")
  func noRecheckAtStartup() {
    var policy = NotificationPolicy()
    _ = policy.observe(snap(.offline(.noLink), since: 0, link: LinkStatus.none), at: at(0))

    #expect(policy.recheckAt == nil)
  }
}

@Suite("Минуты сна не считаются разрывом")
struct NotificationSleepTests {
  @Test("Разрыв до сна — «вернулся» с длительностью без минут сна")
  func outageExcludesSleep() {
    var policy = workingPolicy()
    _ = policy.observe(snap(.offline(.serversNotResponding), since: 20), at: at(20))

    policy.excludeSleep(seconds: 3600)  // Mac спал час
    let events = policy.observe(snap(.online, since: 3700), at: at(3700))

    #expect(events == [.restored(downtimeSeconds: 80)])
  }

  @Test("«Часть сайтов недоступна» до сна — «снова доступны» без минут сна")
  func partialExcludesSleep() {
    var policy = workingPolicy()
    _ = policy.observe(snap(.partial(reachable: .russia), since: 50), at: at(50))

    policy.excludeSleep(seconds: 1000)
    let events = policy.observe(snap(.online, since: 1100), at: at(1100))

    #expect(events == [.partialResolved(unreachable: .abroad, downtimeSeconds: 50)])
  }

  @Test("Без разрыва сон ничего не меняет")
  func noEpisodeNoChange() {
    var policy = workingPolicy()

    policy.excludeSleep(seconds: 600)
    let events = policy.observe(snap(.online, since: 5), at: at(700))

    #expect(events.isEmpty)
  }

  @Test("Ожидание подтверждения пропажи Wi-Fi сдвигается на время сна")
  func pendingLinkLossShifted() {
    var policy = workingPolicy()
    _ = policy.observe(snap(.offline(.noLink), since: 20, link: LinkStatus.none), at: at(20))

    policy.excludeSleep(seconds: 100)

    #expect(policy.recheckAt == at(125))
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
