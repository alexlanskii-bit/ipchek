import IPCheckCore
import SwiftUI

@main
struct IPCheckApp: App {
  /// Модель живёт в делегате: ему нужны те же данные для окна по клику в Dock и для сна Mac.
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate

  var body: some Scene {
    // Копия, которая сразу выйдет (автозапуск выключен человеком), значок не показывает.
    MenuBarExtra(isInserted: menuBarIconShown) {
      StatusPanel(model: delegate.model)
    } label: {
      let snapshot = delegate.model.connectivity.snapshot
      // Описание — для VoiceOver: «IPCHEK: Интернет работает».
      MenuBarIcon(
        state: snapshot.state,
        description: "IPCHEK: " + StatusText.title(snapshot, now: .now))
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(model: delegate.model)
    }
  }

  private var menuBarIconShown: Binding<Bool> {
    let quits = delegate.model.autostart.launchPlan == .quit
    return Binding(get: { !quits }, set: { _ in })
  }
}
