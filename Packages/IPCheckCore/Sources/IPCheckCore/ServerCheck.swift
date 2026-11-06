import Foundation

/// Способ проверки VPN-сервера (решение владельца — «автоматически» по умолчанию).
///
/// Ping не используется (решение владельца 2026-11-06): «песочница» macOS не даёт приложению
/// принять ответ на ping без разрешения на входящие соединения («deny network-inbound»),
/// а расширять права ради ping не стали.
public enum ServerCheckMethod: String, CaseIterable, Sendable {
  /// TCP-порты 443, затем 22 — до первого ответа.
  case auto
  /// Только TCP-порт из настроек.
  case port
}

/// Проверка адреса сервера из настроек.
public enum ServerAddress {
  /// Адрес без пробелов, если это IPv4/IPv6 или корректное имя (RFC 1123); иначе `nil`.
  public static func normalize(_ text: String) -> String? {
    let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !candidate.isEmpty, candidate.utf8.count <= 253 else { return nil }
    if IPAddressText.parse(candidate) == candidate { return candidate }
    let labels = candidate.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.allSatisfy(isValidLabel) else { return nil }
    // Одни цифры через точки — это неверный IP (например, 256.1.1.1), а не имя.
    guard !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
    return candidate
  }

  /// Часть имени: 1–63 символа, латиница, цифры и дефис, но не дефис по краям.
  private static func isValidLabel(_ label: Substring) -> Bool {
    guard (1...63).contains(label.count), label.first != "-", label.last != "-" else {
      return false
    }
    return label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
  }
}

/// Один способ достучаться до сервера: открыть TCP-соединение с портом.
public enum ServerProbeStep: Equatable, Sendable {
  case tcp(port: Int)

  /// Как показывать в панели.
  public var label: String {
    switch self {
    case .tcp(let port): "порт \(port)"
    }
  }
}

/// Итог одной проверки сервера.
public enum ServerProbeResult: Equatable, Sendable {
  case reachable(latencyMs: Int, via: ServerProbeStep)
  case unreachable
}

public enum ServerProbePlan {
  /// Обычная пауза между проверками сервера (решение владельца).
  public static let intervalSeconds = 15
  public static let confirmationIntervalSeconds = 1

  public static func steps(method: ServerCheckMethod, port: Int) -> [ServerProbeStep] {
    switch method {
    case .auto: [.tcp(port: 443), .tcp(port: 22)]
    case .port: [.tcp(port: port)]
    }
  }

  /// Способ, который сработал в прошлый раз, пробуем первым: при живом сервере — одна попытка.
  public static func ordered(_ steps: [ServerProbeStep], preferring preferred: ServerProbeStep?)
    -> [ServerProbeStep]
  {
    guard let preferred, steps.contains(preferred) else { return steps }
    return [preferred] + steps.filter { $0 != preferred }
  }

  /// Пробует способы по очереди до первого ответа. `probe` — задержка в мс или `nil`.
  public static func check(
    _ steps: [ServerProbeStep], probe: (ServerProbeStep) async -> Int?
  ) async -> ServerProbeResult {
    for step in steps {
      if let latency = await probe(step) { return .reachable(latencyMs: latency, via: step) }
    }
    return .unreachable
  }

  public static func pauseSeconds(needsConfirmation: Bool) -> Int {
    needsConfirmation ? confirmationIntervalSeconds : intervalSeconds
  }
}

/// Состояние сервера, которое видит человек.
public enum ServerStatus: Equatable, Sendable {
  case checking
  case reachable(latencyMs: Int, via: ServerProbeStep)
  /// Не отвечает несколько проверок подряд, хотя домашний интернет работает.
  case unreachable
  /// Домашнего интернета нет — о сервере судить нельзя.
  case unknown
}

public struct ServerSnapshot: Equatable, Sendable {
  public var status: ServerStatus = .checking
  /// Когда началось текущее состояние.
  public var since: Date?

  public init() {}
}

/// Превращает проверки сервера в его состояние.
public struct ServerEvaluator: Sendable {
  public private(set) var snapshot = ServerSnapshot()
  private let failuresBeforeDown: Int
  private var failuresInRow = 0

  public init(failuresBeforeDown: Int) {
    self.failuresBeforeDown = max(1, failuresBeforeDown)
  }

  public var needsConfirmation: Bool {
    failuresInRow > 0 && failuresInRow < failuresBeforeDown
  }

  @discardableResult
  public mutating func record(_ result: ServerProbeResult, internetWorking: Bool, at time: Date)
    -> ServerSnapshot
  {
    // Без домашнего интернета сервер не проверить — его молчание ничего не значит.
    guard internetWorking else {
      failuresInRow = 0
      setStatus(.unknown, at: time)
      return snapshot
    }
    switch result {
    case .reachable(let latency, let step):
      failuresInRow = 0
      setStatus(.reachable(latencyMs: latency, via: step), at: time)
    case .unreachable:
      failuresInRow += 1
      if failuresInRow >= failuresBeforeDown { setStatus(.unreachable, at: time) }
    }
    return snapshot
  }

  /// Время начала меняется только при смене вида состояния (новая задержка — не новое состояние).
  private mutating func setStatus(_ status: ServerStatus, at time: Date) {
    if status.kind != snapshot.status.kind || snapshot.since == nil { snapshot.since = time }
    snapshot.status = status
  }
}

extension ServerStatus {
  enum Kind { case checking, reachable, unreachable, unknown }

  var kind: Kind {
    switch self {
    case .checking: .checking
    case .reachable: .reachable
    case .unreachable: .unreachable
    case .unknown: .unknown
    }
  }
}

/// Событие о сервере для уведомления.
public enum ServerEvent: Equatable, Sendable {
  case down
  case up(downtimeSeconds: Int)
}

/// Решает, о чём сообщать по серверу.
public struct ServerPolicy: Sendable {
  public static let repeatCooldown: TimeInterval = 600

  /// Пока сервер ни разу не ответил с запуска — молчим (как и с интернетом при запуске).
  private var hasSeenReachable = false
  private var downSince: Date?
  private var downNotified = false
  private var lastDownNotice: Date?

  public init() {}

  public mutating func observe(_ snapshot: ServerSnapshot, at time: Date) -> [ServerEvent] {
    switch snapshot.status {
    case .checking, .unknown:
      // «Нет интернета» посреди сбоя сервера историю сбоя не прерывает.
      return []
    case .reachable:
      hasSeenReachable = true
      guard let since = downSince else { return [] }
      downSince = nil
      let notified = downNotified
      downNotified = false
      return notified
        ? [.up(downtimeSeconds: max(0, Int(time.timeIntervalSince(since).rounded())))] : []
    case .unreachable:
      guard hasSeenReachable, downSince == nil else { return [] }
      downSince = snapshot.since ?? time
      if let last = lastDownNotice, time.timeIntervalSince(last) < Self.repeatCooldown {
        downNotified = false
        return []
      }
      lastDownNotice = time
      downNotified = true
      return [.down]
    }
  }
}
