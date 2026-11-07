import Foundation
import IPCheckCore
import Testing

@Suite("Кто запустил IPCHEK")
struct LaunchSourceTests {
  @Test("Метка из файла автозапуска — запустила macOS (вход в систему или перезапуск после сбоя)")
  func agent() {
    #expect(LaunchSource(environment: ["IPCHEK_LAUNCHED_BY": "agent"]) == .agent)
  }

  @Test("Без метки или с чужим значением — запустил человек (Dock, Spotlight, Launchpad)")
  func user() {
    #expect(LaunchSource(environment: [:]) == .user)
    #expect(LaunchSource(environment: ["IPCHEK_LAUNCHED_BY": "кто-то"]) == .user)
  }
}

@Suite("Установленная копия")
struct InstalledCopyTests {
  @Test("Рабочая версия в «Программах» — да")
  func installed() {
    #expect(
      Autostart.isInstalledCopy(
        bundlePath: "/Applications/IPCHEK.app", bundleID: "com.lavmoviesstudio.ipchek"))
  }

  @Test(
    "Отладочная версия или копия вне «Программ» — нет: автозапуск только у установленной",
    arguments: [
      ("/Applications/IPCHEK.app", "com.lavmoviesstudio.ipchek.dev"),
      (
        "/Users/me/IPCHEK/build/DerivedData/Build/Products/Release/IPCHEK.app",
        "com.lavmoviesstudio.ipchek"
      ),
      ("/ApplicationsX/IPCHEK.app", "com.lavmoviesstudio.ipchek"),
      ("/Applications/IPCHEK.app", ""),
    ])
  func notInstalled(path: String, bundleID: String) {
    #expect(!Autostart.isInstalledCopy(bundlePath: path, bundleID: bundleID))
  }

  @Test("Без идентификатора — нет")
  func noBundleID() {
    #expect(!Autostart.isInstalledCopy(bundlePath: "/Applications/IPCHEK.app", bundleID: nil))
  }
}

@Suite("Как запускаться")
struct LaunchPlanTests {
  @Test("Запустила macOS, автозапуск включён — работаем, окна нет")
  func agentRuns() {
    #expect(Autostart.plan(source: .agent, launchAtLogin: true) == .run(showWindow: false))
  }

  @Test("Запустила macOS, а человек выключил автозапуск — сразу штатно выходим")
  func agentQuitsWhenOff() {
    #expect(Autostart.plan(source: .agent, launchAtLogin: false) == .quit)
  }

  @Test("Запустил человек — работаем и показываем окно, что бы ни стояло в автозапуске")
  func userRunsWithWindow() {
    #expect(Autostart.plan(source: .user, launchAtLogin: true) == .run(showWindow: true))
    #expect(Autostart.plan(source: .user, launchAtLogin: false) == .run(showWindow: true))
  }
}

@Suite("Подсказка под переключателем автозапуска")
struct AutostartNoticeTests {
  @Test("Отладочная версия — автозапуска нет, что бы ни говорила macOS")
  func devBuild() {
    for job in AutostartJobStatus.allCases {
      #expect(Autostart.notice(isInstalledCopy: false, job: job) == .onlyInstalledCopy)
    }
  }

  @Test("Файла автозапуска нет — подсказать make install")
  func notInstalled() {
    #expect(Autostart.notice(isInstalledCopy: true, job: .notInstalled) == .runMakeInstall)
  }

  @Test("Выключено в Системных настройках — подсказать, где включить")
  func disabledBySystem() {
    #expect(
      Autostart.notice(isInstalledCopy: true, job: .disabledInSystemSettings)
        == .disabledInSystemSettings)
  }

  @Test("Всё на месте — подсказка о том, что выбор действует со следующего входа")
  func enabled() {
    #expect(Autostart.notice(isInstalledCopy: true, job: .enabled) == .appliesAtNextLogin)
  }
}

@Suite("Файл автозапуска")
struct AutostartJobFileTests {
  @Test("Лежит в папке LaunchAgents настоящей домашней папки")
  func path() {
    #expect(
      Autostart.jobPlistPath(home: "/Users/me")
        == "/Users/me/Library/LaunchAgents/com.lavmoviesstudio.ipchek.autostart.plist")
  }

  @Test("Лишняя косая черта в конце домашней папки не ломает путь")
  func trailingSlash() {
    #expect(
      Autostart.jobPlistPath(home: "/Users/me/")
        == "/Users/me/Library/LaunchAgents/com.lavmoviesstudio.ipchek.autostart.plist")
  }
}
