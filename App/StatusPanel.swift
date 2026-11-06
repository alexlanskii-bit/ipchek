import AppKit
import IPCheckCore
import SwiftUI

/// Панель по клику на значок. Набросок согласован 2026-11-06 (этап 2).
struct StatusPanel: View {
  let model: AppModel

  var body: some View {
    let snapshot = model.connectivity.snapshot
    VStack(alignment: .leading, spacing: 10) {
      header(snapshot)
      Divider()
      connectionRows(snapshot)
      Divider()
      futureRows
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

  /// Строки, которые оживут на следующих этапах (решение владельца — показывать серыми).
  private var futureRows: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
      row("Локальный IP", "этап 4", muted: true)
      row("Внешний IP · РФ / зарубеж", "этап 4", muted: true)
      row("VPN", "этап 4", muted: true)
      row("Сервер NL", "этап 5", muted: true)
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
      Button("Настройки") {}
        .disabled(true)
        .help("Появится на этапе 3")
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
