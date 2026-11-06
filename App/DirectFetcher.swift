import Foundation
import IPCheckCore
import Network
import Synchronization

/// HTTPS-запрос напрямую через Wi-Fi/кабель, в обход VPN (решение владельца 2026-11-06 — так
/// узнаётся ваш настоящий IP). URLSession привязываться к интерфейсу не умеет, поэтому соединение
/// открывается через Network.framework: TLS и проверку сертификата сервера делает macOS
/// (`NWParameters.tls`), привязку — `requiredInterface`. Сборка запроса и разбор ответа —
/// `DirectHTTP` (покрыты тестами).
enum DirectFetcher {
  static let timeoutSeconds = 5.0
  private static let queue = DispatchQueue(label: "com.lavmoviesstudio.ipchek.direct")

  /// Код ответа и содержимое или `nil`, если ответа не было.
  static func get(_ url: String, via interface: NWInterface) async -> (status: Int, body: Data)? {
    guard let request = DirectHTTP.request(for: url), let host = URL(string: url)?.host else {
      return nil
    }
    let parameters = NWParameters.tls
    parameters.requiredInterface = interface
    let connection = NWConnection(host: NWEndpoint.Host(host), port: .https, using: parameters)
    let exchange = Exchange(connection: connection, request: request)
    let response = await withCheckedContinuation { continuation in
      exchange.start(continuation, on: queue)
      queue.asyncAfter(deadline: .now() + timeoutSeconds) { exchange.finish(nil) }
    }
    connection.cancel()
    return response.flatMap(DirectHTTP.parse)
  }
}

/// Один обмен: отправить запрос, дочитать ответ до закрытия соединения, отдать результат один раз.
private final class Exchange: Sendable {
  private let connection: NWConnection
  private let request: Data
  private let state = Mutex<State>(State())

  private struct State {
    var continuation: CheckedContinuation<Data?, Never>?
    var received = Data()
  }

  init(connection: NWConnection, request: Data) {
    self.connection = connection
    self.request = request
  }

  func start(_ continuation: CheckedContinuation<Data?, Never>, on queue: DispatchQueue) {
    state.withLock { $0.continuation = continuation }
    connection.stateUpdateHandler = { [self] connectionState in
      switch connectionState {
      case .ready:
        connection.send(
          content: request,
          completion: .contentProcessed { [self] error in
            if error != nil { finish(nil) }
          })
        receive()
      case .waiting, .failed, .cancelled:
        finish(nil)
      case .setup, .preparing:
        break
      @unknown default:
        finish(nil)
      }
    }
    connection.start(queue: queue)
  }

  private func receive() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
      [self] data, _, isComplete, error in
      let tooLong = state.withLock { state -> Bool in
        if let data { state.received.append(data) }
        return state.received.count > DirectHTTP.maxResponseBytes
      }
      if tooLong || error != nil {
        finish(nil)
      } else if isComplete {
        finish(state.withLock { $0.received })
      } else {
        receive()
      }
    }
  }

  /// Отдаёт результат ровно один раз: что раньше — ответ, ошибка или таймаут.
  func finish(_ value: Data?) {
    let waiting = state.withLock { state -> CheckedContinuation<Data?, Never>? in
      let continuation = state.continuation
      state.continuation = nil
      return continuation
    }
    waiting?.resume(returning: value)
  }
}
