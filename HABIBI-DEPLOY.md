# Habibi ERP — развёртывание

Готовый к развёртыванию конфиг: `git clone` + `docker compose up -d`.
Репозиторий frappe_docker больше не нужно настраивать вручную.

## Как это устроено

Bench собирается **внутри образа**, а не хранится в git. Состав приложений
описан манифестом `apps.json`:

```json
[
  { "url": "https://github.com/DHI-Partners/habibi-erp", "branch": "main" }
]
```

`main` в `habibi-erp` — производственная линия: ERPNext version-16 плюс
брендинг Habibi. Ветка `develop` там осталась от линии v17-dev и для
развёртывания не годится — приложение v17 несовместимо с frappe v16,
на котором собран образ.

`images/layered/Containerfile` монтирует этот файл BuildKit-секретом,
выполняет `bench init --apps_path=...`, собирает ассеты и удаляет `.git` из
каждого приложения. Frappe Framework в манифест не входит — он задаётся
build-args `FRAPPE_PATH` / `FRAPPE_BRANCH`.

Поэтому **исходники frappe и приложений сюда не вендорятся**. Каждое
приложение живёт в своём репозитории со своей историей, а здесь хранится
только ссылка на него. Вендоринг сломал бы `git fetch upstream`,
`bench update`, `bench version` и `bench switch-to-branch` — все они
выполняют git внутри `apps/<app>`.

Файлы этого пакета:

| Файл | Назначение |
| --- | --- |
| `apps.json` | манифест приложений: URL + ветка |
| `habibi.env` | переменные окружения стека |
| `scripts/habibi-build.sh` | локальная сборка образа |
| `.github/workflows/habibi-image.yml` | сборка и пуш в ghcr.io |

`compose.yaml` не менялся — он уже параметризован:

```yaml
image: ${CUSTOM_IMAGE:-frappe/erpnext}:${CUSTOM_TAG:-$ERPNEXT_VERSION}
pull_policy: ${PULL_POLICY:-always}
```

## Разовая настройка репозитория

```sh
# 1. Создайте пустой репозиторий DHI-Partners/habibi-docker на GitHub
# 2. В этом клоне:
git remote rename origin upstream          # frappe/frappe_docker остаётся как upstream
git remote add origin https://github.com/DHI-Partners/habibi-docker.git
git push -u origin main
```

Файлы развёртывания лежат на `main` намеренно: развёртывание начинается с
`git clone`, который забирает ветку по умолчанию. Если держать их на
отдельной ветке, в свежем клоне не окажется ни `apps.json`, ни `habibi.env`.

После первого пуша workflow соберёт и запушит `ghcr.io/dhi-partners/habibi-erp:16`.
Сборка занимает 20–40 минут (полный `bench init` + компиляция ассетов).

Синхронизация с апстримом дальше:

```sh
git fetch upstream && git merge upstream/main
```

Пакет не трогает `compose.yaml`, `images/` и `resources/`, поэтому конфликтов
при слиянии быть не должно.

## Развёртывание

```sh
git clone https://github.com/DHI-Partners/habibi-docker.git
cd habibi-docker

# ⚠️ Обязательно смените DB_PASSWORD и проверьте FRAPPE_SITE_NAME_HEADER
$EDITOR habibi.env

docker compose --env-file habibi.env \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.noproxy.yaml \
  up -d
```

Затем создайте сайт. Имя сайта должно совпадать с `FRAPPE_SITE_NAME_HEADER`
из `habibi.env`:

```sh
docker compose --env-file habibi.env -f compose.yaml exec backend \
  bench new-site \
    --mariadb-user-host-login-scope=% \
    --db-root-password change-me \
    --admin-password change-me \
    --install-app erpnext \
    habibi.localhost
```

**Обратите внимание на `--install-app erpnext`, а не `habibi-erp`.** В
`erpnext/hooks.py` осталось `app_name = "erpnext"` — изменён только
`app_title` на `Habibi ERP`. Имя репозитория и имя приложения различаются
намеренно: так подмена приложения не требует правок конфигурации сайтов.
`pyproject.toml` объявляет `name = "erpnext"`, по нему bench и определяет
имя каталога приложения.

Для production вместо `compose.noproxy.yaml` берите
`overrides/compose.traefik-ssl.yaml` или `compose.nginxproxy-ssl.yaml` —
см. `docs/03-production/`.

## Локальная сборка вместо ghcr.io

Если не нужен registry (или нет прав на пакеты организации):

```sh
./scripts/habibi-build.sh
sed -i 's/^PULL_POLICY=.*/PULL_POLICY=missing/' habibi.env
```

`PULL_POLICY=missing` обязателен, иначе compose попытается тянуть образ из
ghcr.io и не увидит локально собранный.

Скрипт считает `CACHE_BUST` из HEAD и хеша `apps.json`. Без этого Docker
переиспользует кешированный слой `bench init` и **не подтянет новые коммиты
приложений** — это самая частая причина «собрал, а изменений нет».

## Добавление приложения

Допишите его в `apps.json` и запушьте — CI пересоберёт образ:

```json
[
  { "url": "https://github.com/DHI-Partners/habibi-erp",  "branch": "main" },
  { "url": "https://github.com/DHI-Partners/saas_bridge", "branch": "main" }
]
```

Затем установите приложение в существующий сайт:

```sh
docker compose --env-file habibi.env -f compose.yaml exec backend \
  bench --site habibi.localhost install-app saas_bridge
```

### Приватные репозитории

Публичный `apps.json` в git не должен содержать токенов. Положите полный
манифест в секрет репозитория `APPS_JSON`, используя URL вида:

```
https://x-access-token:<PAT>@github.com/DHI-Partners/saas_bridge
```

Workflow подставит секрет вместо файла из репозитория. Токен не попадёт в
слои образа, потому что `apps.json` передаётся `--secret`, а не
`--build-arg` (build-args видны навсегда через `docker image history`).

Для локальной сборки просто держите `apps.json` с токеном не в git.

## Обновление приложения

`apps.json` фиксирует **ветку**, а не коммит, поэтому пуш в `main`
меняет содержимое следующего образа. Чтобы пересборка запускалась
автоматически, добавьте в репозиторий `habibi-erp` workflow, дергающий этот:

```yaml
- run: |
    curl -X POST \
      -H "Authorization: Bearer ${{ secrets.HABIBI_DOCKER_PAT }}" \
      -H "Accept: application/vnd.github+json" \
      https://api.github.com/repos/DHI-Partners/habibi-docker/dispatches \
      -d '{"event_type":"habibi-apps-updated"}'
```

Обновление работающего стека после выхода нового образа:

```sh
docker compose --env-file habibi.env -f compose.yaml pull
docker compose --env-file habibi.env -f compose.yaml up -d
docker compose --env-file habibi.env -f compose.yaml exec backend \
  bench --site habibi.localhost migrate
```

## Локальная разработка

Этот пакет — про развёртывание; образ иммутабельный, правки требуют
пересборки. Для разработки используйте `habibi.override.yml` с `pwd.yml`,
который монтирует рабочую копию в `apps/erpnext`:

```sh
docker compose -f pwd.yml -f habibi.override.yml up -d
```

Правки Python требуют `docker restart <проект>-backend-1`. Если после
пересоздания backend возвращается `502` — перезапустите frontend: nginx
кеширует IP апстрима при старте.
