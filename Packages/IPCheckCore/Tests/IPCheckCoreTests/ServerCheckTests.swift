import Foundation
import IPCheckCore
import Testing

@Suite("Адрес VPN-сервера")
struct ServerAddressTests {
  @Test(
    "Корректные адреса",
    arguments: [
      "203.0.113.5", "2001:db8::1", "vpn.example.com", "nl-1.vpn.example.com", "myserver",
      "xn--80ak6aa92e.com",
    ])
  func valid(address: String) {
    #expect(ServerAddress.normalize(address) == address)
  }

  @Test(
    "Неверные адреса отклоняются",
    arguments: [
      "", "bad host!", "-vpn.example.com", "vpn-.example.com", "vpn..example.com",
      "http://vpn.example.com", "vpn.example.com:443", "vpn_example.com", "256.1.1.1",
      String(repeating: "a", count: 64) + ".com", String(repeating: "a.", count: 127) + "com",
    ])
  func invalid(address: String) {
    #expect(ServerAddress.normalize(address) == nil)
  }

  @Test("Пробелы по краям убираются")
  func trimmed() {
    #expect(ServerAddress.normalize("  203.0.113.5\n") == "203.0.113.5")
  }
}

@Suite("Как проверять сервер")
struct ServerProbePlanTests {
  @Test("Автоматически — порты 443, затем 22; «мой порт» — только он")
  func steps() {
    #expect(ServerProbePlan.steps(method: .auto, port: 8443) == [.tcp(port: 443), .tcp(port: 22)])
    #expect(ServerProbePlan.steps(method: .port, port: 8443) == [.tcp(port: 8443)])
  }

  @Test("Способ, сработавший в прошлый раз, — первым; остальные — в прежнем порядке")
  func preferredFirst() {
    let steps: [ServerProbeStep] = [.tcp(port: 443), .tcp(port: 22)]

    #expect(
      ServerProbePlan.ordered(steps, preferring: .tcp(port: 22)) == [
        .tcp(port: 22), .tcp(port: 443),
      ])
    #expect(ServerProbePlan.ordered(steps, preferring: nil) == steps)
    #expect(ServerProbePlan.ordered(steps, preferring: .tcp(port: 8443)) == steps)
  }

  @Test("Пробуем по очереди до первого ответа")
  func checkStopsAtFirstAnswer() async {
    var asked: [ServerProbeStep] = []

    let steps: [ServerProbeStep] = [.tcp(port: 443), .tcp(port: 22), .tcp(port: 8443)]
    let result = await ServerProbePlan.check(steps) { step in
      asked.append(step)
      return step == .tcp(port: 22) ? 48 : nil
    }

    #expect(result == .reachable(latencyMs: 48, via: .tcp(port: 22)))
    #expect(asked == [.tcp(port: 443), .tcp(port: 22)])
  }

  @Test("Ничего не ответило — сервер недоступен")
  func checkAllSilent() async {
    let result = await ServerProbePlan.check([.tcp(port: 443), .tcp(port: 22)]) { _ in nil }

    #expect(result == .unreachable)
  }

  @Test("Пауза: обычно 15 секунд, при подозрении на сбой — 1 секунда")
  func pause() {
    #expect(ServerProbePlan.pauseSeconds(needsConfirmation: false) == 15)
    #expect(ServerProbePlan.pauseSeconds(needsConfirmation: true) == 1)
  }
}

@Suite("Состояние сервера")
struct ServerEvaluatorTests {
  @Test("Ответил — «отвечает» с задержкой и способом")
  func reachable() {
    var evaluator = ServerEvaluator(failuresBeforeDown: 3)

    let snapshot = evaluator.record(ok(40), internetWorking: true, at: at(0))

    #expect(snapshot.status == .reachable(latencyMs: 40, via: .tcp(port: 443)))
    #expect(snapshot.since == at(0))
  }

  @Test("Две неудачи подряд — ещё «отвечает», третья — «не отвечает»")
  func downAfterThree() {
    var evaluator = ServerEvaluator(failuresBeforeDown: 3)
    evaluator.record(ok(40), internetWorking: true, at: at(0))

    evaluator.record(.unreachable, internetWorking: true, at: at(15))
    let two = evaluator.record(.unreachable, internetWorking: true, at: at(16))
    let three = evaluator.record(.unreachable, internetWorking: true, at: at(17))

    #expect(two.status == .reachable(latencyMs: 40, via: .tcp(port: 443)))
    #expect(three.status == .unreachable)
    #expect(three.since == at(17))
  }

