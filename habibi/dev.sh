#!/usr/bin/env bash
# Локальная среда ИИ-модуля целиком.
#
#   ./habibi/dev.sh init   — разовая подготовка: девконтейнер, бенч, сайт
#   ./habibi/dev.sh up     — поднять всё
#   ./habibi/dev.sh down   — погасить
#   ./habibi/dev.sh logs   — логи процесса
#
# Спек: habibi/specs/2026-09-07-habibi-ai-frontend-design.md
#
# Скрипт знает раскладку каталогов на диске: соседние репозитории ищутся по
# ../ от habibi_docker. Это его единственное допущение о среде.

set -euo pipefail
cd "$(dirname "$0")/.."

SITE=dev.localhost
BENCH=development/frappe-bench
DC="docker compose -f .devcontainer/docker-compose.yml"
APPS=(habibi_ui habibi_ai)
LOGS=.dev-logs

# Соседние репозитории, без которых dev.sh не работает целиком. Шире APPS:
# habibi_ai_engine cmd_up вызывает напрямую (../habibi_ai_engine/dev.sh up),
# но это не Frappe-приложение, и в APPS ему не место — тот список ставит
# приложения в сайт через bench install-app.
SIBLINGS=("${APPS[@]}" habibi_ai_engine)

# Команда внутри контейнера бенча, от пользователя frappe.
in_bench() { $DC exec -T frappe bash -lc "$1"; }

need_siblings() {
  local missing=()
  for app in "${SIBLINGS[@]}"; do
    [ -d "../$app" ] || missing+=("$app")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "нет соседних репозиториев: ${missing[*]}" >&2
    echo "они должны лежать рядом с habibi_docker" >&2
    exit 1
  fi
}

