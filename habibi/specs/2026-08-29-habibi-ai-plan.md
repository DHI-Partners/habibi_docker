# ИИ-модуль habibi — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** дать тенантам habibi чат-ботов на движке Directus, выдаваемых через `saas_bridge`, с изоляцией данных между тенантами.

**Architecture:** движок `habibi_ai_engine` (Directus 12 + Postgres 18 + расширение `ai`) — один на инсталляцию, наружу только админка. Frappe-приложение `habibi_ai` ставится тенанту, даёт desk-страницу чата и серверный прокси в движок. Браузер тенанта в Directus не ходит; `tenant` подставляет сервер из `frappe.local.site`.

**Tech Stack:** Directus 12.3.1, Postgres 18, TypeScript (@directus/extensions-sdk 18), Frappe v16 / Python 3.11, Docker Compose, Traefik v3.6, GitHub Actions на `ubuntu-24.04-arm`.

**Spec:** `habibi/specs/2026-08-29-habibi-ai-design.md`

## Global Constraints

* Платформа образов — `linux/arm64`, задаётся явно. Прод-сервер Ampere (aarch64).
* Каждый новый Traefik-роутер обязан иметь `priority=100`. `SITES_RULE` — это `HostRegexp`, он матчит любой поддомен первого уровня и без приоритета перехватывает трафик.
* `tenant` берётся только из `frappe.local.site`. Из тела запроса, параметров и заголовков — никогда.
* Токен движка живёт в `common_site_config.json`. В браузер, в git и в образ не попадает.
* Directus 12, Postgres 18, Frappe v16 (`FRAPPE_BRANCH=version-16`).
* Имена фиксированы: репозитории `habibi_ai_engine` и `habibi_ai`, образ `ghcr.io/dhi-partners/habibi-ai-engine`, compose-сервисы `ai-engine` и `ai-db`, поддомены `ai.habibi-erp.com` и `portainer.habibi-erp.com`.
* Комментарии в конфигах — на русском, как в остальных файлах `habibi/`.

## Структура файлов

**В `habibi_docker` (этот репозиторий):**

| Файл | Ответственность |
| --- | --- |
| `habibi/overrides/compose.portainer.yaml` | Portainer + Traefik-роутер |
| `habibi/overrides/compose.ai.yaml` | `ai-engine` + `ai-db` + Traefik-роутер |
| `habibi/apps.json` | добавляется строка `habibi_ai` |
| `habibi/prod.example.env` | новые переменные с комментариями |

**Новый репозиторий `habibi_ai_engine`:**

| Файл | Ответственность |
| --- | --- |
| `extensions/ai/` | расширение, перенесённое с arabic |
| `schema/snapshot.yaml` | схема пяти коллекций |
| `Containerfile` | Directus 12 + вшитое расширение |
| `.github/workflows/image.yml` | сборка arm64, публикация в GHCR |

**Новый репозиторий `habibi_ai` (Frappe-приложение):**

| Файл | Ответственность |
| --- | --- |
| `habibi_ai/engine.py` | HTTP-клиент движка и построение фильтров. Не импортирует `frappe` — тестируется в отрыве |
| `habibi_ai/api.py` | whitelisted-методы, единственное место, где берётся `frappe.local.site` |
| `habibi_ai/tests/test_engine.py` | unit-тесты фильтрации по тенанту |
| `habibi_ai/page/ai_chat/` | desk-страница |

Разделение `engine.py` / `api.py` умышленное: логика изоляции тенантов должна быть покрыта быстрыми тестами без поднятия сайта Frappe.

---

### Task 1: Portainer

Первым, потому что он ни от чего не зависит и заодно проверяет связку «новый сервис + Traefik + priority» до того, как от неё будет зависеть движок.

**Files:**
- Create: `habibi/overrides/compose.portainer.yaml`
- Modify: `habibi/prod.example.env`

**Interfaces:**
- Produces: рабочий шаблон Traefik-лейблов для задачи 4.

- [ ] **Step 1: Написать override**

