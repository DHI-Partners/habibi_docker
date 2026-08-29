# ИИ-модуль для habibi: движок на Directus + модуль для ERPNext

Дата: 2026-08-29
Статус: черновик, на согласовании

## 1. Задача

Дать тенантам habibi ИИ-функциональность (чат-боты со сценариями и промптами) так,
чтобы модуль:

* выдавался конкретному тенанту, как `habibi_ui`, — то есть управлялся через `saas_bridge`;
* был один на всю инсталляцию, с общей отладкой, аналитикой и правкой ботов в одном месте;
* переиспользовался на других инсталляциях в будущем без переписывания.

Исходник логики — расширение `extensions/ai` из проекта `arabic.best/arabic_compose`
(`Yegoroot/madinah_compose`). Оттуда берётся код и структура коллекций. Сам arabic
не трогаем.

## 2. Ключевое решение: две сущности, а не одна

Механизм выдачи модулей тенанту в habibi — это `installed_apps` сайта Frappe, которым
управляет `saas_bridge`. Directus в `installed_apps` попасть не может. Поэтому ИИ-модуль
разделяется на две части:

| Слой | Что | Тенантность |
| --- | --- | --- |
| **Движок** `habibi_ai_engine` | Directus 11 + Postgres 18 + расширение `ai` | один на инсталляцию |
| **Модуль** `habibi_ai` | Frappe-приложение: страница чата в desk + серверный прокси | ставится выборочно |

Выдача тенанту отдельной разработки не требует: `habibi_ai` добавляется строкой в
`habibi/apps.json`, попадает в образ, появляется в `saas_bridge.api.get_available_apps`
и дальше ставится мышкой на `/app/site-manager`.

## 3. Как ходят запросы

    браузер тенанта
      -> https://<тенант>.habibi-erp.com  (сессия Frappe, существующая авторизация)
      -> whitelisted-метод habibi_ai      (подставляет tenant, скрывает токен)
      -> http://ai-engine:8055            (внутренняя сеть docker)
      -> расширение ai -> ItemsService -> Postgres

Браузер в Directus не ходит никогда. Наружу Directus публикуется только админкой на
`ai.habibi-erp.com` — для владельца инсталляции, не для тенантов.

### Почему не напрямую из браузера

На arabic мобильное приложение ходит в Directus с админским токеном, зашитым в бандл
(`DIRECTUS_ADMIN_TOKEN` в `config.ts`, ставится в заголовок по умолчанию). Бандл
распаковывается, то есть админ-доступ к Directus фактически публичный. В мультитенантной
установке это означало бы, что тенант А читает переписку тенанта Б, и никакая изоляция
«внутри БД модуля» этому не мешает — идентификатор тенанта приходил бы с клиента.

Этот паттерн в habibi не переносится. Тот же вывод уже зафиксирован в `saas_bridge`:
лимит мест пишется в `site_config.json` на бенче именно потому, что System Manager
тенанта может править любой документ и права в своей БД, но не файл на бенче.

## 4. Изоляция тенантов

В коллекции добавляется поле `tenant` (string) со значением, равным имени сайта Frappe
(`naqwa.habibi-erp.com`):

| Коллекция | `tenant` | Смысл |
| --- | --- | --- |
| `ai_bots` | nullable | `null` — общий бот, доступен всем тенантам |
| `ai_prompts` | nullable | наследует область видимости бота |
| `chatbot_scenarios` | nullable | то же |
| `customer_chats` | обязательно | переписка всегда принадлежит тенанту |
| `chat_messages` | обязательно | то же |

Значение проставляет прокси-слой из `frappe.local.site`. Клиент на него влиять не может:
в теле запроса поля `tenant` нет вообще, оно не читается из параметров.

Фильтрация делается в одном месте — helper в `habibi_ai`, через который проходит каждый
вызов движка. Отдельный фильтр в каждом методе — путь к утечке между тенантами, когда
про один из методов забудут.

## 5. Компоненты

### 5.1 Репозиторий `habibi_ai_engine`