cmd_init() {
  need_siblings

  # .devcontainer в .gitignore и собирается из примера — там же лежат монты
  # соседних репозиториев, см. dev-setup.md.
  if [ ! -d .devcontainer ]; then
    cp -R devcontainer-example .devcontainer
    echo "==> .devcontainer собран из примера"
  fi

  # Копия не перезаписывается: .devcontainer в .gitignore именно чтобы его
  # правили под себя. Но расхождение с примером означает потерянные монты или
  # порты, и молчать об этом нельзя — цена в полчаса на поиск причины.
  if ! diff -q devcontainer-example/docker-compose.yml .devcontainer/docker-compose.yml >/dev/null; then
    echo "!!! .devcontainer/docker-compose.yml разошёлся с devcontainer-example/" >&2
    echo "    свежие монты и порты могут отсутствовать; сверьте: diff devcontainer-example/docker-compose.yml .devcontainer/docker-compose.yml" >&2
  fi

  $DC up -d

  if [ ! -d "$BENCH" ]; then
    in_bench "cd /workspace/development &&
      bench init --skip-redis-config-generation --frappe-branch version-16 frappe-bench"
    in_bench "cd /workspace/$BENCH &&
      bench set-config -g db_host mariadb &&
      bench set-config -g redis_cache redis://redis-cache:6379 &&
      bench set-config -g redis_queue redis://redis-queue:6379 &&
      bench set-config -g redis_socketio redis://redis-queue:6379"
    echo "==> бенч создан"
  fi

  # erpnext ставится клоном: он не наш и правится не здесь.
  in_bench "cd /workspace/$BENCH &&
    [ -d apps/erpnext ] || bench get-app --branch version-16 erpnext"

  # Наши приложения — симлинком на смонтированный репозиторий, а не
  # bench get-app. get-app сделал бы клон внутрь apps/, и ты правил бы копию,
  # а пушил из своего репозитория: два расходящихся каталога одного приложения.
  for app in "${APPS[@]}"; do
    in_bench "cd /workspace/$BENCH &&
      [ -e apps/$app ] || ln -s /workspace/repos/$app apps/$app
      # sites/apps.txt после bench init остаётся БЕЗ завершающего перевода
      # строки, и наивный echo >> склеивает новую запись с предыдущей:
      # 'frappe' + 'habibi_ui' превращаются в 'frappehabibi_ui', и обе записи
      # перестают существовать. Проверено на risk-check в задаче B1.
      [ -s sites/apps.txt ] && [ \"\$(tail -c1 sites/apps.txt)\" != '' ] && echo >> sites/apps.txt
      grep -qx $app sites/apps.txt || echo $app >> sites/apps.txt
      bench pip install -e apps/$app"
  done
  echo "==> приложения подключены"

  # Наличие сайта проверяется файлом, а не разбором `bench list-sites`: та
  # печатает человекочитаемое "Available sites:" и имя с отступом, то есть её
  # вывод — не интерфейс. Проверка по нему молча ломалась бы при любой правке
  # форматирования, а сломавшись — уводила бы init в повторный new-site.
  if ! in_bench "test -f /workspace/$BENCH/sites/$SITE/site_config.json"; then
    in_bench "cd /workspace/$BENCH &&
      bench new-site $SITE --mariadb-user-host-login-scope='%' \
        --db-root-password 123 --admin-password admin \
        --install-app erpnext --install-app habibi_ui --install-app habibi_ai"
    echo "==> сайт $SITE создан"
  fi

  # Существование site_config.json говорит, что new-site стартовал, но не что
  # он доехал: конфиг пишется ДО установки приложений, и они ставятся по
  # одному. Упавшая установка оставила бы сайт без приложения навсегда —
  # проверка выше пропускала бы его молча. Поэтому доустанавливаем
  # недостающее на каждом прогоне.
  #
  # Здесь разбирается вывод команды, хотя выше мы от этого ушли: у списка
  # приложений САЙТА файлового источника истины нет, он живёт в его БД.
  for app in erpnext "${APPS[@]}"; do
    in_bench "cd /workspace/$BENCH &&
      bench --site $SITE list-apps | grep -q \"^$app \" ||
      bench --site $SITE install-app $app"
  done

  # developer_mode и allow_tests говорят одно и то же — это сайт для
  # разработки. Без allow_tests `bench run-tests` отказывается работать, и
  # каждый тестовый шаг следующих фаз падает на пустом месте.
  #
  # Снаружи блока создания сайта, по той же причине, что и default_site рядом:
  # внутри настройка не применилась бы к сайту, заведённому раньше этой правки,
  # и человек чинил бы среду руками. init сходится к нужному состоянию, а не
  # доверяет защите. set-config идемпотентен.
  in_bench "cd /workspace/$BENCH &&
    bench --site $SITE set-config developer_mode 1 &&
    bench --site $SITE set-config allow_tests true"

  # Frappe выбирает сайт по заголовку Host, а браузер и прокси vite шлют
  # Host: localhost. Без этих двух ключей бенч отвечает 404 "localhost does
  # not exist" на любой запрос с хоста, хотя порт опубликован и соединение
  # проходит. Лечить заголовком в прокси нельзя: починился бы только vite,
  # а прямое открытие localhost:8000 в браузере — нет.
  #
  # Снаружи блока создания сайта намеренно: внутри он не выполнился бы у того,
  # чей сайт заведён раньше этой правки, и 404 остался бы навсегда. init должен
  # сходиться к нужному состоянию, а не доверять защите — тот же принцип, по
  # которому выше доустанавливаются приложения. set-config идемпотентен.
  in_bench "cd /workspace/$BENCH &&
    bench set-config -g default_site $SITE &&
    bench set-config -g serve_default_site true"

  cat <<'HINT'

==> дальше:
    1. пропиши адрес и токен движка (см. habibi/specs/2026-09-07-habibi-ai-frontend-design.md, 5.4):
       docker compose -f .devcontainer/docker-compose.yml exec frappe bash -lc \
         "cd /workspace/development/frappe-bench &&
          bench --site dev.localhost set-config -g habibi_ai_engine_url http://host.docker.internal:8055 &&
          bench --site dev.localhost set-config -g habibi_ai_engine_token '<токен>'"
    2. ./habibi/dev.sh up
HINT
}

ENGINE=../habibi_ai_engine
UI=../habibi_ui

# Фоновый процесс с логом и pid-файлом. Вотчер расширения и vite держат
# терминал занятым, а процессов здесь пять — пять окон это ровно то, от чего
# скрипт должен избавлять.
background() {
  local name=$1 dir=$2 cmd=$3
  if [ -f "$LOGS/$name.pid" ] && kill -0 "$(cat "$LOGS/$name.pid")" 2>/dev/null; then
    echo "==> $name уже запущен (pid $(cat "$LOGS/$name.pid"))"
    return
  fi
  mkdir -p "$LOGS"
  (cd "$dir" && exec bash -lc "$cmd") > "$LOGS/$name.log" 2>&1 &
  echo $! > "$LOGS/$name.pid"
  echo "==> $name запущен (pid $!), лог $LOGS/$name.log"
}

stop_background() {
  local name=$1
  [ -f "$LOGS/$name.pid" ] || return 0
  kill "$(cat "$LOGS/$name.pid")" 2>/dev/null || true
  rm -f "$LOGS/$name.pid"
  echo "==> $name остановлен"
}

cmd_up() {
  need_siblings
  [ -d "$BENCH" ] || { echo "бенча нет — сначала ./habibi/dev.sh init" >&2; exit 1; }

  # Движок поднимает свой скрипт: у него своя логика туннеля и сборки .env.dev
  # с сервера, второй копии ей не нужно.
  (cd "$ENGINE" && ./dev.sh up)

  $DC up -d
  background вотчер "$ENGINE/extensions/ai" "npm run dev"
  background бенч "." "$DC exec -T frappe bash -lc 'cd /workspace/$BENCH && bench start'"
  background vite "$UI" "yarn dev"

  cat <<'READY'

==> готово:
    фронт с HMR   http://localhost:5173/ui
    бенч          http://localhost:8000
    админка движка http://localhost:8055
READY
}

cmd_down() {
  stop_background vite
  stop_background бенч
  stop_background вотчер
  $DC down
  (cd "$ENGINE" && ./dev.sh down)
}

cmd_logs() {
  local name=${1:-}
  case "$name" in
    движок) (cd "$ENGINE" && ./dev.sh logs) ;;
    вотчер|бенч|vite) tail -f "$LOGS/$name.log" ;;
    *) echo "usage: $0 logs {движок|вотчер|бенч|vite}" >&2; exit 1 ;;
  esac
}

case "${1:-up}" in
  init)   cmd_init ;;
  up)     cmd_up ;;
  down)   cmd_down ;;
  logs)   shift; cmd_logs "$@" ;;
  *)      echo "usage: $0 {init|up|down|logs}" >&2; exit 1 ;;
esac
