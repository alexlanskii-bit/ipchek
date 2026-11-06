import Foundation
import IPCheckCore
import Testing

@Suite("Состояние связи")
struct ConnectivityEvaluatorTests {
  @Test("До первой проверки — «проверяю»")
  func startsChecking() {
    let evaluator = ConnectivityEvaluator(settings: passportDefaults)

    #expect(evaluator.snapshot.state == .checking)
  }

  @Test("Есть неудача, но разрыв ещё не решён — нужна быстрая проверка")
  func confirmationNeededWhileUndecided() {
    var evaluator = onlineEvaluator()
    #expect(!evaluator.needsConfirmation)

    evaluator.record(round(10, down, down))
    #expect(evaluator.needsConfirmation)

    evaluator.record(round(11, down, down))
    evaluator.record(round(12, down, down))  // разрыв решён
    #expect(!evaluator.needsConfirmation)
  }

  @Test("Один регион молчит — быстрая проверка, пока не решено «частично»")
  func confirmationForRegion() {
    var evaluator = onlineEvaluator()

    evaluator.record(round(10, fast, down))
    #expect(evaluator.needsConfirmation)

    evaluator.record(round(11, fast, down))
    evaluator.record(round(12, fast, down))  // «частично» решено
    #expect(!evaluator.needsConfirmation)

    evaluator.record(round(17, fast, fast))
    #expect(!evaluator.needsConfirmation)
  }

  @Test("Пропали Wi-Fi и кабель — сразу «нет интернета»")
  func noLinkIsOfflineImmediately() {
    var evaluator = onlineEvaluator()

    let snapshot = evaluator.linkChanged(to: .none, at: at(100))

    #expect(snapshot.state == .offline(.noLink))
    #expect(snapshot.stateSince == at(100))
  }

  @Test("Две неудачные проверки подряд — ещё не разрыв, третья — разрыв")
  func outageAfterThreeFailedRounds() {
    var evaluator = onlineEvaluator()

    evaluator.record(round(10, down, down))
    let afterTwo = evaluator.record(round(15, down, down))
    let afterThree = evaluator.record(round(20, down, down))

    #expect(afterTwo.state == .online)
    #expect(afterThree.state == .offline(.serversNotResponding))
    #expect(afterThree.stateSince == at(20))
  }

  @Test("Число неудач до разрыва берётся из настроек")
  func outageThresholdComesFromSettings() {
    var settings = passportDefaults
    settings.failuresBeforeOutage = 2
    var evaluator = onlineEvaluator(settings: settings)

    evaluator.record(round(10, down, down))
    let afterTwo = evaluator.record(round(15, down, down))

    #expect(afterTwo.state == .offline(.serversNotResponding))
  }

  @Test("Удачная проверка между неудачами сбрасывает счёт")
  func successResetsFailureCount() {
    var evaluator = onlineEvaluator()

    evaluator.record(round(10, down, down))
    evaluator.record(round(15, down, down))
    evaluator.record(round(20, fast, fast))
    evaluator.record(round(25, down, down))
    let snapshot = evaluator.record(round(30, down, down))

    #expect(snapshot.state != .offline(.serversNotResponding))
  }

  @Test("После разрыва нужны две удачные проверки подряд")
  func recoveryNeedsTwoGoodRounds() {
    var evaluator = offlineEvaluator()

    let afterOne = evaluator.record(round(30, fast, fast))
    let afterTwo = evaluator.record(round(35, fast, fast))

    #expect(afterOne.state == .checking)
    #expect(afterTwo.state == .online)
    #expect(afterTwo.lossPercent == 0)  // неудачи времени разрыва — не потери
  }

  @Test("Разрыв продолжается — время его начала не сдвигается")
  func outageStartStaysPut() {
    var evaluator = offlineEvaluator()  // разрыв начался на 20-й секунде

    let later = evaluator.record(round(40, down, down))

    #expect(later.state == .offline(.serversNotResponding))
    #expect(later.stateSince == at(20))
  }

