import AppKit
import IPCheckCore
import SwiftUI

/// Окно настроек. Набросок согласован с владельцем (этап 3).
/// Пределы значений — из `MonitorSettings.allowedRange`, те же, что проверяются при запуске.
struct SettingsView: View {
  let model: AppModel
  /// Адрес сервера сохраняется по кнопке или Return, а не по каждой букве.
  @State private var hostDraft = ""
  @State private var hostError: String?

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

      Section("Сервер в Нидерландах") {
        HStack {
          TextField("Адрес", text: $hostDraft, prompt: Text("IP или имя сервера"))
            .onSubmit(saveHost)
          Button("Сохранить", action: saveHost)
            .disabled(
              hostDraft.trimmingCharacters(in: .whitespacesAndNewlines) == model.settings.serverHost
            )
        }
        if let hostError {
          Text(hostError)
            .font(.caption)
            .foregroundStyle(.red)
        }
        Picker("Проверка", selection: binding(\.serverCheck)) {
          Text("Автоматически: порты 443 и 22").tag(ServerCheckMethod.auto)
          Text("Только мой порт").tag(ServerCheckMethod.port)
        }
        if model.settings.serverCheck == .port {
          TextField("Порт", value: binding(\.serverPort), format: .number.grouping(.never))
        }
        LabeledContent(
          "Сейчас",
          value: StatusText.server(
            model.server.snapshot, configured: model.server.isConfigured, now: .now
          ).text)
        Text(
          "Проверка идёт напрямую через Wi-Fi или кабель, в обход VPN. Адрес хранится только на этом Mac."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Появится позже") {
        LabeledContent("Хранение истории", value: "этап 6")
        LabeledContent("Запуск при входе", value: "этап 7")
      }
      .foregroundStyle(.tertiary)

      HStack {
        Spacer()
        Button("Вернуть значения по умолчанию") { model.resetSettings() }
          .disabled(model.settingsAreDefault)
          .help("Адрес и способ проверки сервера не сбрасываются")
      }
    }
    .formStyle(.grouped)
    .frame(width: 440)
    .onAppear {
      model.refreshNotificationStatus()
      hostDraft = model.settings.serverHost
    }
  }

  // MARK: - Помощники

  private func saveHost() {
    let trimmed = hostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      hostError = nil
      model.change(\.serverHost, to: "")
      return
    }
    guard let normalized = ServerAddress.normalize(trimmed) else {
      hostError =
        "Неверный адрес. Впишите IP (например, 203.0.113.5) или имя сервера (vpn.example.com)."
      return
    }
    hostError = nil
    hostDraft = normalized
    model.change(\.serverHost, to: normalized)
  }

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
