# Ответы ИИ во входящих Telegram — дизайн

Дата: 2026-09-18
Репозитории: `habibi_ai`, `habibi_telegram`, `habibi_docker`

## Цель

Если на канале Telegram включён параметр «Использовать ИИ для ответа»,
входящее сообщение уходит в ИИ-модуль, тот получает ответ от движка и
отправляет его обратно в тот же чат тем же каналом.

Каналы — оба, что есть в `habibi_telegram`:

- **Telegram Bot** — Bot API, апдейты приходят вебхуком мгновенно;
- **Telegram Account** — личный аккаунт по MTProto (Telethon), апдейты
  забираются `updates.getDifference` раз в минуту либо слушателем (§7).

Отвечаем во всех типах чатов, где канал может писать: личные, группы,
супергруппы. В broadcast-каналах, где мы читатель, отправка невозможна
технически — там ответа не будет.

Вне первой версии: распознавание голосовых, кнопка «ИИ вкл/выкл» в консоли
чатов `habibi_ui`, отдельный «пользователь для ИИ» на канале.

## 1. Архитектура

`habibi_ai` знает о Telegram, `habibi_telegram` об ИИ не знает.

- Telegram остаётся самостоятельным модулем, ставится без ИИ.
- ИИ ставится тенанту выборочно, как сейчас; следующий канал (WhatsApp) —
  ещё один адаптер внутри `habibi_ai`.

```
Бот (вебхук) ─────────┐
                      ├─► Telegram Message (Incoming) вставлена
Аккаунт (MTProto) ────┘            │
                        habibi_ai: doc_events after_insert
                                   │  should_reply(...) — без сети
                                   ▼
                        frappe.enqueue(queue="long", enqueue_after_commit=True)
                                   │
                        channels.telegram.reply_job(канал, чат)
                                   │  1. найти/завести чат движка
                                   │  2. loop.run(...)  ← engine.py + tools
                                   │  3. отправить с флагом automated
                                   ▼
                        habibi_telegram.client.send_message        (бот)
                        habibi_telegram.user_client.send_message   (аккаунт)
                                   │
                        Telegram Message (Outgoing, is_automated=1)
```

### Переносимость

Цикл «движок ↔ инструменты» выносится из `api.send_message` в
`habibi_ai/loop.py`, который **не импортирует frappe** — так же, как уже
сделан `engine.py`. На вход: клиент движка, функция исполнения инструмента,
набор имён инструментов, лимит витков, флаг отладки. На выход: текст ответа
и собранная трассировка.

Чтобы перенести ИИ в систему не на Frappe, достаточно `engine.py` +
`loop.py` и своего клея (откуда сообщение, как исполнить инструмент, куда
отправить ответ). Движок — отдельный HTTP-сервис и не меняется.

## 2. Данные

### 2.1. Правки в `habibi_telegram` (общие, без ИИ)

Поля `Telegram Message`:

| Поле | Тип | Смысл |
|---|---|---|
| `telegram_bot` | Link → Telegram Bot | Через какого бота пришло/ушло сообщение. Симметрично существующему `telegram_account`. |
| `is_automated` | Check | Сообщение отправил не человек. |

Заполнение:

- `handlers.logging.log_incoming_message` — `telegram_bot` из контекста и
  `sent_on` из `message.date` (сейчас у сообщений бота `sent_on` пуст);
- `handlers.logging.log_outgoing_message` — `telegram_bot`;
- `is_automated = 1`, если выполняется одно из:
  - `frappe.flags.in_telegram_update` (ответы обработчиков бота, `/start`,
    аутентификация);
  - отправка идёт из `overrides.notification` (Notification);
  - вызывающий выставил `frappe.flags.telegram_automated_send`.
- MTProto (`handlers.account.log_message`) — `is_automated` по тем же
  флагам; исходящие, увиденные при синхронизации (отправлены с телефона),
  флагов не несут и остаются `is_automated = 0`.

Сообщения, записанные до миграции, получают `is_automated = 0`; на них
логика паузы не срабатывает, потому что `after_insert` для них уже прошёл.

Отправитель-бот определяется по `Telegram User.is_bot`. Если такого поля
нет — добавить его (Check) и заполнять из `user.is_bot` апдейта / Telethon
`User.bot`.

### 2.2. Custom Field, которые ставит `habibi_ai`

Ставятся в `after_install` и `after_migrate` только если на сайте установлен
`habibi_telegram`; повторный запуск идемпотентен.

На **Telegram Bot** и **Telegram Account**, отдельной секцией «ИИ»:

| Поле | Тип | Смысл |
|---|---|---|
| `ai_enabled` | Check | Использовать ИИ для ответа |
| `ai_bot` | Data | id бота движка (`ai_bots.id`). Выбор — из `habibi_ai.api.list_bots` в клиентском скрипте формы. |

Проверка при сохранении (`validate` через doc_events): если `ai_enabled`,
то `ai_bot` задан, движок настроен (`habibi_ai_engine_url`,
`habibi_ai_engine_token`), бот существует для тенанта (`_check_bot`).
Иначе — понятная ошибка на форме.