```
extensions/ai/          перенесённое расширение (bundle, endpoint ai-process-message)
schema/snapshot.yaml    снапшот схемы Directus, применяется при развёртывании
Containerfile           FROM directus/directus:11 + собранное расширение
.github/workflows/      сборка arm64, публикация в ghcr.io/dhi-partners/habibi-ai-engine
README.md
```

Расширение вшивается в образ, а не монтируется томом, как на arabic. Причина — на habibi
уже налажен деплой по тегу `v*`: образ с версионным тегом означает воспроизводимый откат
правкой одной строки в `.env`, тогда как том с `dist` на сервере не версионируется никак.

Сборка — на `ubuntu-24.04-arm`, платформа `linux/arm64` явно: прод-сервер Ampere
(aarch64), и образ обязан быть под ту же архитектуру. Основание — комментарий в
`.github/workflows/habibi-image.yml`, там эта ошибка уже была поймана.

Схема версионируется снапшотом (`directus schema snapshot` / `schema apply`). Без этого
развернуть модуль второй раз можно только воссоздав пять коллекций руками — сейчас на
arabic они существуют только в проде, каталог `snapshots/` пуст.

### 5.2 Схема коллекций

Снята с живого arabic 2026-08-29.

**`ai_bots`** — `id` (int, pk), `name`, `person_key`, `global_system_prompt` (text),
`avatar` (m2o `directus_files`), **`tenant`** (nullable).

**`ai_prompts`** — `id`, `bot_id` (m2o `ai_bots`), `name`, `system_prompt` (text),
**`tenant`**.

**`chatbot_scenarios`** — `id`, `bot_id`, `scenario_key`, `initial_prompt` (m2o
`ai_prompts`), `description`, `flow_id` (m2o `directus_flows`), `metadata` (json),
`max_history_messages` (int, по умолчанию 15), `max_stack` (int, по умолчанию 10),
**`tenant`**.

**`customer_chats`** — `id`, `user_id` (m2o `directus_users`), `bot_id`,
`current_scenario`, `scenario_stack` (json), `metadata` (json), `messages` (o2m
`chat_messages`), **`tenant`** (обязательно), **`external_user`** (string).

**`chat_messages`** — `id`, `chat_id` (m2o `customer_chats`), `role` (`user` |
`assistant`), `content` (text), `sort` (int), `date_created`, `date_updated`,
**`tenant`** (обязательно).

Два отличия от arabic:

* `user_mongo_id` не переносится — это рудимент интеграции с MongoDB другой админки;
* добавляется `external_user` — email пользователя Frappe. Пользователи живут в Frappe,
  а не в Directus, поэтому `user_id` остаётся nullable и в этой схеме не используется.

### 5.3 Frappe-приложение `habibi_ai`

Whitelisted-методы (`System User`, не `Guest`):

| Метод | Назначение |
| --- | --- |
| `habibi_ai.api.list_bots()` | боты тенанта плюс общие (`tenant is null`) |
| `habibi_ai.api.list_chats()` | чаты тенанта, свои для текущего пользователя |
| `habibi_ai.api.get_chat(chat_id)` | чат с историей сообщений |
| `habibi_ai.api.send_message(chat_id, message, bot_id=None)` | проксирует в `POST /ai-process-message` |

Каждый метод проходит через общий helper, который добавляет фильтр по `tenant` и
подставляет `external_user`. `chat_id` перед использованием проверяется на
принадлежность тенанту — иначе номер чужого чата даёт доступ к чужой переписке.

Интерфейс МВП — desk-страница со списком ботов, списком чатов и лентой сообщений.
Обращается только к методам выше.

Конфигурация в `common_site_config.json` (недоступен тенанту):

```json
{
  "habibi_ai_engine_url": "http://ai-engine:8055",
  "habibi_ai_engine_token": "<статический токен сервисной роли Directus>"
}
```

Сервисная роль в Directus имеет доступ только к пяти коллекциям модуля.

### 5.4 `habibi/overrides/compose.ai.yaml`

По образцу `compose.distrib.yaml`. Сервисы `ai-engine` (Directus) и `ai-db` (Postgres 18),
тома `ai_db_data`, `ai_uploads`.

