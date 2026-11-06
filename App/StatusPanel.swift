import AppKit
import IPCheckCore
import SwiftUI

/// Панель по клику на значок. Набросок согласован 2026-11-06 (этап 2).
struct StatusPanel: View {
  let model: AppModel
  @Environment(\.openSettings) private var openSettings
  /// Какой адрес только что скопирован — на 1,5 с вместо него показываем «Скопировано».
  @State private var copied: String?

  var body: some View {
    let snapshot = model.connectivity.snapshot
    VStack(alignment: .leading, spacing: 10) {
      header(snapshot)
      Divider()
      connectionRows(snapshot)
      Divider()
      addressRows
      Divider()
      notificationsRow
      Divider()
      buttons
    }
    .font(.callout)
    .padding(14)
    .frame(width: 320)
    .onAppear { model.refreshNotificationStatus() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in model.refreshNotificationStatus()
    }
  }

  // MARK: - Части панели

  private func header(_ snapshot: ConnectivitySnapshot) -> some View {
    // Раз в секунду обновляет «N с назад» и длительность разрыва.
    TimelineView(.periodic(from: .now, by: 1)) { context in
      HStack(alignment: .center, spacing: 10) {
        MenuBarIcon(
          state: snapshot.state, description: StatusText.title(snapshot, now: context.date)
        )
        .scaleEffect(1.5)
        .frame(width: 30)
        .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(StatusText.title(snapshot, now: context.date))
            .font(.headline)
          Text(StatusText.reason(snapshot, now: context.date))
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

  private func connectionRows(_ snapshot: ConnectivitySnapshot) -> some View {
    let russia = StatusText.region(snapshot.russia)
    let abroad = StatusText.region(snapshot.abroad)
    return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
      row("Подключение", StatusText.linkName(snapshot.link))
      row("Задержка", snapshot.latencyMs.map { "\($0) мс" } ?? "—")
      row("Потери за минуту", snapshot.lossPercent.map { "\($0) %" } ?? "—")
      row(
        StatusText.regionLabel("Россия", snapshot.russia), russia.text,
        color: Color(nsColor: russia.color))
      row(
        StatusText.regionLabel("Зарубеж", snapshot.abroad), abroad.text,
        color: Color(nsColor: abroad.color))
    }
  }

  /// Адреса и VPN. По клику адрес копируется.
  private var addressRows: some View {
    let address = model.addresses.snapshot
    let failed = model.addresses.failedRegions
    return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
      copyableRow("Локальный IP", address.localIP)
      copyableRow(
        "Внешний IP · Россия", address.russiaIP, failed: failed.contains(.russia),
        country: address.russiaCountry)
      copyableRow(
        "Внешний IP · зарубеж", address.abroadIP, failed: failed.contains(.abroad),
        country: address.abroadCountry)
      row(
        "VPN", address.vpnInterface.map { "включён · \($0)" } ?? "выключен",
        color: address.vpnInterface == nil ? Color.secondary : Color.green)
      let server = StatusText.server(
        model.server.snapshot, configured: model.server.isConfigured, now: .now)
      row("Сервер NL", server.text, color: Color(nsColor: server.color))
    }
    .task(id: copied) {
      guard copied != nil else { return }
      do {
        try await Task.sleep(for: .seconds(1.5))
      } catch {
        return  // панель закрыли — подсказка больше не нужна
      }
      copied = nil
    }
  }

  private func copyableRow(
    _ label: String, _ value: String?, failed: Bool = false, country: CountryVerdict? = nil
  ) -> some View {
    GridRow(alignment: .firstTextBaseline) {
      Text(label)
        .foregroundStyle(.secondary)
      VStack(alignment: .trailing, spacing: 1) {
        if let value {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = label
          } label: {
            Text(copied == label ? "Скопировано" : value)
              .monospacedDigit()
          }
          .buttonStyle(.plain)
          .help("Нажмите, чтобы скопировать")
          .accessibilityLabel("\(label): \(value). Нажмите, чтобы скопировать")
        } else {
          Text(failed ? "не удалось узнать" : "—")
            .foregroundStyle(.secondary)
        }
        // Страна определяется заново по самому IP двумя службами (решение владельца).
        if value != nil, let country {
          if let line = CountryText.line(country) {
            Text(line.text)
              .font(.caption)
              .foregroundStyle(Color(nsColor: line.color))
              .help(line.help)
          } else {
            Text("страна — узнаю…")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
        }
      }
      .gridColumnAlignment(.trailing)
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }

  private var notificationsRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Label(
          model.notificationStatusText,
          systemImage: model.notificationsAllowed ? "bell" : "bell.slash"
        )
        .foregroundStyle(.secondary)
        Spacer()
        if model.notificationsAllowed {
          Button("Тест") { model.sendTestNotification() }
            .disabled(model.isSendingTest)
            .help("Отправить тестовое уведомление")
        } else {
          Button("Открыть настройки") { model.openNotificationSettings() }
            .help("Системные настройки → Уведомления")
        }
      }
      if let result = model.lastTestResult {
        Text(result)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var buttons: some View {
    HStack {
      Button("История") {}
        .disabled(true)
        .help("Появится на этапе 6")
      Button("Настройки") {
        // Приложение без значка в Dock: сначала выводим его вперёд, иначе окно откроется позади.
        NSApp.activate()
        openSettings()
      }
      Spacer()
      Button("Выйти") { NSApplication.shared.terminate(nil) }
        .keyboardShortcut("q")
    }
  }

  private func row(_ label: String, _ value: String, color: Color? = nil, muted: Bool = false)
    -> some View
  {
    GridRow {
      Text(label)
        .foregroundStyle(muted ? .tertiary : .secondary)
      Text(value)
        .foregroundStyle(muted ? AnyShapeStyle(.tertiary) : AnyShapeStyle(color ?? .primary))
        .gridColumnAlignment(.trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }
}