```yaml
# Portainer — веб-панель управления контейнерами этого хоста.
#
# priority=100 обязателен: SITES_RULE в compose.https.yaml — это HostRegexp,
# матчащий любой поддомен первого уровня. Без приоритета Traefik сравнивает
# роутеры по длине правила, регулярка длиннее простого Host(...), и запрос
# на portainer.<домен> ушёл бы в nginx Frappe. См. compose.distrib.yaml.
#
# tls.domains не нужен: wildcard *.<домен> уже заказан роутером frontend-http.
#
# БЕЗОПАСНОСТЬ. Доступ к /var/run/docker.sock равносилен root на хосте.
# Неинициализированный Portainer отдаёт создание администратора любому, кто
# первым открыл страницу, поэтому первый вход делается сразу после запуска.
#
# Подключать в COMPOSE_FILE после habibi/overrides/compose.wildcard-tls.yaml.

services:
  portainer:
    image: portainer/portainer-ce:2.34.1
    restart: ${RESTART_POLICY:-unless-stopped}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    labels:
      - traefik.enable=true
      - traefik.http.routers.portainer-http.rule=Host(`portainer.${BASE_DOMAIN:?BASE_DOMAIN not set}`)
      - traefik.http.routers.portainer-http.entrypoints=websecure
      - traefik.http.routers.portainer-http.tls.certresolver=main-resolver
      - traefik.http.routers.portainer-http.priority=100
      - traefik.http.services.portainer.loadbalancer.server.port=9000

volumes:
  portainer_data:
```

- [ ] **Step 2: Проверить, что compose разбирает файл**

Run:
```bash
docker compose -f compose.yaml -f overrides/compose.https.yaml \
  -f habibi/overrides/compose.wildcard-tls.yaml \
  -f habibi/overrides/compose.portainer.yaml config --services
```
Expected: в списке есть `portainer`. Ошибка `BASE_DOMAIN not set` означает, что проверку надо запускать с рабочим `.env`.

- [ ] **Step 3: Дописать переменные в `habibi/prod.example.env`**

Ничего нового не требуется — `BASE_DOMAIN` и `RESTART_POLICY` уже есть. Добавить в файл комментарий о том, что подключение Portainer — это добавление `habibi/overrides/compose.portainer.yaml` в `COMPOSE_FILE`.

- [ ] **Step 4: Коммит**

```bash
git add habibi/overrides/compose.portainer.yaml habibi/prod.example.env
git commit -m "feat(compose): панель Portainer за Traefik"
```

- [ ] **Step 5: Развернуть на сервере**

```bash
ssh habibi
cd ~/habibi_docker && git pull
# добавить :habibi/overrides/compose.portainer.yaml в конец COMPOSE_FILE в .env
docker compose up -d portainer
```

- [ ] **Step 6: Проверить и сразу завести администратора**

Run: `curl -s -o /dev/null -w '%{http_code}\n' https://portainer.habibi-erp.com/`
Expected: `200`. Затем немедленно открыть страницу в браузере и создать администратора — до этого момента панель открыта любому.

---

### Task 2: Репозиторий habibi_ai_engine и перенос расширения

**Files:**
- Create: `habibi_ai_engine/extensions/ai/**` (перенос из `arabic.best/arabic_compose/extensions/ai`)
- Create: `habibi_ai_engine/README.md`, `.gitignore`

**Interfaces:**
- Produces: собранное расширение в `extensions/ai/dist/{api.js,app.js}` для задачи 3.

- [ ] **Step 1: Согласовать создание репозитория**

Создание репозитория в организации — действие наружу. Спросить владельца, затем:

```bash
gh repo create DHI-Partners/habibi_ai_engine --private
```

- [ ] **Step 2: Скопировать расширение без артефактов**

```bash
mkdir -p habibi_ai_engine/extensions
rsync -a --exclude node_modules --exclude dist \
  "/Users/fsa/Projects/arabic.best/arabic_compose/extensions/ai/" \
  habibi_ai_engine/extensions/ai/
```

- [ ] **Step 3: Убрать секреты из `package.json`**

В `extensions/ai/package.json` скрипт `generate-types` содержит логин и пароль от `admin.arabic.best` открытым текстом. Заменить на чтение из окружения:

