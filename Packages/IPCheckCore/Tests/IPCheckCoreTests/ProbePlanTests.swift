import Foundation
import IPCheckCore
import Testing

@Suite("Проверка регионов")
struct ProbePlanTests {
  private let primary = ProbeTarget(
    name: "Основной", url: "http://example.test/a", expectation: .noContent)
  private let backup = ProbeTarget(
    name: "Запасной", url: "http://example.test/b", expectation: .noContent)

  @Test("Основной сервер ответил — запасной не трогаем")
  func primaryAnswers() async {
    var asked: [String] = []

    let result = await ProbePlan.check([primary, backup]) { target in
      asked.append(target.name)
      return 15
    }

    #expect(result == .reachable(latencyMs: 15, via: "Основной"))
    #expect(asked == ["Основной"])
  }

  @Test("Основной молчит — пробуем запасной")
  func backupAnswers() async {
    var asked: [String] = []

    let result = await ProbePlan.check([primary, backup]) { target in
      asked.append(target.name)
      return target == backup ? 25 : nil
    }

    #expect(result == .reachable(latencyMs: 25, via: "Запасной"))
    #expect(asked == ["Основной", "Запасной"])
  }

  @Test("Оба молчат — регион недоступен")
  func bothSilent() async {
    var asked: [String] = []

    let result = await ProbePlan.check([primary, backup]) { target in
      asked.append(target.name)
      return nil
    }

    #expect(result == .unreachable)
    #expect(asked == ["Основной", "Запасной"])
  }

  @Test("У каждого региона есть основной и запасной адрес, адреса корректные")
  func everyRegionHasBackup() {
    for region in Region.allCases {
      let targets = ProbePlan.targets(for: region)
      #expect(targets.count >= 2, "регион \(region)")
      for target in targets {
        #expect(URL(string: target.url)?.host != nil, "\(target.name): \(target.url)")
      }
    }
    #expect(ProbePlan.targets(for: .russia) == ProbePlan.russia)
    #expect(ProbePlan.targets(for: .abroad) == ProbePlan.abroad)
  }

  @Test(
    "Пауза между проверками — из настроек, в «дорогой» сети в 6 раз длиннее",
    arguments: [(5, false, 5), (5, true, 30), (10, false, 10), (10, true, 60)])
  func interval(seconds: Int, expensive: Bool, expected: Int) {
    var settings = passportDefaults
    settings.checkIntervalSeconds = seconds

    #expect(ProbePlan.intervalSeconds(settings: settings, isExpensive: expensive) == expected)
  }

  @Test("Подозрение на разрыв проверяется через 1 секунду, даже в «дорогой» сети")
  func confirmationInterval() {
    for expensive in [false, true] {
      #expect(
        ProbePlan.intervalSeconds(
          settings: passportDefaults, isExpensive: expensive, needsConfirmation: true) == 1)
    }
  }
}