### 2.3. Доктайп `AI Channel Chat` (в `habibi_ai`)

Одна запись на пару «канал + Telegram-чат». Отдельный доктайп, а не поля на
`Telegram Chat`, потому что `Telegram Chat` именуется по `chat_id`, и личный
диалог с одним человеком через бота и через аккаунт — один документ.

| Поле | Тип | Смысл |
|---|---|---|
| `channel_doctype` | Link → DocType | `Telegram Bot` / `Telegram Account` |
| `channel_name` | Dynamic Link | канал |
| `telegram_chat` | Link → Telegram Chat | чат |
| `engine_chat_id` | Int | `customer_chats.id` в движке |
| `ai_paused` | Check | ИИ в этом чате выключен |
| `paused_reason` | Select | `Оператор ответил вручную` / `Выключено вручную` / `Нет прав писать` |
| `paused_on` | Datetime | когда |
| `last_processed_message` | Link → Telegram Message | последнее входящее, отданное ИИ |

Уникальный индекс: (`channel_doctype`, `channel_name`, `telegram_chat`).
Запись создаётся при первом ответе ИИ. Переключение паузы вручную — из
списка/формы доктайпа. Права: System Manager — полные, остальным — нет.

Чат в движке заводится через `EngineClient.create_chat(bot_id,
external_user)` с `external_user = "telegram:<channel_doctype>:<channel_name>:<chat_id>"`;
`tenant` проставляет сервер, как и сейчас.

### 2.4. Пауза при ручном ответе оператора

`after_insert` исходящего `Telegram Message`: если `is_automated = 0` и у
сообщения есть канал (`telegram_bot` или `telegram_account`) с
`ai_enabled` — для этой пары ставится `ai_paused = 1`,
`paused_reason = "Оператор ответил вручную"`. Если записи пары ещё нет —
создаётся сразу на паузе. Снимается только вручную.

## 3. Фоновая обработка

### 3.1. Фильтр в хуке

`channels.telegram.should_reply(message, channel, pair, now) -> bool` —
чистая функция, без сети и без frappe (данные передаёт вызывающий):

- `message.direction == "Incoming"`;
- у сообщения есть канал, у канала `ai_enabled` и `ai_bot`;
- `pair` отсутствует или `not pair.ai_paused`;
- отправитель не бот;
- `content` непустой и `media_type` не из `voice`, `video_note`, `sticker`,
  `animation` без подписи (подпись к медиа — это текст, на неё отвечаем);
- `now - message.sent_on <= 5 минут` (отсекает подтянутую историю MTProto,
  `DifferenceTooLong`, повторную доставку старого).

Если `True` — `frappe.enqueue` в очередь `long` с
`job_id = "ai-reply:<channel_doctype>:<channel_name>:<chat>"`,
`deduplicate=True`, `enqueue_after_commit=True`.

### 3.2. Склейка подряд идущих сообщений

- Задача стартует с задержкой ~3 с (`time.sleep` в начале задачи — очередь
  `long`, не блокирует вебхук).
- Под redis-блокировкой пары
  (`<site>:ai-reply:<channel_doctype>:<channel_name>:<chat>`) задача:
  1. перечитывает пару — если на паузе, выходит;
  2. берёт все входящие этого канала в этом чате после
     `last_processed_message`, прошедшие те же проверки, что в §3.1 (кроме
     свежести — её уже проверили при постановке);
  3. склеивает их `content` через `\n` в одно сообщение для движка;
  4. `loop.run(...)`, отправляет ответ, записывает
     `last_processed_message`;
  5. если за время генерации появились новые входящие — ставит себя
     ещё раз.

Пока задача ждёт в очереди, дубль с тем же `job_id` не создаётся; если
задача уже выполняется, новое сообщение будет подобрано на шаге 5.

### 3.3. Петли

- Ответ ИИ — исходящее с `is_automated = 1`: ИИ на него не реагирует,
  паузу он не ставит.
- Сообщения ботов игнорируются — два бота в группе не зациклятся.
- MTProto: `user_client.send_message` записывает ответ сразу; при
  следующей синхронизации он отсекается дедупликацией по `message_id`.

### 3.4. Ошибки

| Ситуация | Реакция |
|---|---|
| Движок недоступен / ошибка LLM | Одна повторная попытка через 30 с, затем `frappe.log_error`. Клиенту ничего не отправляется. |
| Исчерпан лимит витков | `frappe.log_error` + уведомление в колокольчик `notify_user` канала: «ИИ не смог ответить в чате X». |
| Telegram не принял отправку | `frappe.log_error`. При ошибке прав на запись (`CHAT_WRITE_FORBIDDEN`, 403 `bot was blocked`/`not enough rights`) — пауза с причиной «Нет прав писать». |
| Движок не настроен | Задача не ставится; при сохранении канала с `ai_enabled` — ошибка на форме (§2.2). |

### 3.5. Пользователь

Задача выполняется от `Administrator`. Текущие инструменты (`get_menu`,
`get_delivery_zones`) только читают данные. Поле «Пользователь для ИИ» на
канале — когда появятся изменяющие инструменты.

## 4. Изменения по файлам