```json
"generate-types": "directus-typescript-gen --host \"$DIRECTUS_HOST\" --email \"$DIRECTUS_EMAIL\" --password \"$DIRECTUS_PASSWORD\" --outFile ./src/types/directus-schema.ts"
```

- [ ] **Step 4: Обновить SDK и host под Directus 12**

Расширение собрано под `@directus/extensions-sdk` 17.0.4 и объявляет `"host": "^10.10.0"`.
Целевой образ — Directus 12.3.1, актуальный SDK — 18.0.4: две мажорные версии разницы,
поэтому шаг обязателен, а не «на всякий случай».

```bash
cd extensions/ai
npm install -D @directus/extensions-sdk@18
```

В `package.json` поднять `directus:extension.host` до `^12.0.0`. Затем собрать и поднять
локально:

```bash
cd extensions/ai && npm install && npm run build
docker run --rm -e KEY=k -e SECRET=s -e DB_CLIENT=sqlite3 -e DB_FILENAME=/tmp/d.db \
  -e ADMIN_EMAIL=a@b.c -e ADMIN_PASSWORD=pass \
  -v "$PWD/../..:/directus/extensions/ai:ro" -p 8055:8055 directus/directus:12
```
Expected: сборка проходит и в логах старта расширение `ai` загружено без предупреждения о несовместимости. Если endpoint не собирается из-за расхождений в API расширений — зафиксировать образ на `directus/directus:11` и вынести обновление в отдельную задачу, о чём сообщить владельцу.

- [ ] **Step 5: Коммит**

```bash
git add -A && git commit -m "feat: расширение ai, перенесено с arabic без секретов в package.json"
```

---

### Task 3: Образ движка и CI

**Files:**
- Create: `habibi_ai_engine/Containerfile`
- Create: `habibi_ai_engine/.github/workflows/image.yml`

**Interfaces:**
- Consumes: `extensions/ai/dist/*` из задачи 2.
- Produces: образ `ghcr.io/dhi-partners/habibi-ai-engine:<tag>` под `linux/arm64` для задачи 4.

- [ ] **Step 1: Написать Containerfile**

```dockerfile
# Directus 12 с вшитым расширением ai.
#
# Расширение именно вшивается, а не монтируется томом, как на arabic:
# на habibi деплой идёт по версионному тегу образа, и откат — это правка
# одной строки в .env. Том с dist на сервере не версионируется никак.

FROM node:22-alpine AS build
WORKDIR /src
COPY extensions/ai/package*.json ./
RUN npm ci
COPY extensions/ai/ ./
RUN npm run build

FROM directus/directus:12.3.1
USER root
COPY --from=build --chown=node:node /src/package.json /directus/extensions/ai/package.json
COPY --from=build --chown=node:node /src/dist /directus/extensions/ai/dist
USER node
```

- [ ] **Step 2: Собрать локально и убедиться, что расширение видно**

Run:
```bash
docker build --platform linux/arm64 -t habibi-ai-engine:test .
docker run --rm -e KEY=k -e SECRET=s -e DB_CLIENT=sqlite3 -e DB_FILENAME=/tmp/d.db \
  -e ADMIN_EMAIL=a@b.c -e ADMIN_PASSWORD=pass habibi-ai-engine:test 2>&1 | head -40
```
Expected: в логах загрузки расширений присутствует `ai`.

- [ ] **Step 3: Написать workflow**

