import SwiftUI

@main
struct IPCheckApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    // Название — подпись значка для VoiceOver. Цвет и форма по состоянию сети — этап 2.
    MenuBarExtra("IPCHEK", systemImage: "network") {
      MenuContent(model: model)
    }
    .menuBarExtraStyle(.menu)
  }
}
