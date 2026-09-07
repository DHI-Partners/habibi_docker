#!/usr/bin/env bash
# Локальная среда ИИ-модуля целиком.
#
#   ./habibi/dev.sh init   — разовая подготовка: девконтейнер, бенч, сайт
#   ./habibi/dev.sh up     — поднять всё
#   ./habibi/dev.sh down   — погасить
#   ./habibi/dev.sh logs   — логи процесса
#   ./habibi/dev.sh check  — диагностика цепочки браузер-бенч-движок-БД по звеньям
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

# Порт SSH-туннеля к прод-базе. Значение задаёт и владеет им
# ../habibi_ai_engine/dev.sh (TUNNEL_PORT там же) — здесь только читаем,
# чтобы cmd_check могла проверить туннель, не трогая чужой скрипт.
TUNNEL_PORT=15432

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

# Инцидент 2026-09-07: туннель к прод-базе тихо умер, а с ним не умер ни один
# видимый человеку слой. Движок отвечал 500 с текстом Directus "An unexpected
# error occurred", habibi_ai добросовестно ретранслировал это на экран, и
# ни интерфейс, ни сообщение движка не указывали на причину — та нашлась
# только в `docker compose logs` как ECONNREFUSED к туннелю. cmd_check
# проверяет всю цепочку браузер -> бенч -> habibi_ai -> движок -> туннель ->
# прод-БД звено за звеном и на каждом обрыве говорит, что запустить.
#
# ok()/bad() только печатают и копят $failed — они не решают, идти ли
# дальше: каждая проверка ниже обёрнута в свой if. Голая команда с ожидаемо
# ненулевым кодом под set -e уронила бы весь check на первом же FAIL, а смысл
# команды — показать все звенья разом, а не остановиться на первом обрыве.
cmd_check() {
  local failed=0

  ok()  { echo "OK   $1"; }
  bad() {
    echo "FAIL $1"
    [ -n "${2:-}" ] && echo "     чинить: $2"
    failed=1
  }

  # 1. Контейнеры девконтейнера — без них дальнейшие проверки бессмысленны.
  # Сравниваем полный список сервисов из compose с реально запущенными, а не
  # просто "хоть что-то поднято": частично упавший devcontainer (например,
  # умер redis) даёт обманчиво зелёную картину, если проверять только факт
  # существования процессов.
  local want have missing
  want=$($DC config --services 2>/dev/null || true)
  have=$($DC ps --status running --services 2>/dev/null || true)
  missing=$(comm -23 <(sort <<<"$want") <(sort <<<"$have") 2>/dev/null | tr '\n' ' ')
  missing=${missing% }
  if [ -z "$want" ]; then
    bad "девконтейнер: .devcontainer не поднят или не инициализирован" "./habibi/dev.sh init && ./habibi/dev.sh up"
  elif [ -n "$missing" ]; then
    bad "девконтейнер: не подняты: $missing" "./habibi/dev.sh up"
  else
    ok "девконтейнер: контейнеры подняты"
  fi

  # 2. Движок жив и отвечает по HTTP. /server/health у Directus закрыт
  # настройками по умолчанию и всегда отвечает 403 — это не признак поломки,
  # см. habibi/specs/2026-09-07-habibi-ai-frontend-plan.md. Живость проверяем
  # /server/ping, который не трогает базу и падает только если сам процесс
  # движка не поднялся.
  local code
  if ! code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:8055/server/ping 2>/dev/null); then
    code=""
  fi
  if [ "$code" = "200" ]; then
    ok "движок: /server/ping -> 200"
  else
    bad "движок: /server/ping -> ${code:-нет ответа}" "(cd ../habibi_ai_engine && ./dev.sh up)"
  fi

  # 3. Туннель реально пробрасывает трафик. Ровно это и сломалось в инциденте:
  # процесс ssh мог остаться в списке (или не остаться вовсе), а форвард —
  # не работать. Проверки "процесс существует" или "порт открыт" здесь
  # недостаточно: TCP-хендшейк на мёртвом форварде иногда проходит, трафик
  # дальше него — нет. Поэтому шлём настоящий байт протокола Postgres
  # (SSLRequest) в порт туннеля и ждём ответ 'S'/'N' от реальной базы на
  # другом конце.
  if tunnel_probe; then
    ok "туннель 127.0.0.1:$TUNNEL_PORT: пробрасывает трафик"
  else
    bad "туннель 127.0.0.1:$TUNNEL_PORT: не отвечает" "(cd ../habibi_ai_engine && ./dev.sh up)"
  fi

  # 4. Движок реально достаёт данные из БД через туннель, а не просто жив.
  # /server/ping ничего не говорит о базе; /server/info — говорит: он читает
  # запись из directus_settings (ServerService.serverInfo -> SettingsService.
  # readSingleton), то есть требует настоящего запроса к Postgres, и доступен
  # без токена. Именно так и выглядела авария: /server/ping отвечал бы 200,
  # а любой запрос с обращением к базе — 500 с текстом Directus "An
  # unexpected error occurred".
  if ! code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8055/server/info 2>/dev/null); then
    code=""
  fi
  if [ "$code" = "200" ]; then
    ok "движок -> база: /server/info -> 200"
  else
    bad "движок -> база: /server/info -> ${code:-нет ответа} (звено 2 и 3 зелёные, а это красное — именно так выглядела авария 2026-09-07)" \
        "(cd ../habibi_ai_engine && ./dev.sh up); если не помогло — docker compose -f ../habibi_ai_engine/compose.dev.yaml logs ai-engine"
  fi

  # 5. Бенч отвечает на :8000.
  if ! code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:8000/api/method/ping 2>/dev/null); then
    code=""
  fi
  if [ "$code" = "200" ]; then
    ok "бенч: /api/method/ping -> 200"
  else
    bad "бенч: /api/method/ping -> ${code:-нет ответа}" "./habibi/dev.sh up"
  fi

  # 6. Конфиг бенча указывает на движок. Значения лежат в common_site_config.
  # json — сам set-config -g пишет туда же (см. подсказку в cmd_init).
  # Токен никогда не печатаем — только факт, что ключ присутствует.
  local url_line url token_ok=0 token_msg="не задан"
  if url_line=$(in_bench "grep habibi_ai_engine_url /workspace/$BENCH/sites/common_site_config.json" 2>/dev/null); then
    url=$(awk -F'"' '{print $4}' <<<"$url_line")
  else
    url=""
  fi
  if in_bench "grep -q habibi_ai_engine_token /workspace/$BENCH/sites/common_site_config.json" 2>/dev/null; then
    token_ok=1
    token_msg=задан
  fi
  if [ -n "$url" ] && [ "$token_ok" = 1 ]; then
    ok "конфиг бенча: habibi_ai_engine_url=$url, токен задан"
  else
    bad "конфиг бенча: url=${url:-не задан}, токен $token_msg" \
        "$DC exec -T frappe bash -lc 'cd /workspace/$BENCH && bench --site $SITE set-config -g habibi_ai_engine_url http://host.docker.internal:8055 && bench --site $SITE set-config -g habibi_ai_engine_token <токен>'"
  fi

  # 7. Vite отвечает на :5173.
  if ! code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:5173/ui 2>/dev/null); then
    code=""
  fi
  if [ "$code" = "200" ]; then
    ok "vite: /ui -> 200"
  else
    bad "vite: /ui -> ${code:-нет ответа}" "./habibi/dev.sh up"
  fi

  [ "$failed" = 0 ]
}