```yaml
name: Engine image

# Нативный ARM-раннер: прод-сервер Ampere (aarch64). На ubuntu-latest (x86)
# собрался бы amd64, и docker на сервере отказался бы его запускать.
# Платформа задаётся явно, чтобы смена раннера не поменяла её молча.

on:
  push:
    branches: [main]
    tags: ['v*']
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-24.04-arm
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Resolve image name
        run: |
          owner=$(echo "${{ github.repository_owner }}" | tr '[:upper:]' '[:lower:]')
          echo "IMAGE=ghcr.io/${owner}/habibi-ai-engine" >> "$GITHUB_ENV"

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Release image tag
        id: reltag
        env:
          REF_NAME: ${{ github.ref_name }}
        run: |
          if [ "${{ github.ref_type }}" = "tag" ]; then
            echo "image_tag=${{ env.IMAGE }}:${REF_NAME}" >> "$GITHUB_OUTPUT"
          else
            echo "image_tag=" >> "$GITHUB_OUTPUT"
          fi

      - uses: docker/build-push-action@v6
        with:
          context: .
          file: Containerfile
          push: true
          platforms: linux/arm64
          tags: |
            ${{ env.IMAGE }}:12
            ${{ steps.reltag.outputs.image_tag }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

Имя тега передаётся через `env`, а не подставляется в `run:` — имя git-тега может содержать shell-метасимволы. Это тот же фикс, что был сделан в `habibi-image.yml` коммитом `fccb7fa`.

- [ ] **Step 4: Запушить и проверить сборку**

```bash
git add Containerfile .github/workflows/image.yml
git commit -m "feat(ci): сборка образа движка под arm64"
git push -u origin main
gh run watch
```
Expected: сборка зелёная, пакет виден в `gh api /orgs/DHI-Partners/packages?package_type=container`.

- [ ] **Step 5: Поставить релизный тег**

```bash
git tag v0.1.0 && git push --tags
```

---

### Task 4: Движок на сервере

**Files:**
- Create: `habibi/overrides/compose.ai.yaml`
- Modify: `habibi/prod.example.env`

**Interfaces:**
- Consumes: образ из задачи 3.
- Produces: `http://ai-engine:8055` внутри сети проекта, админка на `ai.habibi-erp.com`.

- [ ] **Step 1: Написать override**

```yaml
# Движок ИИ-модуля: Directus с расширением ai и своя база Postgres.
#
# Своя БД, а не общая MariaDB стека: Directus поддерживает Postgres, схема
# модуля к схемам сайтов Frappe отношения не имеет, и общий сервер БД связал
# бы их циклами восстановления из бэкапа.
#
# Наружу публикуется только админка — тенанты сюда не ходят, их запросы
# идут через backend Frappe по внутренней сети (habibi_ai.engine).
#
# priority=100 обязателен, см. шапку compose.distrib.yaml.
#
# networks не задаём: сервис попадает в дефолтную сеть проекта, где Traefik
# находит его по лейблам, а backend достаёт по DNS-имени ai-engine.

services:
  ai-engine:
    image: ${AI_ENGINE_IMAGE:-ghcr.io/dhi-partners/habibi-ai-engine}:${AI_ENGINE_TAG:?AI_ENGINE_TAG not set}
    pull_policy: ${PULL_POLICY:-always}
    restart: ${RESTART_POLICY:-unless-stopped}
    depends_on:
      ai-db:
        condition: service_healthy
    environment:
      KEY: ${DIRECTUS_KEY:?DIRECTUS_KEY not set}
      SECRET: ${DIRECTUS_SECRET:?DIRECTUS_SECRET not set}
      ADMIN_EMAIL: ${DIRECTUS_ADMIN_EMAIL:?DIRECTUS_ADMIN_EMAIL not set}
      ADMIN_PASSWORD: ${DIRECTUS_ADMIN_PASSWORD:?DIRECTUS_ADMIN_PASSWORD not set}
      PUBLIC_URL: https://ai.${BASE_DOMAIN:?BASE_DOMAIN not set}
      DB_CLIENT: pg
      DB_HOST: ai-db
      DB_PORT: "5432"
      DB_DATABASE: ${AI_DB_NAME:-habibi_ai}
      DB_USER: ${AI_DB_USER:-habibi_ai}
      DB_PASSWORD: ${AI_DB_PASSWORD:?AI_DB_PASSWORD not set}
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
    volumes:
      - ai_uploads:/directus/uploads
    labels:
      - traefik.enable=true
      - traefik.http.routers.ai-http.rule=Host(`ai.${BASE_DOMAIN}`)
      - traefik.http.routers.ai-http.entrypoints=websecure
      - traefik.http.routers.ai-http.tls.certresolver=main-resolver
      - traefik.http.routers.ai-http.priority=100
      - traefik.http.services.ai.loadbalancer.server.port=8055

  ai-db:
    image: postgres:18-alpine
    restart: ${RESTART_POLICY:-unless-stopped}
    environment:
      POSTGRES_DB: ${AI_DB_NAME:-habibi_ai}
      POSTGRES_USER: ${AI_DB_USER:-habibi_ai}
      POSTGRES_PASSWORD: ${AI_DB_PASSWORD:?AI_DB_PASSWORD not set}
    volumes:
      - ai_db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "${AI_DB_USER:-habibi_ai}", "-d", "${AI_DB_NAME:-habibi_ai}"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  ai_uploads:
  ai_db_data:
```

