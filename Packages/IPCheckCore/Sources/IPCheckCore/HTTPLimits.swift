import Foundation

/// Как приложение представляется службам IP и стран.
///
/// Обычная подпись вместо «IPCHEK»: запросы напрямую и через VPN не должны выделяться редкой
/// подписью, по которой их легко связать между собой (замечание проверки 2026-11-06).
public enum ClientIdentity {
  public static let userAgent = "Mozilla/5.0"
}

/// Чтение ответа службы с пределом размера: длинный ответ точно не тот, что ждали, и дочитывать
/// его незачем.
public enum BoundedBody {
  /// Содержимое, если в нём не больше `limit` байт; иначе `nil` — чтение обрывается на байте
  /// сверх предела.
  public static func read<Bytes: AsyncSequence>(_ bytes: Bytes, limit: Int) async throws -> Data?
  where Bytes.Element == UInt8 {
    var body = Data()
    for try await byte in bytes {
      body.append(byte)
      if body.count > limit { return nil }
    }
    return body
  }
}