# Живость ssh-процесса ничего не говорит о том, ходит ли трафик — это и есть
# суть проверки 3 в cmd_check. Шлём Postgres SSLRequest (8 байт: длина=8,
# код=80877103) в порт туннеля и ждём один байт ответа ('S' — есть TLS,
# 'N' — нет): ответ приходит только если байты реально дошли до Postgres на
# другом конце и вернулись, то есть форвард жив, а не просто открыт локально.
#
# Ошибки exec/read у /dev/tcp попадают в стандартный вывод bash, а не в код
# возврата команды сам по себе — группируем каждый шаг в {...}, чтобы
# 2>/dev/null подавлял их, и на любой неудаче явно возвращаем 1, не давая
# set -e увидеть непроверенный ненулевой код.
tunnel_probe() {
  local byte
  { exec 3<>"/dev/tcp/127.0.0.1/$TUNNEL_PORT"; } 2>/dev/null || return 1
  { printf '\x00\x00\x00\x08\x04\xd2\x16\x2f' >&3; } 2>/dev/null || { exec 3<&- 3>&- 2>/dev/null; return 1; }
  if read -r -t 3 -n 1 -u 3 byte 2>/dev/null; then
    exec 3<&- 3>&- 2>/dev/null
    [ -n "$byte" ]
  else
    exec 3<&- 3>&- 2>/dev/null
    return 1
  fi
}

case "${1:-up}" in
  init)   cmd_init ;;
  up)     cmd_up ;;
  down)   cmd_down ;;
  logs)   shift; cmd_logs "$@" ;;
  check)  cmd_check ;;
  *)      echo "usage: $0 {init|up|down|logs|check}" >&2; exit 1 ;;
esac