- [ ] **Step 2: Дописать переменные в `habibi/prod.example.env`**

```
# --- ИИ-модуль (habibi/overrides/compose.ai.yaml) ---
AI_ENGINE_IMAGE=ghcr.io/dhi-partners/habibi-ai-engine
AI_ENGINE_TAG=v0.1.0
# KEY и SECRET: openssl rand -hex 32. Смена SECRET разлогинивает всех.
DIRECTUS_KEY=
DIRECTUS_SECRET=
DIRECTUS_ADMIN_EMAIL=
DIRECTUS_ADMIN_PASSWORD=
AI_DB_NAME=habibi_ai
AI_DB_USER=habibi_ai
AI_DB_PASSWORD=
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
```

- [ ] **Step 3: Проверить конфиг локально**

Run: `docker compose config --services | grep ai-`
Expected: `ai-engine` и `ai-db`.

- [ ] **Step 4: Коммит и выкат**

```bash
git add habibi/overrides/compose.ai.yaml habibi/prod.example.env
git commit -m "feat(compose): движок ИИ-модуля (Directus + Postgres)"
```

На сервере: заполнить новые переменные в `.env`, добавить файл в `COMPOSE_FILE`, `docker compose up -d ai-db ai-engine`.

- [ ] **Step 5: Проверить оба пути**

Run:
```bash
curl -s -o /dev/null -w 'снаружи: %{http_code}\n' https://ai.habibi-erp.com/server/health
docker compose exec -T backend curl -s -o /dev/null -w 'изнутри: %{http_code}\n' http://ai-engine:8055/server/health
```
Expected: `200` в обеих строках. Первая проверяет Traefik и приоритет, вторая — что backend Frappe достаёт движок по внутреннему имени.

---

### Task 5: Схема коллекций

**Files:**
- Create: `habibi_ai_engine/schema/snapshot.yaml`
- Create: `habibi_ai_engine/schema/README.md`

**Interfaces:**
- Produces: пять коллекций с полем `tenant` — контракт для задач 6 и 7.

- [ ] **Step 1: Снять снапшот с arabic**

```bash
ssh arabic 'cd ~/arabic_compose && docker compose exec -T directus npx directus schema snapshot --yes /tmp/s.yaml && docker compose exec -T directus cat /tmp/s.yaml' > /tmp/arabic-schema.yaml
```

- [ ] **Step 2: Оставить только коллекции модуля**

Из снапшота удалить всё, кроме `ai_bots`, `ai_prompts`, `chatbot_scenarios`, `customer_chats`, `chat_messages` и относящихся к ним связей. Убрать поле `customer_chats.user_mongo_id` — это рудимент интеграции с MongoDB другой админки.

- [ ] **Step 3: Добавить поля тенантности**

В каждую из пяти коллекций — поле `tenant` (`type: string`, интерфейс `input`). В `customer_chats` и `chat_messages` — `nullable: false`; в `ai_bots`, `ai_prompts`, `chatbot_scenarios` — nullable, где `null` означает «общий для всех тенантов». В `customer_chats` добавить `external_user` (`type: string`, nullable): пользователи живут в Frappe, а не в Directus, поэтому `user_id` остаётся пустым.

- [ ] **Step 4: Применить на движок**

```bash
scp habibi_ai_engine/schema/snapshot.yaml habibi:/tmp/
ssh habibi 'cd ~/habibi_docker && docker compose cp /tmp/snapshot.yaml ai-engine:/tmp/s.yaml && docker compose exec -T ai-engine npx directus schema apply --yes /tmp/s.yaml'
```

- [ ] **Step 5: Проверить, что схема встала**