### `habibi_ai`

- `loop.py` — новый, без frappe: `run(client, chat_id, message, bot_id,
  tool_names, tool_definitions, execute_tool, max_loop, debug) -> dict`.
  Ошибки — собственные исключения (`LoopExhausted`, `BadStep`), frappe
  их переводит в `frappe.throw` в `api.py`.
- `api.send_message` — переходит на `loop.run`; поведение для браузера и
  трассировка не меняются.
- `channels/__init__.py`, `channels/telegram.py` — фильтр, хуки
  `on_message_insert`, `validate_channel`, задача `reply_job`, отправка.
- `habibi_ai/doctype/ai_channel_chat/` — доктайп.
- `setup.py` — Custom Field при наличии `habibi_telegram`.
- `hooks.py` — `doc_events` для `Telegram Message` (`after_insert`),
  `Telegram Bot` и `Telegram Account` (`validate`); `doctype_js` для формы
  с выбором `ai_bot`.

### `habibi_telegram`

- `telegram_message.json` — поля `telegram_bot`, `is_automated`.
- `telegram_user.json` — `is_bot`, если его нет.
- `handlers/logging.py`, `handlers/account.py`, `overrides/notification.py`
  — заполнение полей (§2.1).
- `commands/__init__.py`, `user_client.py` — `listen-all`, heartbeat,
  пропуск аккаунтов с живым слушателем в `sync_all_accounts` (§7).

### `habibi_docker`

- `habibi/overrides/compose.telegram-listener.yaml` — сервис
  `telegram-listener`.
- Документация по подключению сервиса.

## 5. Тесты

Быстрые, без сайта (`python -m unittest`):

- `habibi_ai/tests/test_loop.py` — сразу текст; инструмент → текст;
  инструмент вне предложенного набора отклоняется; лимит исчерпан;
  `raw` передаётся нетронутым; шаг неизвестной формы. Соответствующие
  случаи из `test_api.py` переезжают сюда, `test_api.py` проверяет, что
  `send_message` работает поверх `loop`.
- `habibi_ai/tests/test_telegram_channel.py` — `should_reply` таблицей
  случаев (§3.1); склейка входящих; пауза на ручное исходящее и её
  отсутствие на автоматическое.

На сайте (`bench run-tests --app ...`):

- `habibi_telegram` — `telegram_bot`, `is_automated`, `sent_on`
  заполняются во всех путях записи (§2.1).
- `habibi_ai` — Custom Field ставятся в `after_migrate` только при
  установленном `habibi_telegram`; повторный запуск ничего не дублирует.

Сквозная проверка на `client1.example.com`:

1. Поставить `habibi_telegram`, завести тестового бота, включить ИИ.
2. Сообщение боту → пришёл ответ; в движке чат `telegram:...`; у ответа
   `is_automated = 1`.
3. Три сообщения подряд → один ответ.
4. Ручной ответ из консоли → пара на паузе; следующее сообщение клиента
   ИИ не трогает.
5. То же с тестовым личным аккаунтом — со слушателем и без.

## 6. Порядок работ

1. `habibi_ai`: `loop.py`, перевод `api.send_message`. Поведение браузера
   не меняется.
2. `habibi_telegram`: поля и флаги §2.1.
3. `habibi_ai`: доктайп, Custom Field, хуки, задача, отправка, пауза.
4. `habibi_telegram` + `habibi_docker`: слушатель (§7).
5. Релиз по тегу, `bench migrate` на сайтах, проверка на client1.

Шаги 1–3 выкатываются без шага 4: личные аккаунты тогда отвечают с
задержкой до минуты.

## 7. Слушатель MTProto

- `bench telegram listen-all` — процесс-менеджер: обходит сайты с
  установленным `habibi_telegram`, держит по потоку-слушателю
  (`user_client.listen`) на каждый аккаунт с `enabled` и `sync_enabled`.
  Раз в минуту перечитывает список: новые подключает, выключенные
  отключает; упавший слушатель перезапускается с паузой.
- Heartbeat в redis `telegram-listener:<site>:<account>` раз в 30 с с TTL
  90 с. `sync_all_accounts` пропускает аккаунты с живым heartbeat — одна
  сессия Telethon не должна работать в двух соединениях
  (`AUTH_KEY_DUPLICATED`). Слушатель упал → через минуту аккаунт снова на
  cron.
- При старте слушатель делает `sync_account` и добирает пропущенное.
- Сервис `telegram-listener` в `habibi/overrides/compose.telegram-listener.yaml`:
  образ приложения, `command: bench telegram listen-all`,
  `restart: unless-stopped`.

## 8. Риски

- **Антиспам Telegram для личных аккаунтов.** Автоответы на входящие —
  наименее рискованный сценарий, но ответы «везде», включая группы, на
  личном номере могут привести к ограничениям. Решение осознанное.
- **Дедупликация по (`chat`, `message_id`).** Нумерация сообщений у бота и
  у аккаунта независима, а `Telegram Chat` общий — совпадение номеров
  теоретически теряет сообщение, и ИИ на него не ответит. Существующая
  проблема `habibi_telegram`, чинится отдельно.
