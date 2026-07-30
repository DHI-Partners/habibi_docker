#!/usr/bin/env bash
#
# Локальная сборка образа Habibi ERP.
#
# Собирает layered-образ: frappe (по FRAPPE_BRANCH) + все приложения из
# apps.json. Ассеты собираются внутри образа через bench init.
#
# Требуется Docker Engine v23+ (apps.json передаётся BuildKit-секретом,
# чтобы токены приватных репозиториев не попали в слои образа).
#
# После сборки поставьте в habibi.env:
#   PULL_POLICY=missing
# иначе compose попытается тянуть образ из ghcr.io вместо локального.

set -euo pipefail

cd "$(dirname "$0")/.."

FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"
FRAPPE_PATH="${FRAPPE_PATH:-https://github.com/frappe/frappe}"
IMAGE="${IMAGE:-ghcr.io/dhi-partners/habibi-erp}"
TAG="${TAG:-16}"

if [ ! -s apps.json ]; then
  echo "ошибка: apps.json отсутствует или пуст" >&2
  exit 1
fi

# CACHE_BUST инвалидирует слой bench init. Без него Docker переиспользует
# кеш и НЕ подтянет новые коммиты приложений из apps.json.
CACHE_BUST="${CACHE_BUST:-$(git rev-parse HEAD)-$(md5sum apps.json | cut -d' ' -f1)}"

echo "frappe:  ${FRAPPE_PATH} @ ${FRAPPE_BRANCH}"
echo "образ:   ${IMAGE}:${TAG}"
echo "apps:"
sed 's/^/  /' apps.json

docker build \
  --build-arg="FRAPPE_PATH=${FRAPPE_PATH}" \
  --build-arg="FRAPPE_BRANCH=${FRAPPE_BRANCH}" \
  --build-arg="CACHE_BUST=${CACHE_BUST}" \
  --secret="id=apps_json,src=apps.json" \
  --tag="${IMAGE}:${TAG}" \
  --file=images/layered/Containerfile \
  .

echo
echo "готово: ${IMAGE}:${TAG}"
echo "не забудьте PULL_POLICY=missing в habibi.env"
