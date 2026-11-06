import AppKit
import IPCheckCore
import SwiftUI

/// Окно настроек. Набросок согласован с владельцем (этап 3).
/// Пределы значений — из `MonitorSettings.allowedRange`, те же, что проверяются при запуске.
struct SettingsView: View {
  let model: AppModel

  var body: some View {
    Form {
      Section("Проверка связи") {
        stepper(
          "Проверять каждые", \.checkIntervalSeconds, key: .checkIntervalSeconds, step: 1,
          unit: "с")
        stepper(
          "Разрыв — неудач подряд", \.failuresBeforeOutage, key: .failuresBeforeOutage, step: 1,
          unit: nil)
      }

      Section("Связь нестабильна, если") {
        stepper(
          "Задержка больше", \.unstableLatencyMs, key: .unstableLatencyMs, step: 50, unit: "мс")
        stepper(
          "Потери за минуту больше", \.unstableLossPercent, key: .unstableLossPercent, step: 1,
          unit: "%")
      }

      Section("Уведомления") {
        Toggle("Со звуком", isOn: binding(\.soundEnabled))
        Toggle(isOn: binding(\.notifyUnstable)) {
          Text("О нестабильной связи")
          Text("Не чаще раза в 10 минут")
        }
        HStack {
          Text(model.notificationStatusText)
            .foregroundStyle(.secondary)
          Spacer()
          if model.notificationsAllowed {
            Button("Тест") { model.sendTestNotification() }
              .disabled(model.isSendingTest)
          } else {
            Button("Открыть настройки macOS") { model.openNotificationSettings() }
          }
        }
      }

      Section("Появится позже") {
        LabeledContent("Сервер в Нидерландах", value: "этап 5")
        LabeledContent("Хранение истории", value: "этап 6")
        LabeledContent("Запуск при входе", value: "этап 7")
      }
      .foregroundStyle(.tertiary)

      HStack {
        Spacer()
        Button("Вернуть значения по умолчанию") { model.resetSettings() }
          .disabled(model.settings == .defaults)
      }
    }
    .formStyle(.grouped)
    .frame(width: 440)
    .onAppear { model.refreshNotificationStatus() }
  }

  // MARK: - Помощники

  private func binding<Value>(_ keyPath: WritableKeyPath<MonitorSettings, Value>) -> Binding<Value>
  {
    Binding(
      get: { model.settings[keyPath: keyPath] },
      set: { model.change(keyPath, to: $0) })
  }

  private func stepper(
    _ title: String, _ keyPath: WritableKeyPath<MonitorSettings, Int>, key: SettingsKey,
    step: Int, unit: String?
  ) -> some View {
    let value = model.settings[keyPath: keyPath]
    let range = MonitorSettings.allowedRange(for: key) ?? value...value
    return Stepper(value: binding(keyPath), in: range, step: step) {
      LabeledContent(title, value: unit.map { "\(value) \($0)" } ?? "\(value)")
    }
  }
}
