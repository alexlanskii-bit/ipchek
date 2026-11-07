import Foundation

/// Сон Mac: пока Mac спит и ещё `wakeGraceSeconds` после пробуждения — без тревог
/// (паспорт, раздел 11: «после пробуждения 30 с на переподключение без тревог»).
///
/// Сам ничего не глушит: приложение спрашивает `isQuiet` перед тем, как отдать состояние
/// правилам уведомлений, а по окончании паузы показывает им текущее состояние ещё раз.
public struct SleepGuard: Sendable {
  public private(set) var isAsleep = false
  /// До какого момента после последнего пробуждения тревог нет.
  public private(set) var quietUntil: Date?
  private var sleptAt: Date?

  public init() {}

  public mutating func willSleep(at time: Date) {
    guard !isAsleep else { return }  // повторное сообщение — сон считаем от первого
    isAsleep = true
    sleptAt = time
  }

  /// Возвращает, сколько секунд Mac спал (0, если о засыпании не сообщали).
  @discardableResult
  public mutating func didWake(at time: Date, graceSeconds: Int) -> TimeInterval {
    let slept = sleptAt.map { max(0, time.timeIntervalSince($0)) } ?? 0
    isAsleep = false
    sleptAt = nil
    let until = time.addingTimeInterval(TimeInterval(max(0, graceSeconds)))
    // Короткий сон внутри паузы её не укорачивает.
    quietUntil = max(quietUntil ?? until, until)
    return slept
  }

  public func isQuiet(at time: Date) -> Bool {
    if isAsleep { return true }
    guard let quietUntil else { return false }
    return time < quietUntil
  }
}