Run: `ssh habibi 'cd ~/habibi_docker && docker compose exec -T ai-db psql -U habibi_ai -d habibi_ai -c "\dt"'`
Expected: в списке таблиц есть все пять, и `\d chat_messages` показывает колонку `tenant NOT NULL`.

- [ ] **Step 6: Завести сервисную роль и токен**

В админке `ai.habibi-erp.com` создать роль `service-frappe` с доступом только к пяти коллекциям модуля, пользователя с этой ролью и статический токен. Токен записать — он понадобится в задаче 7 и больше нигде не хранится.

- [ ] **Step 7: Коммит**

```bash
git add schema/ && git commit -m "feat(schema): пять коллекций модуля с полем tenant"
```

---

### Task 6: Клиент движка с изоляцией тенантов

Ядро безопасности модуля. Пишется по TDD и тестируется без поднятия сайта Frappe: `engine.py` не импортирует `frappe`.

**Files:**
- Create: `habibi_ai/habibi_ai/engine.py`
- Test: `habibi_ai/habibi_ai/tests/test_engine.py`

**Interfaces:**
- Produces: `scoped_filter(tenant, extra=None, allow_shared=False) -> dict` и `EngineClient(url, token, tenant)` с методами `list_bots()`, `list_chats(external_user)`, `get_chat(chat_id)`, `send_message(chat_id, message, bot_id=None)` — используются в задаче 7.

- [ ] **Step 1: Согласовать создание репозитория и завести приложение**

```bash
gh repo create DHI-Partners/habibi_ai --private
```
Затем в devcontainer (Часть 1 `habibi/dev-setup.md`): `bench new-app habibi_ai`. Через `compose.appmount.yaml` новое приложение подключить нельзя — монтирование не создаёт ни записи в `sites/apps.txt`, ни `.pth`, ни ассетов; это прямо оговорено в шапке того файла.

- [ ] **Step 2: Написать падающие тесты**

```python
import unittest

from habibi_ai.engine import scoped_filter


class TestScopedFilter(unittest.TestCase):
    def test_приватные_данные_видны_только_своему_тенанту(self):
        self.assertEqual(
            scoped_filter("naqwa.habibi-erp.com"),
            {"tenant": {"_eq": "naqwa.habibi-erp.com"}},
        )

    def test_общие_записи_доступны_когда_разрешены(self):
        self.assertEqual(
            scoped_filter("naqwa.habibi-erp.com", allow_shared=True),
            {
                "_or": [
                    {"tenant": {"_eq": "naqwa.habibi-erp.com"}},
                    {"tenant": {"_null": True}},
                ]
            },
        )

    def test_дополнительный_фильтр_соединяется_через_and(self):
        self.assertEqual(
            scoped_filter("a.example.com", extra={"bot_id": {"_eq": 3}}),
            {
                "_and": [
                    {"tenant": {"_eq": "a.example.com"}},
                    {"bot_id": {"_eq": 3}},
                ]
            },
        )

    def test_пустой_тенант_отвергается(self):
        # Пустая строка дала бы фильтр, под который не попадает ничего,
        # но ошибку конфигурации лучше увидеть сразу, а не как пустой список.
        for value in ("", None):
            with self.assertRaises(ValueError):
                scoped_filter(value)
```

- [ ] **Step 3: Запустить и убедиться, что тесты падают**

Run: `python -m unittest habibi_ai.tests.test_engine -v`
Expected: FAIL — `ImportError: cannot import name 'scoped_filter'`.

- [ ] **Step 4: Реализовать минимально**

```python
"""Клиент движка ИИ. Не импортирует frappe: изоляция тенантов должна быть
покрыта быстрыми тестами без поднятия сайта."""

import requests

TIMEOUT = 60


def scoped_filter(tenant, extra=None, allow_shared=False):
    """Фильтр Directus, ограничивающий выборку одним тенантом.

    Единственное место, где строится это условие. Отдельный фильтр в каждом
    методе означал бы, что про один из них однажды забудут, а цена такой
    забывчивости — чужая переписка в ответе.
    """
    if not tenant:
        raise ValueError("tenant обязателен")

    own = {"tenant": {"_eq": tenant}}
    base = {"_or": [own, {"tenant": {"_null": True}}]} if allow_shared else own

    if extra:
        return {"_and": [base, extra]}
    return base


class EngineClient:
    def __init__(self, url, token, tenant):
        if not tenant:
            raise ValueError("tenant обязателен")
        self.url = url.rstrip("/")
        self.tenant = tenant
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {token}"

    def _items(self, collection, params):
        response = self.session.get(
            f"{self.url}/items/{collection}", params=params, timeout=TIMEOUT
        )
        response.raise_for_status()
        return response.json().get("data", [])
```

