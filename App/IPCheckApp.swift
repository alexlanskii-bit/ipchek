import IPCheckCore
import SwiftUI

@main
struct IPCheckApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    MenuBarExtra {
      StatusPanel(model: model)
    } label: {
      let snapshot = model.connectivity.snapshot
      // Описание — для VoiceOver: «IPCHEK: Интернет работает».
      MenuBarIcon(
        state: snapshot.state,
        description: "IPCHEK: " + StatusText.title(snapshot, now: .now))
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(model: model)
    }
  }
}
