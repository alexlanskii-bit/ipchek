import Foundation
import IPCheckCore
import Network
import Synchronization

/// Проверка VPN-сервера напрямую через Wi-Fi/кабель, в обход VPN: открывается TCP-соединение
/// с портом сервера и сразу закрывается.
///
/// Обычным путём VPN-программа владельца сама «отвечает» за любой адрес. Привязка к физическому
/// интерфейсу (`requiredInterface`) даёт честный ответ — проверено 2026-11-06: несуществующий
/// адрес не отвечает, настоящие отвечают за 5–17 мс. Ping не используется: «песочница» macOS
/// не даёт принять ответ на него (решение владельца — права не расширять).
enum ServerProbe {
  /// До Нидерландов напрямую — десятки миллисекунд; секунды хватает с большим запасом,
  /// а два способа по секунде не затягивают обнаружение сбоя.
  static let timeoutSeconds = 1.0
  private static let queue = DispatchQueue(label: "com.lavmoviesstudio.ipchek.server")

  /// Задержка в миллисекундах или `nil`, если сервер не ответил этим способом.
  static func latency(
    of step: ServerProbeStep, host: String, via interface: NWInterface
  ) async -> Int? {
    switch step {
    case .tcp(let port):
      return await tcp(host: host, port: port, via: interface)
    }
  }

  private static func tcp(host: String, port: Int, via interface: NWInterface) async -> Int? {
    guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
    let parameters = NWParameters.tcp
    parameters.requiredInterface = interface
    let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
    let started = ContinuousClock.now
    let connected = await withCheckedContinuation { continuation in
      let once = ResumeOnce(continuation)
      connection.stateUpdateHandler = { state in
        switch state {
        case .ready: once.resume(true)
        case .waiting, .failed, .cancelled: once.resume(false)
        case .setup, .preparing: break
        @unknown default: once.resume(false)
        }
      }
      connection.start(queue: queue)
      queue.asyncAfter(deadline: .now() + timeoutSeconds) { once.resume(false) }
    }
    connection.cancel()
    guard connected else { return nil }
    return Int(((ContinuousClock.now - started) / .milliseconds(1)).rounded())
  }
}

/// Отдаёт результат ожидающему ровно один раз: что раньше — соединение, ошибка или таймаут.
private final class ResumeOnce: Sendable {
  private let continuation: Mutex<CheckedContinuation<Bool, Never>?>

  init(_ continuation: CheckedContinuation<Bool, Never>) {
    self.continuation = Mutex(continuation)
  }

  func resume(_ value: Bool) {
    let waiting = continuation.withLock { stored -> CheckedContinuation<Bool, Never>? in
      let current = stored
      stored = nil
      return current
    }
    waiting?.resume(returning: value)
  }
}
