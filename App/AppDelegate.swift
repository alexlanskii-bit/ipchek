import AppKit
import IPCheckCore
import SwiftUI

/// События жизни приложения, которых нет в SwiftUI: повторный запуск (клик по значку в Dock,
/// Spotlight), сон и пробуждение Mac, сигнал завершения.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()
  private let statusWindow = StatusWindowController()
  private var terminationSignal: DispatchSourceSignal?
  private var observers: [NSObjectProtocol] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    let autostart = model.autostart
    Log.launch.notice(
      "Запуск: \(String(describing: autostart.source), privacy: .public), план: \(String(describing: autostart.launchPlan), privacy: .public), файл автозапуска: \(String(describing: autostart.job), privacy: .public)"
    )
    switch autostart.launchPlan {
    case .quit:
      // Запустила macOS, а человек выключил «Запускать при входе». Код выхода 0 — launchd
      // не считает это сбоем.
      Log.launch.notice("Запуск при входе выключен в настройках — выхожу")
      NSApp.terminate(nil)
    case .run(let showWindow):
      handleTerminationSignal()
      observeSleepAndWake()
      model.start()
      if showWindow { statusWindow.show(model: model) }
    }
  }

  /// IPCHEK уже работает, а его снова запустили (значок в Dock, Spotlight, Launchpad):
  /// показываем окно состояния (решение владельца 2026-11-07).
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    Log.launch.notice("Повторный запуск — показываю окно")
    statusWindow.show(model: model)
    return false
  }

  /// `make install` и macOS (выход из системы) закрывают приложение сигналом SIGTERM.
  /// Без обработчика процесс обрывается: задание автозапуска сочло бы это сбоем и запустило
  /// IPCHEK снова, а с этапа 6 терялась бы незаписанная история. С обработчиком — штатный
  /// выход с кодом 0, как по кнопке «Выйти».
  private func handleTerminationSignal() {
    signal(SIGTERM, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    source.setEventHandler {
      MainActor.assumeIsolated {
        Log.launch.notice("Сигнал завершения — выхожу штатно")
        NSApp.terminate(nil)
      }
    }
    source.resume()
    terminationSignal = source
  }

  private func observeSleepAndWake() {
    let center = NSWorkspace.shared.notificationCenter
    observers = [
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.model.systemWillSleep() }
      },
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.model.systemDidWake() }
      },
    ]
  }
}

/// Окно с тем же содержимым, что и панель в строке меню: открывается кликом по значку в Dock.
@MainActor
final class StatusWindowController {
  private var window: NSWindow?

  func show(model: AppModel) {
    let window = self.window ?? makeWindow(model: model)
    self.window = window
    Log.launch.notice("Окно состояния")
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  private func makeWindow(model: AppModel) -> NSWindow {
    let content = NSHostingController(rootView: StatusPanel(model: model))
    let window = NSWindow(contentViewController: content)
    window.title = "IPCHEK"
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    // Сначала размер по содержимому, потом центр: иначе SwiftUI уточняет высоту уже после
    // центрирования, и окно уезжает к верху экрана (замечено 2026-11-07).
    window.setContentSize(content.view.fittingSize)
    window.center()
    return window
  }
}