  @Test("Wi-Fi вернулся — «проверяю», после двух удачных проверок — «работает»")
  func linkBackThenRecovery() {
    var evaluator = onlineEvaluator()
    evaluator.linkChanged(to: .none, at: at(10))

    let back = evaluator.linkChanged(to: .wifi, at: at(20))
    let afterOne = evaluator.record(round(25, fast, fast))
    let afterTwo = evaluator.record(round(30, fast, fast))

    #expect(back.state == .checking)
    #expect(afterOne.state == .checking)
    #expect(afterTwo.state == .online)
  }

  @Test("Пока нет ни Wi-Fi, ни кабеля, проверки не меняют состояние")
  func roundsWithoutLinkKeepNoLink() {
    var evaluator = onlineEvaluator()
    evaluator.linkChanged(to: .none, at: at(10))

    let snapshot = evaluator.record(round(15, fast, fast))

    #expect(snapshot.state == .offline(.noLink))
  }

  @Test(
    "Один регион не отвечает три раза подряд — «частично»",
    arguments: [Region.russia, Region.abroad])
  func partialWhenOneRegionDown(reachable: Region) {
    var evaluator = onlineEvaluator()
    func partialRound(_ second: Double) -> CheckRound {
      reachable == .russia ? round(second, fast, down) : round(second, down, fast)
    }

    evaluator.record(partialRound(10))
    let afterTwo = evaluator.record(partialRound(15))
    let afterThree = evaluator.record(partialRound(20))

    #expect(afterTwo.state == .online)
    #expect(afterThree.state == .partial(reachable: reachable))
  }

  @Test("Потери за минуту выше порога — «нестабильно», ровно на пороге — «работает»")
  func packetLossThreshold() {
    // 10 раундов = 20 проверок регионов. 3 неудачи = 15%, 2 неудачи = 10%.
    let fifteen = runRounds(abroadFailsAt: [1, 4, 7])
    let ten = runRounds(abroadFailsAt: [1, 4])

    #expect(fifteen.state == .unstable(.packetLoss(percent: 15, threshold: 10)))
    #expect(ten.state == .online)
    #expect(ten.lossPercent == 10)
  }

  @Test("Средняя задержка выше порога — «нестабильно», ровно на пороге — «работает»")
  func latencyThreshold() {
    var slow = onlineEvaluator(latency: 301)
    var edge = onlineEvaluator(latency: 300)
    for second in [10.0, 15, 20] {
      slow.record(round(second, ms(301), ms(301)))
      edge.record(round(second, ms(300), ms(300)))
    }

    #expect(slow.snapshot.state == .unstable(.highLatency(ms: 301, threshold: 300)))
    #expect(edge.snapshot.state == .online)
  }

  @Test("Неудачи старше минуты не считаются")
  func oldFailuresExpire() {
    var evaluator = onlineEvaluator()
    evaluator.record(round(10, fast, down))
    evaluator.record(round(15, fast, fast))
    evaluator.record(round(20, fast, down))
    var snapshot = evaluator.snapshot
    for second in stride(from: 25.0, through: 85, by: 5) {
      snapshot = evaluator.record(round(second, fast, fast))
    }

    #expect(snapshot.lossPercent == 0)
    #expect(snapshot.state == .online)
  }

  @Test("Пока проверок мало, о качестве не судим")
  func tooFewChecksToJudgeQuality() {
    var evaluator = ConnectivityEvaluator(settings: passportDefaults)
    evaluator.linkChanged(to: .wifi, at: at(0))

    // Задержка выше порога, но проверок всего две.
    let snapshot = evaluator.record(round(5, ms(400), ms(400)))

    #expect(snapshot.latencyMs == 400)
    #expect(snapshot.state == .online)
  }