Traefik: ``Host(`ai.${BASE_DOMAIN}`)``, `entrypoints=websecure`,
`certresolver=main-resolver`, `loadbalancer.server.port=8055` и обязательно
**`priority=100`**. Без приоритета запрос уходит во frontend Frappe: `SITES_RULE` —
это `HostRegexp`, он матчит любой поддомен первого уровня, а Traefik без явного
приоритета сравнивает роутеры по длине правила, и регулярка длиннее. Ровно эта ловушка
описана в шапке `compose.distrib.yaml`.

`tls.domains` не нужен — wildcard `*.habibi-erp.com` уже заказан роутером `frontend-http`,
и Traefik подбирает сертификат по SNI.

`networks` не задаём: сервис попадает в дефолтную сеть проекта, где Traefik находит его
по лейблам, а backend Frappe достаёт по DNS-имени `ai-engine`.

Новые переменные `.env`: `AI_ENGINE_IMAGE`, `AI_ENGINE_TAG`, `DIRECTUS_KEY`,
`DIRECTUS_SECRET`, `DIRECTUS_ADMIN_EMAIL`, `DIRECTUS_ADMIN_PASSWORD`, `AI_DB_PASSWORD`,
`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`.

### 5.5 Portainer

Отдельный `habibi/overrides/compose.portainer.yaml`, независим от остального.
`portainer/portainer-ce`, том `portainer_data`, сокет `/var/run/docker.sock`,
Traefik-лейблы с `priority=100`, порт 9000.

Доступ к docker-сокету равносилен root на хосте, поэтому панель закрывается basic-auth
middleware Traefik поверх собственной авторизации Portainer, а первый вход (создание
администратора) делается сразу после запуска: неинициализированный Portainer отдаёт
создание админа любому, кто открыл страницу.

## 6. Порядок развёртывания

1. Portainer — независим, проверяет заодно схему «новый сервис + Traefik + priority».
2. `habibi_ai_engine`: перенос расширения, снапшот схемы, Containerfile, CI, образ в GHCR.
3. `compose.ai.yaml`, поднять движок, применить схему, завести сервисную роль и токен.
4. `habibi_ai`: прокси-методы и страница, строка в `habibi/apps.json`, пересборка образа.
5. Поставить модуль тестовому тенанту через Site Manager, сбросить кеш сайта.

Шаг 5 про кеш обязателен: Frappe держит разрешённые хуки в redis, и сайт, закешировавший
их до появления модуля, продолжит работать по-старому. В README `saas_bridge` это
названо единственной ошибкой, которая выглядит в точности как успех.

## 7. Вне рамок

Делается отдельными циклами после того, как ядро заработает:

* `extensions/base` — авторизация по телефону (SMSAero) и push-уведомления;
* перенос стартовых данных (боты, промпты, сценарии) с arabic;
* мобильное приложение / внешний фронтенд;
* стриминг ответа LLM — в МВП обычный запрос-ответ;
* отдельные роли и токены Directus на каждого тенанта — в МВП изоляция в прокси-слое.

## 8. Риски

**Версия host у расширения.** В `package.json` указан `"host": "^10.10.0"`, а образ —
Directus 11. На arabic работает, но при переносе это проверяется первым делом.

**Изоляция держится на прокси-слое.** Сервисный токен один на все тенанты, поэтому
ошибка в фильтре по `tenant` означает утечку переписки между клиентами. Отсюда единый
helper вместо фильтра в каждом методе и тесты именно на попытку достать чужой чат.

**Секреты в исходниках.** В `extensions/ai/package.json` (скрипт `generate-types`) и в
`package.json` мобильного приложения лежат логин и пароль от `admin.arabic.best` открытым
текстом. В новый репозиторий не переносятся; учётные данные на arabic подлежат смене
независимо от этой работы.

**Диск.** На сервере свободно 23 ГБ из 45. Postgres и тома Directus добавляются к
существующим MariaDB и бэкапам Frappe — за ростом надо следить.