  @Test("Число неудач берётся из настроек")
  func thresholdFromSettings() {
    var evaluator = ServerEvaluator(failuresBeforeDown: 1)
    evaluator.record(ok(40), internetWorking: true, at: at(0))

    let snapshot = evaluator.record(.unreachable, internetWorking: true, at: at(15))

    #expect(snapshot.status == .unreachable)
  }

  @Test("Нет домашнего интернета — о сервере не судим, и неудачи не копятся")
  func noInternetIsUnknown() {
    var evaluator = ServerEvaluator(failuresBeforeDown: 3)
    evaluator.record(ok(40), internetWorking: true, at: at(0))
    evaluator.record(.unreachable, internetWorking: true, at: at(15))
    evaluator.record(.unreachable, internetWorking: true, at: at(16))

    let offline = evaluator.record(.unreachable, internetWorking: false, at: at(17))
    let back = evaluator.record(.unreachable, internetWorking: true, at: at(30))

    #expect(offline.status == .unknown)
    #expect(back.status == .unknown)  // одна неудача после возврата — ещё не приговор
  }

  @Test("Удача между неудачами сбрасывает счёт")
  func successResets() {
    var evaluator = ServerEvaluator(failuresBeforeDown: 3)
    for (second, result) in [(0.0, ok(40)), (15, .unreachable), (16, .unreachable), (17, ok(42))] {
      evaluator.record(result, internetWorking: true, at: at(second))
    }
    evaluator.record(.unreachable, internetWorking: true, at: at(32))
    let snapshot = evaluator.record(.unreachable, internetWorking: true, at: at(33))

    #expect(snapshot.status == .reachable(latencyMs: 42, via: .tcp(port: 443)))
  }

  @Test("Есть неудача, но «не отвечает» ещё не решено — нужна быстрая повторная проверка")
  func confirmation() {
    var evaluator = ServerEvaluator(failuresBeforeDown: 3)
    evaluator.record(ok(40), internetWorking: true, at: at(0))
    #expect(!evaluator.needsConfirmation)

    evaluator.record(.unreachable, internetWorking: true, at: at(15))
    #expect(evaluator.needsConfirmation)

    evaluator.record(.unreachable, internetWorking: true, at: at(16))
    evaluator.record(.unreachable, internetWorking: true, at: at(17))
    #expect(!evaluator.needsConfirmation)
  }

  @Test("После пробуждения — «проверяю» с этого момента, неудачи до сна забыты")
  func wakeStartsFresh() {
    var evaluator = ServerEvaluator(failuresBeforeDown: 3)
    evaluator.record(ok(40), internetWorking: true, at: at(0))
    evaluator.record(.unreachable, internetWorking: true, at: at(15))
    evaluator.record(.unreachable, internetWorking: true, at: at(16))

    let snapshot = evaluator.systemDidWake(at: at(5000))
    let afterWake = evaluator.record(.unreachable, internetWorking: true, at: at(5001))

    #expect(snapshot.status == .checking)
    #expect(snapshot.since == at(5000))
    #expect(afterWake.status == .checking)  // одна неудача после сна — ещё не приговор
  }

  @Test("Проверка, начатая до пробуждения, не учитывается")
  func checkStartedBeforeWakeIgnored() {
    var evaluator = ServerEvaluator(failuresBeforeDown: 1)
    evaluator.record(ok(40), internetWorking: true, at: at(0))
    evaluator.systemDidWake(at: at(5000))

    let snapshot = evaluator.record(.unreachable, internetWorking: true, at: at(4990))

    #expect(snapshot.status == .checking)
    #expect(!evaluator.needsConfirmation)
  }
}

@Suite("Уведомления о сервере")
struct ServerPolicyTests {
  @Test("Был жив → не отвечает: уведомление")
  func downNotified() {
    var policy = livePolicy()

    #expect(policy.observe(snap(.unreachable, since: 30), at: at(30)) == [.down])
  }

