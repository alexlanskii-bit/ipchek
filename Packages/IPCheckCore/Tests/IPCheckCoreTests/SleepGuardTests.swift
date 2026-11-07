import Foundation
import IPCheckCore
import Testing

@Suite("Сон Mac: пауза без тревог")
struct SleepGuardTests {
  @Test("Обычная работа — тревоги разрешены")
  func awakeIsNotQuiet() {
    let guardian = SleepGuard()

    #expect(!guardian.isQuiet(at: at(0)))
    #expect(!guardian.isAsleep)
  }

  @Test("Пока Mac спит — без тревог, сколько бы это ни длилось")
  func asleepIsQuiet() {
    var guardian = SleepGuard()
    guardian.willSleep(at: at(100))

    #expect(guardian.isAsleep)
    #expect(guardian.isQuiet(at: at(100)))
    #expect(guardian.isQuiet(at: at(100 + 8 * 3600)))
  }

  @Test("После пробуждения — пауза из настроек; на её последней секунде ещё тихо, после — нет")
  func graceAfterWake() {
    var guardian = SleepGuard()
    guardian.willSleep(at: at(100))

    guardian.didWake(at: at(1000), graceSeconds: 30)

    #expect(!guardian.isAsleep)
    #expect(guardian.quietUntil == at(1030))
    #expect(guardian.isQuiet(at: at(1029)))
    #expect(!guardian.isQuiet(at: at(1030)))
  }

  @Test("Пробуждение говорит, сколько Mac спал")
  func sleptDuration() {
    var guardian = SleepGuard()
    guardian.willSleep(at: at(100))

    #expect(guardian.didWake(at: at(700), graceSeconds: 30) == 600)
  }

  @Test("Пробуждение без сообщения о засыпании — пауза есть, сна 0 секунд")
  func wakeWithoutSleep() {
    var guardian = SleepGuard()

    let slept = guardian.didWake(at: at(50), graceSeconds: 30)

    #expect(slept == 0)
    #expect(guardian.isQuiet(at: at(60)))
  }

  @Test("Два сообщения о засыпании подряд — сон считается от первого")
  func doubleSleepKeepsFirst() {
    var guardian = SleepGuard()
    guardian.willSleep(at: at(100))
    guardian.willSleep(at: at(200))

    #expect(guardian.didWake(at: at(400), graceSeconds: 30) == 300)
  }

  @Test("Пауза 0 секунд — тревоги сразу после пробуждения")
  func zeroGrace() {
    var guardian = SleepGuard()
    guardian.willSleep(at: at(100))

    guardian.didWake(at: at(200), graceSeconds: 0)

    #expect(!guardian.isQuiet(at: at(200)))
  }

  @Test("Неверная пауза (меньше нуля) считается нулём")
  func negativeGrace() {
    var guardian = SleepGuard()

    guardian.didWake(at: at(200), graceSeconds: -5)

    #expect(!guardian.isQuiet(at: at(200)))
  }

  @Test("Короткий сон внутри паузы не укорачивает её")
  func shortSleepDoesNotShortenGrace() {
    var guardian = SleepGuard()
    guardian.didWake(at: at(100), graceSeconds: 60)  // тихо до 160
    guardian.willSleep(at: at(110))

    guardian.didWake(at: at(115), graceSeconds: 0)

    #expect(guardian.isQuiet(at: at(150)))
    #expect(!guardian.isQuiet(at: at(160)))
  }

  @Test("Снова уснул во время паузы — тихо, пока спит")
  func sleepDuringGrace() {
    var guardian = SleepGuard()
    guardian.didWake(at: at(100), graceSeconds: 30)

    guardian.willSleep(at: at(110))

    #expect(guardian.isQuiet(at: at(5000)))
  }
}

@Suite("Сон Mac: ложных тревог нет, настоящие — есть")
struct SleepScenarioTests {
  @Test("Закрыл крышку на 10 минут, Wi-Fi пропал и вернулся в паузе — ни одного уведомления")
  func lidClosedTenMinutes() {
    var mac = MacSimulation()
    mac.online(until: 100)

    mac.sleep(at: 100)
    mac.link(.none, at: 101)  // Wi-Fi выключается уже во сне
    mac.wake(at: 700)
    mac.link(.wifi, at: 705)
    mac.round(at: 706, fast, fast)
    mac.round(at: 711, fast, fast)
    mac.tick(at: 730)  // пауза кончилась — проверка по таймеру
    mac.round(at: 735, fast, fast)

    #expect(mac.events.isEmpty)
    #expect(mac.evaluator.snapshot.state == .online)
  }

