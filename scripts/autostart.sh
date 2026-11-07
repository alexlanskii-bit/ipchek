#!/bin/bash
# Автозапуск рабочей версии IPCHEK через launchd (этап 7, docs/DECISIONS.md — решение 38).
#
#   scripts/autostart.sh stop    — штатно закрыть копию, которую запустила macOS, и снять задание
#                                  (перед заменой приложения в make install)
#   scripts/autostart.sh start   — положить файл задания в ~/Library/LaunchAgents и запустить
#                                  IPCHEK под присмотром macOS (перезапуск после сбоя)
#   scripts/autostart.sh remove  — снять задание и удалить файл (полное удаление IPCHEK)
#
# Файл задания — scripts/autostart.plist. Выключить автозапуск, не удаляя файл, можно
# переключателем в настройках IPCHEK или в Системных настройках → Основные → Объекты входа.
set -euo pipefail

label="com.lavmoviesstudio.ipchek.autostart"
bundle_id="com.lavmoviesstudio.ipchek"
app="/Applications/IPCHEK.app"
template="$(cd "$(dirname "$0")" && pwd)/autostart.plist"
target="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"

is_loaded() {
  launchctl print "$domain/$label" >/dev/null 2>&1
}

is_running() {
  lsappinfo info -only pid -app "$bundle_id" | grep -q '^"pid"='
}

# launchctl bootout посылает SIGTERM и ждёт выхода. IPCHEK выходит штатно, с кодом 0.
stop() {
  if is_loaded; then
    launchctl bootout "$domain/$label"
  fi
}

start() {
  plutil -lint -s "$template"
  mkdir -p "$(dirname "$target")"
  cp "$template" "$target"
  chmod 644 "$target"
  stop
  if ! launchctl bootstrap "$domain" "$target"; then
    echo "macOS не приняла файл автозапуска. Если IPCHEK выключен в Системных настройках →" \
      "Основные → Объекты входа, включите его там." >&2
  fi
  # Если автозапуск выключен в настройках IPCHEK или в Системных настройках, копия под
  # присмотром сразу выходит или не запускается — тогда запускаем обычным способом.
  sleep 3
  if ! is_running; then
    echo "Автозапуск выключен — запускаю IPCHEK без него."
    open "$app"
  fi
}

remove() {
  stop
  rm -f "$target"
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  remove) remove ;;
  *)
    echo "Использование: $0 start|stop|remove" >&2
    exit 2
    ;;
esac