  @Test("Не отвечал с самого запуска — без уведомлений")
  func silentAtStartup() {
    var policy = ServerPolicy()

    let events = [
      policy.observe(snap(.checking, since: 0), at: at(0)),
      policy.observe(snap(.unreachable, since: 5), at: at(5)),
    ]

    #expect(events.allSatisfy { $0.isEmpty })
  }

  @Test("Снова отвечает — уведомление со временем, сколько молчал")
  func upWithDowntime() {
    var policy = livePolicy()
    _ = policy.observe(snap(.unreachable, since: 30), at: at(30))

    let events = policy.observe(
      snap(.reachable(latencyMs: 40, via: .tcp(port: 443)), since: 270), at: at(270))

    #expect(events == [.up(downtimeSeconds: 240)])
  }

  @Test("Пропал домашний интернет посреди сбоя сервера — история сбоя не прерывается")
  func unknownKeepsEpisode() {
    var policy = livePolicy()
    _ = policy.observe(snap(.unreachable, since: 30), at: at(30))

    let unknown = policy.observe(snap(.unknown, since: 60), at: at(60))
    let up = policy.observe(
      snap(.reachable(latencyMs: 40, via: .tcp(port: 443)), since: 90), at: at(90))

    #expect(unknown.isEmpty)
    #expect(up == [.up(downtimeSeconds: 60)])
  }

  @Test("«Не отвечает» снова в течение 10 минут — молчим, и о возврате тоже")
  func cooldown() {
    var policy = livePolicy()
    _ = policy.observe(snap(.unreachable, since: 30), at: at(30))
    _ = policy.observe(snap(.reachable(latencyMs: 40, via: .tcp(port: 443)), since: 60), at: at(60))

    let again = policy.observe(snap(.unreachable, since: 300), at: at(300))
    let upAgain = policy.observe(
      snap(.reachable(latencyMs: 40, via: .tcp(port: 443)), since: 320), at: at(320))
    let later = policy.observe(snap(.unreachable, since: 630), at: at(630))

    #expect(again.isEmpty)
    #expect(upAgain.isEmpty)
    #expect(later == [.down])  // ровно 600 с после первого
  }

  @Test("Сбой сервера до сна — «снова отвечает» без минут сна")
  func downtimeExcludesSleep() {
    var policy = livePolicy()
    _ = policy.observe(snap(.unreachable, since: 30), at: at(30))

    policy.excludeSleep(seconds: 3600)
    let events = policy.observe(
      snap(.reachable(latencyMs: 40, via: .tcp(port: 443)), since: 3700), at: at(3700))

    #expect(events == [.up(downtimeSeconds: 70)])
  }

  @Test("Длительность — до момента, когда сервер ответил, а не когда это заметили")
  func downtimeEndsWhenAnswered() {
    var policy = livePolicy()
    _ = policy.observe(snap(.unreachable, since: 30), at: at(30))

    let events = policy.observe(
      snap(.reachable(latencyMs: 40, via: .tcp(port: 443)), since: 90), at: at(120))

    #expect(events == [.up(downtimeSeconds: 60)])
  }

  @Test("Состояние не изменилось — тишина")
  func unchanged() {
    var policy = livePolicy()

    #expect(
      policy.observe(snap(.reachable(latencyMs: 55, via: .tcp(port: 443)), since: 0), at: at(20))
        .isEmpty)
  }
}

// MARK: - Помощники

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ second: Double) -> Date { start.addingTimeInterval(second) }

private func ok(_ latency: Int) -> ServerProbeResult {
  .reachable(latencyMs: latency, via: .tcp(port: 443))
}

private func snap(_ status: ServerStatus, since second: Double) -> ServerSnapshot {
  var snapshot = ServerSnapshot()
  snapshot.status = status
  snapshot.since = at(second)
  return snapshot
}

/// Сервер отвечал с самого начала.
private func livePolicy() -> ServerPolicy {
  var policy = ServerPolicy()
  _ = policy.observe(snap(.checking, since: 0), at: at(0))
  _ = policy.observe(snap(.reachable(latencyMs: 40, via: .tcp(port: 443)), since: 0), at: at(0))
  return policy
}
