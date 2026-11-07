#!/bin/bash
# Штатно закрывает все запущенные копии приложения с указанным идентификатором и ждёт, пока
# они выйдут. Использование: scripts/stop-app.sh com.lavmoviesstudio.ipchek
#
# Сигнал SIGTERM IPCHEK обрабатывает как «Выйти»: выход с кодом 0, и задание автозапуска
# не принимает его за сбой (docs/DECISIONS.md, решение 38).
# Ищем по идентификатору, а не по пути: копию, которую запустила macOS (автозапуск), launchd
# запускает с коротким путём «Contents/MacOS/IPCHEK», и поиск по полному пути её не находит.
set -euo pipefail

bundle_id="${1:?Укажите идентификатор приложения, например com.lavmoviesstudio.ipchek}"
signalled=""

running_pid() {
  lsappinfo info -only pid -app "$bundle_id" | sed -nE 's/^"pid"=([0-9]+)$/\1/p'
}

for _ in $(seq 50); do
  pid="$(running_pid)"
  if [[ -z "$pid" ]]; then
    exit 0
  fi
  if [[ " $signalled " != *" $pid "* ]]; then
    kill -TERM "$pid"
    signalled="$signalled $pid"
  fi
  sleep 0.2
done

echo "Приложение $bundle_id не закрылось за 10 секунд" >&2
exit 1