  @Test("Проснулся, а интернета нет и после паузы — уведомление «пропал»")
  func noInternetAfterWake() {
    var mac = MacSimulation()
    mac.online(until: 100)

    mac.sleep(at: 100)
    mac.wake(at: 700)
    mac.round(at: 701, down, down)
    mac.round(at: 702, down, down)
    mac.round(at: 703, down, down)
    mac.tick(at: 730)

    #expect(mac.events == [.outage(.serversNotResponding, link: .wifi)])
  }

  @Test("Проснулся без Wi-Fi (например, в дороге) — уведомление по таймеру после паузы")
  func noWiFiAfterWake() {
    var mac = MacSimulation()
    mac.online(until: 100)

    mac.sleep(at: 100)
    mac.link(.none, at: 101)
    mac.wake(at: 700)
    mac.tick(at: 730)

    #expect(mac.events == [.outage(.noLink, link: LinkStatus.none)])
  }

  @Test("Разрыв до сна, вернулся во время сна — «вернулся» без минут сна")
  func outageBeforeSleepExcludesSleepTime() {
    var mac = MacSimulation()
    mac.online(until: 100)
    mac.round(at: 100, down, down)
    mac.round(at: 101, down, down)
    mac.round(at: 102, down, down)  // третья неудача — разрыв со 102-й секунды
    #expect(mac.events == [.outage(.serversNotResponding, link: .wifi)])

    mac.sleep(at: 160)  // 58 с разрыва до сна
    mac.wake(at: 8 * 3600)
    mac.round(at: 8 * 3600 + 1, fast, fast)  // интернет есть через 1 с после пробуждения
    mac.tick(at: 8 * 3600 + 30)  // узнаём об этом после паузы

    #expect(mac.events.last == .restored(downtimeSeconds: 59))  // 58 с до сна + 1 с после
  }

  @Test("Проверка, начатая до сна и закончившаяся после, не считается неудачей")
  func roundStartedBeforeSleepIgnored() {
    var mac = MacSimulation()
    mac.online(until: 100)
    mac.sleep(at: 100)
    mac.wake(at: 700)

    mac.round(at: 99, down, down)  // начата до сна, ответа не дождалась

    #expect(!mac.evaluator.needsConfirmation)
    #expect(mac.evaluator.snapshot.state == .checking)
  }
}

// MARK: - Помощники

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let down = RegionResult.unreachable
private let fast = RegionResult.reachable(latencyMs: 20, via: "тест")

private func at(_ second: Double) -> Date { start.addingTimeInterval(second) }

/// Как приложение связывает части: оценка связи → (если не пауза) правила уведомлений.
private struct MacSimulation {
  var evaluator = ConnectivityEvaluator(settings: passportDefaults)
  var policy = NotificationPolicy()
  var guardian = SleepGuard()
  var events: [ConnectivityEvent] = []

  mutating func online(until second: Double) {
    link(.wifi, at: 0)
    round(at: 5, fast, fast)
    round(at: second - 1, fast, fast)
  }

  mutating func link(_ status: LinkStatus, at second: Double) {
    deliver(evaluator.linkChanged(to: status, at: at(second)), at: second)
  }

  mutating func round(at second: Double, _ russia: RegionResult, _ abroad: RegionResult) {
    deliver(
      evaluator.record(CheckRound(at: at(second), russia: russia, abroad: abroad)), at: second)
  }

  mutating func sleep(at second: Double) {
    guardian.willSleep(at: at(second))
  }

  mutating func wake(at second: Double) {
    let slept = guardian.didWake(at: at(second), graceSeconds: passportDefaults.wakeGraceSeconds)
    policy.excludeSleep(seconds: slept)
    deliver(evaluator.systemDidWake(at: at(second)), at: second)
  }

  /// Проверка по таймеру — то же состояние ещё раз (конец паузы, подтверждение пропажи Wi-Fi).
  mutating func tick(at second: Double) {
    deliver(evaluator.snapshot, at: second)
  }

  private mutating func deliver(_ snapshot: ConnectivitySnapshot, at second: Double) {
    guard !guardian.isQuiet(at: at(second)) else { return }
    events += policy.observe(snapshot, at: at(second), notifyUnstable: true)
  }
}
