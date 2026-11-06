import Foundation
import IPCheckCore
import Synchronization
import Testing

@Suite("Запросы к службам: подпись и предел размера ответа")
struct HTTPLimitsTests {
  @Test("Подпись запросов обычная и не выдаёт приложение")
  func userAgentIsGeneric() {
    #expect(ClientIdentity.userAgent == "Mozilla/5.0")
    #expect(!ClientIdentity.userAgent.localizedCaseInsensitiveContains("IPCHEK"))
    let request = DirectHTTP.request(for: "https://icanhazip.com").map {
      String(decoding: $0, as: UTF8.self)
    }
    #expect(request?.contains("\r\nUser-Agent: \(ClientIdentity.userAgent)\r\n") == true)
  }

  @Test("Ответ не длиннее предела — читается целиком")
  func withinLimit() async throws {
    #expect(try await BoundedBody.read(stream([]), limit: 4) == Data())
    #expect(try await BoundedBody.read(stream([1, 2, 3]), limit: 4) == Data([1, 2, 3]))
    #expect(try await BoundedBody.read(stream([1, 2, 3, 4]), limit: 4) == Data([1, 2, 3, 4]))
  }

  @Test("Ответ длиннее предела — отбрасывается, не дочитывая")
  func overLimit() async throws {
    let counter = ByteCounter()
    let endless = AsyncStream<UInt8>(unfolding: { counter.next() })

    #expect(try await BoundedBody.read(stream([1, 2, 3, 4, 5]), limit: 4) == nil)
    #expect(try await BoundedBody.read(endless, limit: 16) == nil)
    #expect(counter.count == 17)
  }
}

private func stream(_ bytes: [UInt8]) -> AsyncStream<UInt8> {
  AsyncStream { continuation in
    for byte in bytes { continuation.yield(byte) }
    continuation.finish()
  }
}

/// Бесконечный ответ: считает, сколько байт у него попросили.
private final class ByteCounter: Sendable {
  private let asked = Mutex(0)

  var count: Int { asked.withLock { $0 } }

  func next() -> UInt8? {
    asked.withLock { $0 += 1 }
    return 0
  }
}