- [ ] **Step 5: Запустить тесты**

Run: `python -m unittest habibi_ai.tests.test_engine -v`
Expected: PASS, 4 теста.

- [ ] **Step 6: Коммит**

```bash
git add habibi_ai/engine.py habibi_ai/tests/test_engine.py
git commit -m "feat: фильтр изоляции тенантов и клиент движка"
```

- [ ] **Step 7: Написать падающий тест на проверку принадлежности чата**

```python
import unittest
from unittest.mock import Mock

from habibi_ai.engine import EngineClient, ChatNotFound


class TestChatOwnership(unittest.TestCase):
    def setUp(self):
        self.client = EngineClient("http://ai-engine:8055", "t", "a.example.com")
        self.client._items = Mock(return_value=[])

    def test_чужой_чат_не_отдаётся(self):
        # Движок вернул пустой список: фильтр по тенанту не пропустил чат.
        with self.assertRaises(ChatNotFound):
            self.client.get_chat(42)

    def test_запрос_чата_всегда_ограничен_тенантом(self):
        self.client._items = Mock(return_value=[{"id": 42}])
        self.client.get_chat(42)
        params = self.client._items.call_args.args[1]
        self.assertIn("a.example.com", str(params["filter"]))
```

- [ ] **Step 8: Убедиться, что падает, затем реализовать**

Run: `python -m unittest habibi_ai.tests.test_engine -v` → FAIL (`ChatNotFound` не определён).

```python
class ChatNotFound(Exception):
    """Чат не существует либо принадлежит другому тенанту.

    Один и тот же класс на оба случая намеренно: разные ошибки позволили бы
    перебором номеров узнать, какие чаты существуют у соседей.
    """


# в EngineClient:
    def get_chat(self, chat_id):
        chats = self._items(
            "customer_chats",
            {
                "filter": scoped_filter(self.tenant, {"id": {"_eq": chat_id}}),
                "fields": "*",
                "limit": 1,
            },
        )
        if not chats:
            raise ChatNotFound(chat_id)
        return chats[0]
```

- [ ] **Step 9: Тесты зелёные, коммит**

Run: `python -m unittest habibi_ai.tests.test_engine -v`
Expected: PASS, 6 тестов.

```bash
git commit -am "feat: чужой чат неотличим от несуществующего"
```

- [ ] **Step 10: Дописать остальные методы тем же циклом**

`list_bots()` (с `allow_shared=True`), `list_chats(external_user)`, `send_message(chat_id, message, bot_id=None)`. Последний вызывает `POST {url}/ai-process-message` и перед этим обязан выполнить `get_chat(chat_id)` — иначе номер чужого чата уйдёт в движок в обход фильтра. На каждый метод — сначала тест, потом код.

---

### Task 7: Whitelisted-методы

**Files:**
- Create: `habibi_ai/habibi_ai/api.py`
- Modify: `habibi_ai/habibi_ai/hooks.py`

**Interfaces:**
- Consumes: `EngineClient`, `ChatNotFound` из задачи 6.
- Produces: `habibi_ai.api.{list_bots,list_chats,get_chat,send_message}` для задачи 8.

- [ ] **Step 1: Написать api.py**