  @Test("Задержка — среднее по ответившим серверам, потери — доля случайных сбоев")
  func latencyAndLossNumbers() {
    var evaluator = ConnectivityEvaluator(settings: passportDefaults)
    evaluator.linkChanged(to: .wifi, at: at(0))

    evaluator.record(round(5, ms(20), ms(40)))
    evaluator.record(round(10, ms(30), down))
    let snapshot = evaluator.record(round(15, ms(25), ms(35)))

    #expect(snapshot.latencyMs == 30)  // (20 + 40 + 30 + 25 + 35) / 5
    #expect(snapshot.lossPercent == 17)  // 1 сбой из 6 проверок
    #expect(snapshot.russia == ms(25))
    #expect(snapshot.abroad == ms(35))
  }

  @Test("Свежий сбой, который ещё может оказаться разрывом, в потери пока не идёт")
  func undecidedFailureIsNotLossYet() {
    var evaluator = ConnectivityEvaluator(settings: passportDefaults)
    evaluator.linkChanged(to: .wifi, at: at(0))

    evaluator.record(round(5, fast, fast))
    let snapshot = evaluator.record(round(10, fast, down))

    #expect(snapshot.lossPercent == 0)
    #expect(snapshot.abroad == down)
  }

  @Test("Сбой перед пропажей Wi-Fi — часть разрыва, а не потери")
  func failureBeforeLinkLossIsNotLoss() {
    var evaluator = onlineEvaluator()
    evaluator.record(round(10, down, down))
    evaluator.linkChanged(to: .none, at: at(12))
    evaluator.linkChanged(to: .wifi, at: at(14))

    evaluator.record(round(15, fast, fast))
    let snapshot = evaluator.record(round(20, fast, fast))

    #expect(snapshot.lossPercent == 0)
    #expect(snapshot.state == .online)
  }

  @Test("Неудачи, из которых сложилось «частично», не считаются потерями")
  func partialFailuresAreNotLoss() {
    var evaluator = onlineEvaluator()
    for second in [10.0, 15, 20] {
      evaluator.record(round(second, fast, down))
    }

    let snapshot = evaluator.record(round(25, fast, fast))

    #expect(snapshot.lossPercent == 0)
    #expect(snapshot.state == .online)
  }
}

// MARK: - Помощники

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let down = RegionResult.unreachable
private let fast = ms(20)

private func at(_ second: Double) -> Date { start.addingTimeInterval(second) }

private func ms(_ value: Int) -> RegionResult { .reachable(latencyMs: value, via: "тест") }

private func round(_ second: Double, _ russia: RegionResult, _ abroad: RegionResult) -> CheckRound {
  CheckRound(at: at(second), russia: russia, abroad: abroad)
}

/// Wi-Fi есть, одна удачная проверка на 5-й секунде — состояние «работает».
private func onlineEvaluator(settings: MonitorSettings = passportDefaults, latency: Int = 20)
  -> ConnectivityEvaluator
{
  var evaluator = ConnectivityEvaluator(settings: settings)
  evaluator.linkChanged(to: .wifi, at: at(0))
  evaluator.record(round(5, ms(latency), ms(latency)))
  return evaluator
}

/// Разрыв начался на 20-й секунде (три неудачные проверки).
private func offlineEvaluator() -> ConnectivityEvaluator {
  var evaluator = onlineEvaluator()
  for second in [10.0, 15, 20] {
    evaluator.record(round(second, down, down))
  }
  return evaluator
}

/// 10 раундов раз в 5 секунд; зарубежные серверы не отвечают в указанных раундах (с нуля).
private func runRounds(abroadFailsAt failures: Set<Int>) -> ConnectivitySnapshot {
  var evaluator = ConnectivityEvaluator(settings: passportDefaults)
  evaluator.linkChanged(to: .wifi, at: at(0))
  var snapshot = evaluator.snapshot
  for index in 0..<10 {
    let abroad = failures.contains(index) ? down : fast
    snapshot = evaluator.record(round(Double(5 + index * 5), fast, abroad))
  }
  return snapshot
}
