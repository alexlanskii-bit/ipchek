import AppKit
import IPCheckCore
import SwiftUI

/// Значок в строке меню: цвет и форма по состоянию связи.
///
/// Строка меню перекрашивает обычные значки в один цвет, поэтому цветной значок собирается
/// как NSImage с `isTemplate = false` (NSImage.SymbolConfiguration, paletteColors, macOS 12+).
struct MenuBarIcon: View {
  let state: ConnectionState
  let description: String

  var body: some View {
    Image(nsImage: Self.image(for: state, description: description))
  }

  private static func image(for state: ConnectionState, description: String) -> NSImage {
    let icon = StatusText.icon(for: state)
    var configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    if let color = icon.color {
      configuration = configuration.applying(.init(paletteColors: [color]))
    }
    guard
      let base = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: description),
      let image = base.withSymbolConfiguration(configuration)
    else {
      return NSImage()
    }
    image.isTemplate = icon.color == nil
    return image
  }
}