```python
"""Единственное место, где берётся имя сайта. Ни один параметр запроса на
tenant не влияет: клиент не может назваться чужим тенантом."""

import frappe

from habibi_ai.engine import ChatNotFound, EngineClient


def get_client():
    url = frappe.conf.get("habibi_ai_engine_url")
    token = frappe.conf.get("habibi_ai_engine_token")
    if not url or not token:
        frappe.throw(
            "Движок ИИ не настроен: habibi_ai_engine_url и habibi_ai_engine_token "
            "задаются в common_site_config.json"
        )
    return EngineClient(url, token, frappe.local.site)


@frappe.whitelist()
def list_bots():
    return get_client().list_bots()


@frappe.whitelist()
def get_chat(chat_id):
    try:
        return get_client().get_chat(int(chat_id))
    except ChatNotFound:
        frappe.throw("Чат не найден", frappe.DoesNotExistError)


@frappe.whitelist()
def send_message(chat_id, message, bot_id=None):
    try:
        return get_client().send_message(int(chat_id), message, bot_id)
    except ChatNotFound:
        frappe.throw("Чат не найден", frappe.DoesNotExistError)
```

`@frappe.whitelist()` без `allow_guest=True` — методы доступны только аутентифицированным пользователям сайта.

- [ ] **Step 2: Прописать конфиг на dev-сайте**

```bash
bench --site <dev-сайт> set-config -g habibi_ai_engine_url http://ai-engine:8055
bench --site <dev-сайт> set-config -g habibi_ai_engine_token '<токен из задачи 5>'
```
Флаг `-g` пишет в `common_site_config.json` — файл на бенче, недоступный тенанту. Это тот же приём, которым `saas_bridge` хранит лимит мест.

- [ ] **Step 3: Проверить вызовом**

Run: `bench --site <dev-сайт> execute habibi_ai.api.list_bots`
Expected: список ботов (на пустой базе — `[]`), без исключений.

- [ ] **Step 4: Проверить, что тенант не подделывается**

Run: `bench --site <dev-сайт> execute habibi_ai.api.get_chat --kwargs "{'chat_id': 999999}"`
Expected: `DoesNotExistError`, а не данные и не 500.

- [ ] **Step 5: Коммит**

```bash
git add habibi_ai/api.py && git commit -m "feat: whitelisted-методы модуля"
```

---

### Task 8: Страница чата и выдача тенанту

**Files:**
- Create: `habibi_ai/habibi_ai/page/ai_chat/{ai_chat.json,ai_chat.js}`
- Modify: `habibi/apps.json` (в habibi_docker)

- [ ] **Step 1: Создать страницу**

```bash
bench --site <dev-сайт> --app habibi_ai new-page ai_chat
```
Страница обращается только к методам из задачи 7 через `frappe.call`. Ассеты правятся в dev-окружении: в production-образе нет node и yarn, правки в `.js` там не подхватываются.

- [ ] **Step 2: Проверить в браузере**

Открыть `/app/ai-chat` на dev-сайте: список ботов грузится, сообщение отправляется, ответ приходит.

- [ ] **Step 3: Добавить приложение в сборку**

В `habibi/apps.json` дописать:

```json
{
  "url": "https://github.com/DHI-Partners/habibi_ai",
  "branch": "main"
}
```

Приватный репозиторий: в CI `apps.json` берётся из секрета `APPS_JSON` с токеном — публичный файл в git токенов не содержит.

- [ ] **Step 4: Собрать образ и выкатить**

```bash
git commit -am "feat(apps): подключить habibi_ai" && git push
git tag v1.1.0 && git push --tags
```
Тег ставится на коммит, затрагивающий `habibi/apps.json` — фильтр `paths` в `habibi-image.yml` действует и на пуш тега, иначе выката не будет.

- [ ] **Step 5: Выдать модуль тенанту**

На `admin.habibi-erp.com` → `/app/site-manager` → Site apps → выбрать сайт → установить `habibi_ai`.

- [ ] **Step 6: Сбросить кеш сайта**

Run: `ssh habibi 'cd ~/habibi_docker && docker compose exec -T backend bench --site <тенант> clear-cache'`

Обязательный шаг: Frappe держит разрешённые хуки в redis, и сайт, закешировавший их до установки модуля, продолжит работать так, будто модуля нет. В README `saas_bridge` это названо единственной ошибкой здесь, которая выглядит в точности как успех.

- [ ] **Step 7: Приёмка**

Открыть `/app/ai-chat` на сайте тенанта — страница есть и работает. Открыть на сайте без модуля — страницы нет. В админке движка у созданного чата поле `tenant` равно имени первого сайта.
