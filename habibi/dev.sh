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

# Команда внутри контейнера бенча, от пользователя frappe.
in_bench() { $DC exec -T frappe bash -lc "$1"; }

need_siblings() {
  local missing=()
  for app in "${APPS[@]}"; do
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
    in_bench "cd /workspace/$BENCH && bench --site $SITE set-config developer_mode 1"
    echo "==> сайт $SITE создан"
  fi

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

case "${1:-up}" in
  init)   cmd_init ;;
  *)      echo "usage: $0 {init}" >&2; exit 1 ;;
esac
