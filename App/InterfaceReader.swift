import Darwin
import IPCheckCore

/// Читает адреса сетевых интерфейсов Mac (системная функция getifaddrs).
/// Решения — какой из них VPN и какой локальный IP — принимает `NetworkAddresses` (покрыто тестами).
enum InterfaceReader {
  static func addresses() -> [InterfaceAddress] {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return [] }
    defer { freeifaddrs(head) }

    var result: [InterfaceAddress] = []
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let entry = pointer.pointee
      guard let socketAddress = entry.ifa_addr else { continue }
      let family = Int32(socketAddress.pointee.sa_family)
      guard family == AF_INET || family == AF_INET6 else { continue }

      let length = socklen_t(
        family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      guard
        getnameinfo(socketAddress, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
          == 0
      else { continue }

      var address = text(host)
      // У IPv6 бывает суффикс зоны «%en0» — для показа он не нужен.
      if let zone = address.firstIndex(of: "%") { address = String(address[..<zone]) }
      result.append(
        InterfaceAddress(
          interface: String(cString: entry.ifa_name), address: address,
          isIPv6: family == AF_INET6))
    }
    return result
  }

  /// Строка из C-буфера. `String(cString: [CChar])` устарел в Swift 6 — по подсказке компилятора
  /// обрезаем завершающий ноль и декодируем как UTF-8.
  private static func text(_ buffer: [CChar]) -> String {
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }
}
