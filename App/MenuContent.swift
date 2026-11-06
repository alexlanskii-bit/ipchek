import AppKit
import SwiftUI

/// Меню значка. На этапе 1 — заглушка: версия, состояние уведомлений и тестовое уведомление.
struct MenuContent: View {
  let model: AppModel

  var body: some View {
    Text("IPCHEK \(AppInfo.version)")
    Text("Слежение за сетью появится на этапе 2")

    Divider()

    Text(model.notificationStatusText)
    Button("Отправить тестовое уведомление") {
      model.sendTestNotification()
    }
    .disabled(model.isSendingTest)
    if let result = model.lastTestResult {
      Text(result)
    }

    Divider()

    Button("Выйти из IPCHEK") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}
