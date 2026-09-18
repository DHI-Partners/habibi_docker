# Ответы ИИ во входящих Telegram — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Входящее сообщение Telegram (бот или личный аккаунт) с включённым «Использовать ИИ для ответа» уходит в движок ИИ, ответ возвращается в тот же чат тем же каналом.

**Architecture:** `habibi_ai` подписывается на `after_insert` у `Telegram Message` и ставит фоновую задачу; задача ведёт ход агента через вынесенный из `api.py` цикл `loop.py` (без frappe) и отправляет ответ функциями `habibi_telegram`. `habibi_telegram` про ИИ не знает — получает только общие поля `telegram_bot`, `is_automated`, `is_bot` и параметр `automated`. Отдельно — слушатель MTProto для мгновенного приёма у личных аккаунтов.

**Tech Stack:** Frappe v16 (Python 3.14, unittest, `frappe.tests.IntegrationTestCase`), Telethon, Directus-движок `habibi_ai_engine` (не меняется), Docker Compose.

**Spec:** `habibi/specs/2026-09-18-telegram-ai-replies-design.md` — читать вместе с планом.

## Global Constraints

- Отступы — табы, `line-length = 110`, как в `pyproject.toml` обоих приложений.
- Комментарии и докстринги — по-русски, объясняют «почему», в стиле соседнего кода.
- Имена тестов — по-русски (`test_пауза_на_ручной_ответ`), как в `habibi_ai/tests`.
- `engine.py`, `loop.py`, `channels/decisions.py` **не импортируют frappe**.
- `habibi_telegram` не импортирует и не упоминает `habibi_ai`.
- tenant берётся только из `frappe.local.site` (через `api.get_client()`), никогда из данных сообщения.
- Отвечаем только на сообщения не старше 5 минут; на голосовые/стикеры без подписи не отвечаем.
- Задача ответа выполняется от `Administrator`, в очереди `long`.
- При изменении JSON доктайпа обязательно обновлять `"modified"` — иначе `bench migrate` изменения не подхватит.
- Ветки: `habibi_ai` — `main`, `habibi_telegram` — `master`, `habibi_docker` — `main`. Работать в фича-ветке `feat/telegram-ai-replies` в каждом репозитории.

## Как запускать команды

Все команды — из `/Users/fsa/Projects/habibi/habibi_docker`. Dev-бенч живёт в devcontainer:

```bash
DC="docker compose -f .devcontainer/docker-compose.yml"
# быстрые тесты без сайта:
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && env/bin/python -m unittest <модуль> -v"
# тесты на сайте:
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module <модуль>"
```

Если контейнер не поднят: `./habibi/dev.sh up` (или `./habibi/dev.sh init` после Task 0).

## Карта файлов

| Файл | Задача | Ответственность |
|---|---|---|
| `.devcontainer/docker-compose.yml`, `habibi/dev.sh` | 0 | `habibi_telegram` в dev-бенче |
| `habibi_ai/habibi_ai/loop.py` | 1 | цикл хода агента, без frappe |
| `habibi_ai/habibi_ai/api.py` | 1 | `run_turn`, `send_message` поверх `loop` |
| `habibi_ai/habibi_ai/tests/test_loop.py` | 1 | тесты цикла |
| `habibi_telegram/.../telegram_message.json`, `telegram_user.json` | 2 | поля `telegram_bot`, `is_automated`, `is_bot` |
| `habibi_telegram/habibi_telegram/handlers/logging.py`, `handlers/account.py`, `client.py`, `user_client.py`, `overrides/notification.py`, `mtproto.py`, `telegram_user.py` | 2 | заполнение полей, параметр `automated` |
| `habibi_telegram/habibi_telegram/tests/test_message_origin.py` | 2 | тесты на сайте |
| `habibi_ai/habibi_ai/channels/decisions.py` | 3 | чистые решения канала |
| `habibi_ai/habibi_ai/tests/test_channel_decisions.py` | 3 | тесты решений |
| `habibi_ai/habibi_ai/habibi_ai/doctype/ai_channel_chat/*` | 4 | доктайп пары «канал + чат» |
| `habibi_ai/habibi_ai/setup.py`, `hooks.py`, `public/js/telegram_channel_ai.js`, `channels/telegram.py` (validate) | 4 | Custom Field, выбор ИИ-бота, проверка канала |
| `habibi_ai/habibi_ai/channels/telegram.py` | 5 | хук, пауза, задача ответа, отправка |
| `habibi_ai/habibi_ai/tests/test_telegram_bridge.py` | 4, 5 | тесты на сайте |
| `habibi_telegram/habibi_telegram/listener.py`, `commands/__init__.py`, `user_client.py` | 6 | `listen-all`, heartbeat |
| `habibi/overrides/compose.telegram-listener.yaml` | 6 | сервис слушателя |

---

### Task 0: `habibi_telegram` в dev-бенче

**Files:**
- Modify: `habibi_docker/.devcontainer/docker-compose.yml` (блок volumes сервиса `frappe`, рядом со строкой `- ../../habibi_ai:/workspace/repos/habibi_ai:cached`)
- Modify: `habibi_docker/habibi/dev.sh:21` (`APPS=`)

**Interfaces:**
- Produces: сайт `dev.localhost` с установленными `habibi_telegram` и `habibi_ai`; `allow_tests` уже включён скриптом.

- [ ] **Step 1: Смонтировать репозиторий**

В `.devcontainer/docker-compose.yml` после строки с `habibi_ai` добавить:

```yaml
      - ../../habibi_telegram:/workspace/repos/habibi_telegram:cached
```

- [ ] **Step 2: Добавить приложение в список**

В `habibi/dev.sh` строку 21 заменить на:

```bash
APPS=(habibi_ui habibi_ai habibi_telegram)
```

Порядок важен только для первичного `new-site` (там стоит явный список `--install-app`); доустановка ниже по циклу подхватит `habibi_telegram` на существующем сайте.

- [ ] **Step 3: Пересоздать контейнер и доустановить**

```bash
docker compose -f .devcontainer/docker-compose.yml up -d --force-recreate frappe
./habibi/dev.sh init
```

Expected: в выводе `==> приложения подключены`, без ошибок `install-app`.

- [ ] **Step 4: Проверить**

```bash
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost list-apps"
```

Expected: в списке есть `habibi_telegram` и `habibi_ai`.

- [ ] **Step 5: Commit** (репозиторий `habibi_docker`)

```bash
git add .devcontainer/docker-compose.yml habibi/dev.sh
git commit -m "chore(dev): habibi_telegram в dev-бенче — нужен для интеграции с ИИ"
```

---

### Task 1: Цикл хода агента в `loop.py`

Вынести цикл из `api.send_message` в модуль без frappe; `api.send_message` работает поверх него без изменения поведения. Появляется `api.run_turn` — общий вход для браузера и каналов.

**Files:**
- Create: `habibi_ai/habibi_ai/loop.py`
- Create: `habibi_ai/habibi_ai/tests/test_loop.py`
- Modify: `habibi_ai/habibi_ai/api.py` (константа `MAX_LOOP`, функции `call`, `send_message`; `_tool_names` остаётся)

**Interfaces:**
- Produces:
  - `loop.DEFAULT_MAX_LOOP: int = 8`
  - `loop.resolve_max_loop(configured, default=DEFAULT_MAX_LOOP) -> int`
  - `loop.run(step, message, *, offered: list[str], definitions: list[dict], execute, max_loop: int, debug: bool = False) -> {"response": str, "debug": list}`; `step(message, *, turn, tools, debug) -> dict`, `execute(name, args) -> str`
  - `loop.BadStep(Exception)`, `loop.LoopExhausted(Exception)` — `str(e)` уже человекочитаем
  - `api.run_turn(client, chat_id: int, message: str, bot_id=None, debug=False) -> {"response", "debug"}` — **без** frappe-обёртки ошибок: пробрасывает `EngineError`, `ChatNotFound`, `BotNotFound`, `BadStep`, `LoopExhausted`
  - `api.MAX_LOOP == loop.DEFAULT_MAX_LOOP`

- [ ] **Step 1: Написать падающие тесты цикла**

`habibi_ai/habibi_ai/tests/test_loop.py`:

```python
"""Тесты цикла хода агента.

Не импортируют frappe, как и test_engine.py: loop.py от него не зависит, и
цикл должен проверяться за секунды — и переноситься в систему не на Frappe
вместе с engine.py.
"""

import unittest
from unittest.mock import Mock

from habibi_ai import loop


def _step(*results):
	return Mock(side_effect=list(results))


def _run(step, execute=None, offered=("get_menu",), max_loop=5, debug=False):
	return loop.run(
		step,
		"привет",
		offered=list(offered),
		definitions=[{"name": n} for n in offered],
		execute=execute or Mock(return_value="результат"),
		max_loop=max_loop,
		debug=debug,
	)


class TestЦикл(unittest.TestCase):
	def test_текст_с_первого_шага(self):
		step = _step({"type": "text", "content": "здравствуйте"})
		result = _run(step)
		self.assertEqual(result, {"response": "здравствуйте", "debug": []})
		self.assertEqual(step.call_count, 1)

	def test_шаг_получает_сообщение_turn_tools_debug(self):
		step = _step({"type": "text", "content": "ок"})
		_run(step, debug=True)
		args, kwargs = step.call_args
		self.assertEqual(args, ("привет",))
		self.assertEqual(kwargs["turn"], [])
		self.assertEqual(kwargs["tools"], [{"name": "get_menu"}])
		self.assertTrue(kwargs["debug"])

	def test_инструмент_исполняется_и_результат_уходит_в_следующий_шаг(self):
		step = _step(
			{"type": "tool_use", "id": "t1", "name": "get_menu", "input": {"q": 1}},
			{"type": "text", "content": "шаурма 350"},
		)
		execute = Mock(return_value="шаурма — 350")
		result = _run(step, execute=execute)
		execute.assert_called_once_with("get_menu", {"q": 1})
		self.assertEqual(result["response"], "шаурма 350")
		turn = step.call_args_list[1].kwargs["turn"]
		self.assertEqual(turn[0], {"type": "tool_use", "id": "t1", "name": "get_menu", "input": {"q": 1}})
		self.assertEqual(turn[1], {"type": "tool_result", "id": "t1", "content": "шаурма — 350"})

	def test_raw_передаётся_нетронутым(self):
		raw = [{"type": "thinking", "text": "..."}]
		step = _step(
			{"type": "tool_use", "id": "t1", "name": "get_menu", "input": {}, "raw": raw},
			{"type": "text", "content": "ок"},
		)
		_run(step)
		self.assertEqual(step.call_args_list[1].kwargs["turn"][0]["raw"], raw)

	def test_без_raw_ключа_нет(self):
		step = _step(
			{"type": "tool_use", "id": "t1", "name": "get_menu", "input": {}},
			{"type": "text", "content": "ок"},
		)
		_run(step)
		self.assertNotIn("raw", step.call_args_list[1].kwargs["turn"][0])

	def test_имя_вне_предложенного_не_исполняется(self):
		step = _step(
			{"type": "tool_use", "id": "t1", "name": "create_order", "input": {}},
			{"type": "text", "content": "готово"},
		)
		execute = Mock()
		result = _run(step, execute=execute, debug=True)
		execute.assert_not_called()
		rejection = step.call_args_list[1].kwargs["turn"][1]
		self.assertIn("create_order", rejection["content"])
		rejected = [s for s in result["debug"] if s["step"] == "tool_rejected"]
		self.assertEqual(rejected[0]["data"], {"name": "create_order", "offered": ["get_menu"]})

	def test_шаг_неизвестной_формы(self):
		with self.assertRaises(loop.BadStep) as cm:
			_run(_step({"type": "нечто"}))
		self.assertIn("неизвестной формы", str(cm.exception))

	def test_лимит_витков(self):
		step = _step(*[{"type": "tool_use", "id": f"t{i}", "name": "get_menu", "input": {}} for i in range(10)])
		with self.assertRaises(loop.LoopExhausted) as cm:
			_run(step, max_loop=3)
		self.assertEqual(step.call_count, 3)
		self.assertIn("3", str(cm.exception))

	def test_виток_в_трассировке_идёт_перед_шагами_движка(self):
		step = _step(
			{"type": "tool_use", "id": "t1", "name": "get_menu", "input": {}, "debug": [{"step": "engine_1", "data": {}}]},
			{"type": "text", "content": "ок", "debug": [{"step": "engine_2", "data": {}}]},
		)
		result = _run(step, debug=True, max_loop=4)
		steps = [s["step"] for s in result["debug"]]
		self.assertEqual(steps, ["loop", "engine_1", "loop", "engine_2"])
		self.assertEqual(result["debug"][2]["data"], {"iteration": 2, "max_loop": 4})

	def test_без_debug_трассировка_пуста(self):
		step = _step({"type": "text", "content": "ок", "debug": [{"step": "engine", "data": {}}]})
		self.assertEqual(_run(step)["debug"], [])


class TestЛимит(unittest.TestCase):
	def test_положительное_целое_берётся(self):
		self.assertEqual(loop.resolve_max_loop(3), 3)

	def test_непригодное_заменяется_значением_по_умолчанию(self):
		for bad in (None, 0, -1, "5", 2.5, True, Mock()):
			with self.subTest(bad=bad):
				self.assertEqual(loop.resolve_max_loop(bad), loop.DEFAULT_MAX_LOOP)
```

- [ ] **Step 2: Убедиться, что падают**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && env/bin/python -m unittest habibi_ai.tests.test_loop -v"`
Expected: FAIL — `ImportError: cannot import name 'loop' from 'habibi_ai'`.

- [ ] **Step 3: Реализовать `loop.py`**

`habibi_ai/habibi_ai/loop.py`:

```python
"""Цикл хода агента: движок решает, вызывающий исполняет, пока не будет текста.

Не импортирует frappe — по той же причине, что engine.py, и ещё по одной:
вместе они и есть переносимая часть ИИ-модуля. Системе не на Frappe хватит
этих двух файлов и своего клея — откуда сообщение, как исполнить инструмент,
куда отправить ответ.

Инструменты исполняет вызывающий, а не движок: они работают под правами
тенанта, и учётные данные тенантов движку не нужны и не передаются.
"""

DEFAULT_MAX_LOOP = 8


class BadStep(Exception):
	"""Движок вернул шаг неизвестной формы.

	Контракт шага фиксирован движком, но проверяем его здесь: без этого чужой
	или устаревший ответ падал бы голым KeyError, и причину искали бы в
	habibi_ai вместо движка, который её и создал.
	"""

	def __init__(self, step):
		super().__init__(f"Движок вернул шаг неизвестной формы: {step!r}")
		self.step = step


class LoopExhausted(Exception):
	"""Модель зациклилась на вызовах инструментов и не пришла к ответу.

	Молчаливая остановка скрыла бы это — человек должен увидеть внятную
	ошибку, а не зависший чат.
	"""

	def __init__(self, max_loop):
		super().__init__(
			f"Бот не смог завершить ответ за {max_loop} обращений к инструментам. "
			"Проверьте инструкции сценариев в трассировке."
		)
		self.max_loop = max_loop


def resolve_max_loop(configured, default=DEFAULT_MAX_LOOP):
	"""Лимит витков из поля бота либо значение по умолчанию.

	Непригодное значение (ноль, минус, мусор из ручной правки) молча выродило
	бы цикл в одну ошибку «не смог ответить», поэтому в дело идёт только
	положительное целое. bool — подкласс int, его отсекаем явно.
	"""
	if isinstance(configured, int) and not isinstance(configured, bool) and configured > 0:
		return configured
	return default


def run(step, message, *, offered, definitions, execute, max_loop, debug=False):
	"""Ведёт ход до текстового ответа.

	step(message, *, turn, tools, debug) — один шаг движка (EngineClient.step
	с уже привязанными chat_id и bot_id); execute(name, args) — исполнение
	инструмента, всегда строка. offered — имена, которые предложены модели на
	этом ходу: исполняется только имя из этого списка.
	"""
	turn = []
	collected_debug = []

	for iteration in range(1, max_loop + 1):
		# Собственный шаг трассировки цикла, а не движка: номер витка и лимит
		# известны только здесь. Кладём его ДО обращения к движку за этот
		# виток, чтобы граница витков в трассировке была видна.
		if debug:
			collected_debug.append({"step": "loop", "data": {"iteration": iteration, "max_loop": max_loop}})

		result = step(message, turn=list(turn), tools=definitions, debug=debug)

		if debug and result.get("debug"):
			collected_debug.extend(result["debug"])

		if result.get("type") == "text":
			return {"response": result.get("content", ""), "debug": collected_debug}

		if result.get("type") != "tool_use" or not result.get("id") or not result.get("name"):
			raise BadStep(result)

		# Вызов и результат идут в turn парой — движку нужны оба, чтобы на
		# следующем витке видеть, что уже исполнено. В историю переписки они
		# не попадают: это внутренняя кухня хода.
		entry = {
			"type": "tool_use",
			"id": result["id"],
			"name": result["name"],
			"input": result.get("input") or {},
		}
		# raw — ответ модели целиком, как его прислал движок. Цикл его не
		# читает, только возит: у моделей с адаптивным мышлением рядом с
		# tool_use лежат блоки thinking, и собранный заново виток без них
		# провайдер отвергает. Нет поля — нет и ключа: для движка отсутствие и
		# пустое значение не одно и то же.
		if result.get("raw") is not None:
			entry["raw"] = result["raw"]
		turn.append(entry)

		if result["name"] in offered:
			content = execute(result["name"], result.get("input") or {})
		else:
			# Движок решает, что предложить модели, но не что исполнять под
			# правами тенанта. Модель получает отказ текстом и может
			# исправиться на следующем витке.
			content = (
				f"Инструмент {result['name']} не был предложен на этом ходу. "
				f"Доступные: {', '.join(offered)}"
			)
			if debug:
				collected_debug.append(
					{"step": "tool_rejected", "data": {"name": result["name"], "offered": list(offered)}}
				)

		turn.append({"type": "tool_result", "id": result["id"], "content": content})

	raise LoopExhausted(max_loop)
```

- [ ] **Step 4: Прогнать тесты цикла**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && env/bin/python -m unittest habibi_ai.tests.test_loop -v"`
Expected: PASS, 12 тестов.

- [ ] **Step 5: Перевести `api.py` на `loop`**

В `habibi_ai/habibi_ai/api.py`:

1. Импорты: заменить `from habibi_ai import tools` на `from habibi_ai import loop, tools`.
2. `MAX_LOOP = 8` заменить на `MAX_LOOP = loop.DEFAULT_MAX_LOOP`.
3. В функции `call` перед `except EngineError as e:` добавить ветку:

```python
	except (loop.BadStep, loop.LoopExhausted) as e:
		frappe.throw(str(e))
```

4. Тело `send_message` целиком (от `debug = DEBUG_ROLE in ...` до финального `frappe.throw(...)` включительно) заменить на:

```python
	debug = DEBUG_ROLE in frappe.get_roles()
	result = call(run_turn, get_client(), int(chat_id), message, bot_id, debug)
	response = {"success": True, "response": result["response"]}
	if result["debug"]:
		response["debug"] = result["debug"]
	return response


def run_turn(client, chat_id, message, bot_id=None, debug=False):
	"""Один ход агента — общий для браузера и каналов.

	Ошибки движка и цикла пробрасываются как есть: браузеру их переводит в
	человеческий текст call(), а канальный адаптер решает сам — повторить,
	поставить чат на паузу или оповестить оператора.

	Лимит задаётся полем бота; бот тот же, что и в step: явный bot_id, иначе
	бот чата.
	"""
	max_loop = loop.resolve_max_loop(client.get_max_loop(chat_id, bot_id), MAX_LOOP)
	offered = _tool_names()
	return loop.run(
		lambda text, **kwargs: client.step(chat_id, text, bot_id, **kwargs),
		message,
		offered=offered,
		definitions=tools.definitions(offered),
		execute=tools.execute,
		max_loop=max_loop,
		debug=debug,
	)
```

Докстринг `send_message` оставить, убрав из него фразу «Ведёт цикл…» и заменив на «Ход ведёт run_turn; здесь — гейт трассировки и перевод ошибок.»

- [ ] **Step 6: Прогнать все быстрые тесты модуля**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && env/bin/python -m unittest habibi_ai.tests.test_loop habibi_ai.tests.test_engine habibi_ai.tests.test_api habibi_ai.tests.test_tools -v"`
Expected: PASS все. Существующие `TestЦиклИнструментов` в `test_api.py` должны пройти без правок — это и есть проверка, что поведение браузера не изменилось. Если `test_вызов_инструмента...` падает на `run.assert_called_once_with` — значит `execute=tools.execute` захвачен до патча; он вычисляется при вызове `run_turn`, так что падать не должен.

- [ ] **Step 7: Commit** (репозиторий `habibi_ai`)

```bash
git checkout -b feat/telegram-ai-replies
git add habibi_ai/loop.py habibi_ai/api.py habibi_ai/tests/test_loop.py
git commit -m "refactor: цикл хода агента — в loop.py без frappe, api.run_turn для каналов"
```

---

### Task 2: Происхождение сообщений в `habibi_telegram`

**Files:**
- Modify: `habibi_telegram/habibi_telegram/habibi_telegram/doctype/telegram_message/telegram_message.json`
- Modify: `habibi_telegram/habibi_telegram/habibi_telegram/doctype/telegram_user/telegram_user.json`
- Modify: `habibi_telegram/habibi_telegram/habibi_telegram/doctype/telegram_user/telegram_user.py` (`get_or_create`)
- Modify: `habibi_telegram/habibi_telegram/mtproto.py` (`entity_to_user`)
- Modify: `habibi_telegram/habibi_telegram/handlers/logging.py` (`log_incoming_message`, `log_outgoing_message`)
- Modify: `habibi_telegram/habibi_telegram/client.py` (`send_message`, `send_file`, `send_voice`)
- Modify: `habibi_telegram/habibi_telegram/handlers/account.py` (`log_message`)
- Modify: `habibi_telegram/habibi_telegram/user_client.py` (`send_message`)
- Modify: `habibi_telegram/habibi_telegram/overrides/notification.py` (два `frappe.enqueue`)
- Create: `habibi_telegram/habibi_telegram/tests/__init__.py`, `habibi_telegram/habibi_telegram/tests/test_message_origin.py`

**Interfaces:**
- Produces:
  - `Telegram Message.telegram_bot` (Link → Telegram Bot), `Telegram Message.is_automated` (Check)
  - `Telegram User.is_bot` (Check)
  - `client.send_message(..., automated: bool = False)`, то же у `send_file`, `send_voice`
  - `user_client.send_message(account, chat_id, text, ..., automated: bool = False)`
  - `handlers.logging.log_outgoing_message(telegram_bot, result, automated=False)`
  - `handlers.account.log_message(account, message, entities=None, notify=True, automated=False)`
  - Правило: `is_automated = automated or frappe.flags.in_telegram_update`

- [ ] **Step 1: Добавить поля в JSON доктайпов**

Выполнить из корня `habibi_telegram` одноразовый скрипт (в репозиторий не кладётся):

```bash
cd /Users/fsa/Projects/habibi/habibi_telegram && git checkout -b feat/telegram-ai-replies && python3 - <<'EOF'
import json, pathlib

STAMP = "2026-09-18 12:00:00.000000"
BASE = pathlib.Path("habibi_telegram/habibi_telegram/doctype")

def add_fields(path, new_fields):
	p = BASE / path
	d = json.loads(p.read_text())
	names = {f["fieldname"] for f in d["fields"]}
	for field in new_fields:
		field = dict(field)
		after = field.pop("insert_after")
		if field["fieldname"] in names:
			continue
		idx = next(i for i, f in enumerate(d["fields"]) if f["fieldname"] == after) + 1
		d["fields"].insert(idx, field)
		d["field_order"].insert(d["field_order"].index(after) + 1, field["fieldname"])
	d["modified"] = STAMP
	p.write_text(json.dumps(d, indent=1, ensure_ascii=False, sort_keys=True) + "\n")

add_fields("telegram_message/telegram_message.json", [
	{"insert_after": "direction", "fieldname": "is_automated", "fieldtype": "Check", "label": "Is Automated",
	 "default": "0", "read_only": 1,
	 "description": "Sent by automation (bot handlers, notifications, AI), not by a person"},
	{"insert_after": "telegram_account", "fieldname": "telegram_bot", "fieldtype": "Link", "label": "Telegram Bot",
	 "options": "Telegram Bot", "read_only": 1, "search_index": 1,
	 "description": "Bot the message came through"},
])
add_fields("telegram_user/telegram_user.json", [
	{"insert_after": "is_guest", "fieldname": "is_bot", "fieldtype": "Check", "label": "Is Bot",
	 "default": "0", "read_only": 1},
])
EOF
git diff --stat
```

Expected: изменены два JSON-файла; в `git diff` видны новые поля и новый `"modified"`.

- [ ] **Step 2: Написать падающие тесты**

`habibi_telegram/habibi_telegram/tests/__init__.py` — пустой файл.

`habibi_telegram/habibi_telegram/tests/test_message_origin.py`:

```python
"""Откуда сообщение и кто его отправил.

Поля telegram_bot, is_automated и is_bot нужны тем, кто строит поверх истории
автоматику: без них не понять, каким ботом отвечать, и не отличить ответ
человека от ответа обработчика или уведомления.
"""

from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import Mock, patch

import frappe
from frappe.tests import IntegrationTestCase

from habibi_telegram import client
from habibi_telegram.dispatcher import Context
from habibi_telegram.handlers import account as account_store
from habibi_telegram.handlers.logging import log_outgoing_message, pre_process

BOT = "origin-test-bot"


def make_bot():
	if frappe.db.exists("Telegram Bot", BOT):
		return frappe.get_doc("Telegram Bot", BOT)
	with patch(
		"habibi_telegram.telegram_api.TelegramBotAPI.get_me",
		return_value={"is_bot": True, "username": "origin_test_bot"},
	):
		return frappe.get_doc({"doctype": "Telegram Bot", "title": BOT, "api_token": "1:test"}).insert()


def update(message_id, *, text="привет", sender_is_bot=False, chat_id=5550001):
	return {
		"update_id": message_id,
		"message": {
			"message_id": message_id,
			"date": int(datetime.now(UTC).timestamp()),
			"chat": {"id": chat_id, "type": "private", "first_name": "Анна"},
			"from": {"id": chat_id, "is_bot": sender_is_bot, "first_name": "Анна"},
			"text": text,
		},
	}


def sent(message_id, chat_id=5550001, text="ответ"):
	return {"message_id": message_id, "date": int(datetime.now(UTC).timestamp()),
		"chat": {"id": chat_id, "type": "private", "first_name": "Анна"}, "text": text}


class TestВходящиеБота(IntegrationTestCase):
	def setUp(self):
		self.bot = make_bot()

	def test_входящее_знает_своего_бота_и_время(self):
		context = Context(telegram_bot=self.bot, update=update(101))
		pre_process(context)
		message = context.telegram_message
		self.assertEqual(message.telegram_bot, BOT)
		self.assertIsNotNone(message.sent_on)
		self.assertEqual(message.is_automated, 0)

	def test_отправитель_бот_помечается(self):
		context = Context(telegram_bot=self.bot, update=update(102, sender_is_bot=True, chat_id=5550002))
		pre_process(context)
		self.assertEqual(frappe.db.get_value("Telegram User", context.telegram_user.name, "is_bot"), 1)


class TestИсходящиеБота(IntegrationTestCase):
	def setUp(self):
		make_bot()

	def tearDown(self):
		frappe.flags.in_telegram_update = False

	def test_ручная_отправка_не_автоматическая(self):
		doc = log_outgoing_message(BOT, sent(201))
		self.assertEqual(doc.is_automated, 0)
		self.assertEqual(doc.telegram_bot, BOT)

	def test_ответ_обработчика_автоматический(self):
		frappe.flags.in_telegram_update = True
		doc = log_outgoing_message(BOT, sent(202))
		self.assertEqual(doc.is_automated, 1)

	def test_automated_доезжает_через_send_message(self):
		api = Mock()
		api.send_message = Mock(return_value=sent(203, text="от ИИ"))
		with patch("habibi_telegram.client.get_bot", return_value=api):
			client.send_message("от ИИ", from_bot=BOT, chat_id=5550001, automated=True)
		name = frappe.db.get_value("Telegram Message", {"message_id": "203", "telegram_bot": BOT})
		self.assertEqual(frappe.db.get_value("Telegram Message", name, "is_automated"), 1)


class TestЛичныйАккаунт(IntegrationTestCase):
	def setUp(self):
		title = "origin-test-account"
		if frappe.db.exists("Telegram Account", title):
			self.account = frappe.get_doc("Telegram Account", title)
		else:
			self.account = frappe.get_doc({
				"doctype": "Telegram Account", "title": title, "phone": "+70000000000",
				"api_id": "1", "api_hash": "x", "account_id": "9990001",
			}).insert()

	def _message(self, message_id, out):
		from telethon.tl import types

		return SimpleNamespace(
			id=message_id, peer_id=types.PeerUser(user_id=7770001), from_id=None, out=out,
			message="текст", date=datetime.now(UTC), media=None, action=None,
		)

	def test_automated_ставится_по_параметру(self):
		name, _ = account_store.log_message(self.account, self._message(301, out=True), automated=True)
		self.assertEqual(frappe.db.get_value("Telegram Message", name, "is_automated"), 1)

	def test_исходящее_с_телефона_ручное(self):
		name, _ = account_store.log_message(self.account, self._message(302, out=True))
		self.assertEqual(frappe.db.get_value("Telegram Message", name, "is_automated"), 0)
```

- [ ] **Step 3: Мигрировать и убедиться, что тесты падают**

```bash
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost migrate && bench --site dev.localhost run-tests --module habibi_telegram.tests.test_message_origin"
```

Expected: FAIL — `telegram_bot` пуст (None != 'origin-test-bot'), `TypeError: send_message() got an unexpected keyword argument 'automated'`, `log_message() got an unexpected keyword argument 'automated'`. Если `Telegram Account` не создаётся из-за своей `validate` — прочитать `telegram_account.py` и замокать сетевой вызов тем же `patch`, что у бота.

- [ ] **Step 4: `Telegram User.is_bot`**

`mtproto.entity_to_user` — в возвращаемый словарь добавить:

```python
		"is_bot": bool(getattr(entity, "bot", False)),
```

`telegram_user.get_or_create` — в создаваемый документ добавить `is_bot=1 if telegram_user.get("is_bot") else 0,` а ветку найденного пользователя заменить на:

```python
	name = frappe.db.get_value("Telegram User", {"telegram_user_id": telegram_user["id"]})
	if name:
		# Флаг ставим и тем, кого завели до появления поля: бот ботом и
		# остаётся, а без флага автоматика отвечала бы ему в ответ
		if telegram_user.get("is_bot") and not frappe.db.get_value("Telegram User", name, "is_bot"):
			frappe.db.set_value("Telegram User", name, "is_bot", 1, update_modified=False)
		return frappe.get_doc("Telegram User", name)
```

- [ ] **Step 5: Бот — входящие и исходящие**

`handlers/logging.py`:

В импорты добавить:

```python
from datetime import UTC, datetime

from habibi_telegram.mtproto import to_system_datetime
```

В `log_incoming_message` в `frappe.get_doc(...)` добавить аргументы:

```python
		telegram_bot=context.telegram_bot.name,
		sent_on=_sent_on(message),
```

`log_outgoing_message` — новая сигнатура и поля:

```python
def log_outgoing_message(telegram_bot: str, result, automated: bool = False):
	"""
	result — объект Message, который вернул sendMessage / sendDocument.

	automated — отправил не человек. Ответы обработчиков внутри process_update
	автоматические всегда, поэтому флаг апдейта учитывается здесь, а не у
	каждого вызывающего.
	"""
```

и в её `frappe.get_doc(...)` добавить:

```python
		telegram_bot=telegram_bot,
		sent_on=_sent_on(result),
		is_automated=1 if (automated or frappe.flags.in_telegram_update) else 0,
```

В конец модуля:

```python
def _sent_on(message: dict):
	"""Дата сообщения Bot API (unix-время UTC) → дата сайта.

	Без неё нельзя отличить свежее сообщение от доставленного с опозданием, а
	отвечать на вчерашнее автоматике нельзя.
	"""
	if not message.get("date"):
		return None
	return to_system_datetime(datetime.fromtimestamp(message["date"], tz=UTC))
```

`client.py` — в `send_message`, `send_file`, `send_voice` добавить в сигнатуру последним параметром `automated: bool = False`, в докстринг — строку `automated:     отправил не человек (уведомление, ИИ) — пометка в истории`, и каждый вызов `log_outgoing_message(telegram_bot=from_bot, result=result)` заменить на `log_outgoing_message(telegram_bot=from_bot, result=result, automated=automated)`.

- [ ] **Step 6: Уведомления и личный аккаунт**

`overrides/notification.py` — в оба `frappe.enqueue(...)` добавить `automated=True,`.

`handlers/account.py` `log_message` — сигнатура:

```python
def log_message(
	account, message, entities: dict = None, notify: bool = True, automated: bool = False
) -> tuple[str | None, bool]:
```

в докстринг — строку `automated — отправил не человек (передаёт тот, кто отправлял через user_client).`, в `frappe.get_doc(...)` — `is_automated=1 if automated else 0,`.

`user_client.py` `send_message` — добавить параметр `automated: bool = False` последним, в докстринг — `automated — отправил не человек (ИИ, уведомление): пометка в истории.`, последнюю строку заменить на:

```python
	return store.log_message(account, message, _entities_from([message]), automated=automated)[0]
```

- [ ] **Step 7: Прогнать тесты**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module habibi_telegram.tests.test_message_origin"`
Expected: PASS, 7 тестов.

- [ ] **Step 8: Commit** (репозиторий `habibi_telegram`)

```bash
git add habibi_telegram/habibi_telegram/doctype/telegram_message/telegram_message.json \
  habibi_telegram/habibi_telegram/doctype/telegram_user/ habibi_telegram/mtproto.py \
  habibi_telegram/handlers/ habibi_telegram/client.py habibi_telegram/user_client.py \
  habibi_telegram/overrides/notification.py habibi_telegram/tests/
git commit -m "feat: сообщение знает своего бота и кто его отправил — человек или автоматика"
```

---

### Task 3: Чистые решения канала

**Files:**
- Create: `habibi_ai/habibi_ai/channels/__init__.py`
- Create: `habibi_ai/habibi_ai/channels/decisions.py`
- Create: `habibi_ai/habibi_ai/tests/test_channel_decisions.py`

**Interfaces:**
- Produces (`habibi_ai.channels.decisions`, без frappe):
  - `FRESH_FOR: timedelta = 5 минут`
  - `text_of(content) -> str` — текст без служебных пометок вида `[voice]`
  - `is_replyable(message: dict, sender_is_bot: bool, now: datetime) -> bool`; `message` — ключи `direction`, `content`, `sent_on` (datetime или None)
  - `should_reply(message, channel: dict|None, pair: dict|None, sender_is_bot, now) -> bool`; `channel` — `ai_enabled`, `ai_bot`; `pair` — `ai_paused`
  - `combine(contents: Iterable[str]) -> str`
  - `is_write_forbidden(error_text: str) -> bool`
  - `pair_name(channel_doctype, channel_name, telegram_chat) -> str`
  - `external_user(channel_doctype, channel_name, chat_id) -> str`

- [ ] **Step 1: Написать падающие тесты**

`habibi_ai/habibi_ai/channels/__init__.py`:

```python
"""Каналы, по которым ИИ отвечает людям вне интерфейса habibi_ui.

decisions — решения без frappe (переносимы и проверяются за секунды),
telegram — клей с habibi_telegram.
"""
```

`habibi_ai/habibi_ai/tests/test_channel_decisions.py`:

```python
"""Когда ИИ отвечает в канал.

Без frappe: это решения, ошибка в которых означает либо ответ на вчерашнее
сообщение, либо переписку двух ботов по кругу, — проверяются они первыми и
быстро.
"""

import unittest
from datetime import datetime, timedelta

from habibi_ai.channels import decisions

NOW = datetime(2026, 9, 18, 12, 0, 0)
ON = {"ai_enabled": 1, "ai_bot": "3"}


def message(**overrides):
	base = {"direction": "Incoming", "content": "Здравствуйте", "sent_on": NOW - timedelta(seconds=5)}
	base.update(overrides)
	return base


class TestShouldReply(unittest.TestCase):
	def test_отвечаем(self):
		self.assertTrue(decisions.should_reply(message(), ON, None, False, NOW))

	def test_не_отвечаем(self):
		cases = {
			"канал выключен": (message(), {"ai_enabled": 0, "ai_bot": "3"}, None, False),
			"бот не выбран": (message(), {"ai_enabled": 1, "ai_bot": ""}, None, False),
			"настроек нет": (message(), None, None, False),
			"чат на паузе": (message(), ON, {"ai_paused": 1}, False),
			"пишет бот": (message(), ON, None, True),
			"исходящее": (message(direction="Outgoing"), ON, None, False),
			"пусто": (message(content=""), ON, None, False),
			"пробелы": (message(content="   "), ON, None, False),
			"голосовое": (message(content="[voice]"), ON, None, False),
			"служебное": (message(content="[chatjoinedbylink]"), ON, None, False),
			"старое": (message(sent_on=NOW - timedelta(minutes=6)), ON, None, False),
		}
		for name, (msg, channel, pair, is_bot) in cases.items():
			with self.subTest(name):
				self.assertFalse(decisions.should_reply(msg, channel, pair, is_bot, NOW))

	def test_граница_свежести_включительно(self):
		self.assertTrue(decisions.should_reply(message(sent_on=NOW - decisions.FRESH_FOR), ON, None, False, NOW))

	def test_без_даты_считается_свежим(self):
		# Вебхук бота приходит сразу; дата пуста только у записей до миграции
		self.assertTrue(decisions.should_reply(message(sent_on=None), ON, None, False, NOW))

	def test_пауза_снята(self):
		self.assertTrue(decisions.should_reply(message(), ON, {"ai_paused": 0}, False, NOW))

	def test_подпись_к_фото_это_текст(self):
		self.assertTrue(decisions.should_reply(message(content="Сколько стоит это?"), ON, None, False, NOW))


class TestCombine(unittest.TestCase):
	def test_склеивает_через_перевод_строки_без_пометок(self):
		self.assertEqual(
			decisions.combine(["Здравствуйте", "[photo]", " хочу пиццу ", ""]),
			"Здравствуйте\nхочу пиццу",
		)


class TestПраваНаЗапись(unittest.TestCase):
	def test_узнаёт_запрет(self):
		for text in (
			"Forbidden: bot was blocked by the user",
			"Bad Request: not enough rights to send text messages to the chat",
			"You can't write in this chat (caused by SendMessageRequest)",
			"CHAT_WRITE_FORBIDDEN",
			"Not enough rights in this chat",
		):
			with self.subTest(text):
				self.assertTrue(decisions.is_write_forbidden(text))

	def test_прочие_ошибки_не_запрет(self):
		for text in ("Telegram asks to wait 30 seconds before trying again", "Timeout", ""):
			with self.subTest(text):
				self.assertFalse(decisions.is_write_forbidden(text))


class TestИмена(unittest.TestCase):
	def test_имя_пары(self):
		self.assertEqual(decisions.pair_name("Telegram Bot", "shop", "555"), "Telegram Bot:shop:555")

	def test_внешний_пользователь_движка(self):
		self.assertEqual(
			decisions.external_user("Telegram Account", "manager", "555"),
			"telegram:Telegram Account:manager:555",
		)
```

- [ ] **Step 2: Убедиться, что падают**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && env/bin/python -m unittest habibi_ai.tests.test_channel_decisions -v"`
Expected: FAIL — `ImportError: cannot import name 'decisions'`.

- [ ] **Step 3: Реализовать**

`habibi_ai/habibi_ai/channels/decisions.py`:

```python
"""Решения канального адаптера, не зависящие от frappe.

Отвечать ли на сообщение, что склеить в одно, считать ли ошибку отправки
запретом писать. Здесь, а не в telegram.py: цена ошибки — ответ на вчерашнее
или два бота, переписывающиеся по кругу, и проверяться это должно за
секунды. Заодно это переносится в систему не на Frappe вместе с loop.py.
"""

import re
from datetime import timedelta

# Старше этого не отвечаем: подтянутая история MTProto, переполнение
# getDifference, повторная доставка. Ответ на вчерашнее хуже молчания.
FRESH_FOR = timedelta(minutes=5)

# Пометка вложения или служебного события вместо текста: [voice], [photo],
# [chatjoinedbylink]. Такие записи пишет habibi_telegram, когда текста нет.
_MARKER = re.compile(r"\[[\w ]+\]")

# Ошибки, после которых писать в чат бессмысленно, пока человек не вмешается.
# Сравнение по подстроке в нижнем регистре: Bot API и Telethon формулируют
# их по-разному, а повторять отправку в чат, где нас заблокировали, — спам.
WRITE_FORBIDDEN_MARKERS = (
	"chat_write_forbidden",
	"write in this chat",
	"bot was blocked",
	"bot was kicked",
	"not enough rights",
	"have no rights",
	"user is deactivated",
	"chat_admin_required",
	"user_banned_in_channel",
	"chat not found",
)


def text_of(content):
	"""Текст сообщения без пометок вложений; пустая строка, если текста нет."""
	text = (content or "").strip()
	if not text or _MARKER.fullmatch(text):
		return ""
	return text


def is_replyable(message, sender_is_bot, now):
	"""Годится ли само сообщение для ответа — без учёта настроек канала."""
	if message.get("direction") != "Incoming":
		return False
	# Два бота в группе иначе переписывались бы бесконечно
	if sender_is_bot:
		return False
	if not text_of(message.get("content")):
		return False
	sent_on = message.get("sent_on")
	# Без даты — только записи бота до миграции; вебхук приходит сразу
	if sent_on is not None and now - sent_on > FRESH_FOR:
		return False
	return True


def should_reply(message, channel, pair, sender_is_bot, now):
	"""Ставить ли задачу ответа на только что записанное сообщение."""
	if not channel or not channel.get("ai_enabled") or not channel.get("ai_bot"):
		return False
	if pair and pair.get("ai_paused"):
		return False
	return is_replyable(message, sender_is_bot, now)


def combine(contents):
	"""Несколько сообщений подряд — одно сообщение для движка.

	Люди пишут «Здравствуйте», «хочу заказать», «пиццу» тремя сообщениями;
	ответ на каждое по отдельности выглядел бы как три ответа невпопад.
	"""
	return "\n".join(text for text in (text_of(c) for c in contents) if text)


def is_write_forbidden(error_text):
	lowered = (error_text or "").lower()
	return any(marker in lowered for marker in WRITE_FORBIDDEN_MARKERS)


def pair_name(channel_doctype, channel_name, telegram_chat):
	"""Имя записи AI Channel Chat — оно же ключ уникальности пары."""
	return f"{channel_doctype}:{channel_name}:{telegram_chat}"


def external_user(channel_doctype, channel_name, chat_id):
	"""external_user чата в движке: по нему видно, откуда чат, в админке Directus."""
	return f"telegram:{channel_doctype}:{channel_name}:{chat_id}"
```

- [ ] **Step 4: Прогнать тесты**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && env/bin/python -m unittest habibi_ai.tests.test_channel_decisions -v"`
Expected: PASS.

- [ ] **Step 5: Commit** (репозиторий `habibi_ai`)

```bash
git add habibi_ai/channels/__init__.py habibi_ai/channels/decisions.py habibi_ai/tests/test_channel_decisions.py
git commit -m "feat(channels): решения, когда ИИ отвечает в канал — без frappe"
```

---

### Task 4: Доктайп пары, поля на каналах, выбор ИИ-бота

**Files:**
- Create: `habibi_ai/habibi_ai/habibi_ai/doctype/__init__.py` (пустой)
- Create: `habibi_ai/habibi_ai/habibi_ai/doctype/ai_channel_chat/__init__.py` (пустой)
- Create: `habibi_ai/habibi_ai/habibi_ai/doctype/ai_channel_chat/ai_channel_chat.json`
- Create: `habibi_ai/habibi_ai/habibi_ai/doctype/ai_channel_chat/ai_channel_chat.py`
- Modify: `habibi_ai/habibi_ai/setup.py`
- Modify: `habibi_ai/habibi_ai/hooks.py`
- Create: `habibi_ai/habibi_ai/public/js/telegram_channel_ai.js`
- Create: `habibi_ai/habibi_ai/channels/telegram.py` (пока только `validate_channel`)
- Create: `habibi_ai/habibi_ai/tests/test_telegram_bridge.py` (классы этой задачи)

**Interfaces:**
- Consumes: `decisions.pair_name` (Task 3); `api.get_client`, `EngineClient._check_bot`, `BotNotFound` (существующие)
- Produces:
  - DocType `AI Channel Chat`: `channel_doctype`, `channel_name`, `telegram_chat`, `engine_chat_id`, `ai_paused`, `paused_reason`, `paused_on`, `last_processed_message`; `name == decisions.pair_name(...)`
  - Custom Field `ai_enabled` (Check), `ai_bot` (Autocomplete) на `Telegram Bot` и `Telegram Account`
  - `setup.install_telegram_fields()`, `setup.after_app_install(app_name)`
  - `channels.telegram.validate_channel(doc, method=None)`
  - Константы в `channels/telegram.py`: `PAIR = "AI Channel Chat"`, `REASON_OPERATOR`, `REASON_MANUAL`, `REASON_FORBIDDEN`

- [ ] **Step 1: Написать падающие тесты**

`habibi_ai/habibi_ai/tests/test_telegram_bridge.py`:

```python
"""Связка habibi_telegram → habibi_ai на живом сайте.

Нужен сайт с обоими приложениями (dev.localhost после Task 0). Движок и
Telegram подменяются: проверяется клей — поля, пары, пауза, задача ответа.
"""

from unittest.mock import Mock, patch

import frappe
from frappe.tests import IntegrationTestCase

from habibi_ai import setup
from habibi_ai.channels import decisions
from habibi_ai.channels import telegram as bridge
from habibi_ai.engine import BotNotFound

BOT = "ai-bridge-test-bot"


def make_bot(**values):
	if not frappe.db.exists("Telegram Bot", BOT):
		with patch(
			"habibi_telegram.telegram_api.TelegramBotAPI.get_me",
			return_value={"is_bot": True, "username": "ai_bridge_test_bot"},
		):
			frappe.get_doc({"doctype": "Telegram Bot", "title": BOT, "api_token": "1:test"}).insert()
	if values:
		frappe.db.set_value("Telegram Bot", BOT, values)
	return frappe.get_doc("Telegram Bot", BOT)


class TestПоляКанала(IntegrationTestCase):
	def test_поля_стоят_и_не_дублируются(self):
		setup.install_telegram_fields()
		setup.install_telegram_fields()
		for doctype in ("Telegram Bot", "Telegram Account"):
			meta = frappe.get_meta(doctype)
			self.assertTrue(meta.has_field("ai_enabled"), doctype)
			self.assertEqual(meta.get_field("ai_bot").fieldtype, "Autocomplete")
			self.assertEqual(
				frappe.db.count("Custom Field", {"dt": doctype, "fieldname": ["like", "ai_%"]}), 3
			)

	def test_без_telegram_ничего_не_ставится(self):
		with patch("frappe.get_installed_apps", return_value=["frappe", "habibi_ai"]):
			with patch("habibi_ai.setup.create_custom_fields") as create:
				setup.install_telegram_fields()
		create.assert_not_called()


class TestПроверкаКанала(IntegrationTestCase):
	def setUp(self):
		setup.install_telegram_fields()
		self.bot = make_bot(ai_enabled=0, ai_bot="")

	def test_без_бота_нельзя_включить(self):
		self.bot.ai_enabled = 1
		self.bot.ai_bot = ""
		with self.assertRaises(frappe.ValidationError):
			bridge.validate_channel(self.bot)

	def test_чужой_бот_не_проходит(self):
		self.bot.ai_enabled = 1
		self.bot.ai_bot = "77"
		client = Mock()
		client._check_bot = Mock(side_effect=BotNotFound(77))
		with patch("habibi_ai.api.get_client", return_value=client):
			with self.assertRaises(frappe.ValidationError):
				bridge.validate_channel(self.bot)

	def test_свой_бот_проходит(self):
		self.bot.ai_enabled = 1
		self.bot.ai_bot = "3"
		client = Mock()
		with patch("habibi_ai.api.get_client", return_value=client):
			bridge.validate_channel(self.bot)
		client._check_bot.assert_called_once_with(3)

	def test_выключенный_не_проверяется(self):
		with patch("habibi_ai.api.get_client") as get_client:
			bridge.validate_channel(self.bot)
		get_client.assert_not_called()


class TestПара(IntegrationTestCase):
	def test_имя_пары_и_снятие_паузы(self):
		make_bot()
		chat = frappe.get_doc({"doctype": "Telegram Chat", "chat_id": "5559001", "title": "Тест", "type": "private"})
		chat.insert(ignore_if_duplicate=True)
		pair = frappe.get_doc({
			"doctype": bridge.PAIR, "channel_doctype": "Telegram Bot", "channel_name": BOT,
			"telegram_chat": chat.name, "ai_paused": 1,
		}).insert()
		self.assertEqual(pair.name, decisions.pair_name("Telegram Bot", BOT, chat.name))
		self.assertEqual(pair.paused_reason, bridge.REASON_MANUAL)
		self.assertIsNotNone(pair.paused_on)

		pair.ai_paused = 0
		pair.save()
		self.assertFalse(pair.paused_reason)
		self.assertIsNone(pair.paused_on)
```

- [ ] **Step 2: Убедиться, что падают**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module habibi_ai.tests.test_telegram_bridge"`
Expected: FAIL — `ImportError: cannot import name 'telegram' from 'habibi_ai.channels'` / `AttributeError: module 'habibi_ai.setup' has no attribute 'install_telegram_fields'`.

- [ ] **Step 3: Доктайп `AI Channel Chat`**

`ai_channel_chat.json`:

```json
{
 "actions": [],
 "creation": "2026-09-18 12:00:00.000000",
 "doctype": "DocType",
 "engine": "InnoDB",
 "field_order": [
  "channel_doctype",
  "channel_name",
  "telegram_chat",
  "engine_chat_id",
  "column_break_pause",
  "ai_paused",
  "paused_reason",
  "paused_on",
  "last_processed_message"
 ],
 "fields": [
  {"fieldname": "channel_doctype", "fieldtype": "Link", "in_list_view": 1, "label": "Канал (тип)", "options": "DocType", "read_only": 1, "reqd": 1},
  {"fieldname": "channel_name", "fieldtype": "Dynamic Link", "in_list_view": 1, "in_standard_filter": 1, "label": "Канал", "options": "channel_doctype", "read_only": 1, "reqd": 1},
  {"fieldname": "telegram_chat", "fieldtype": "Link", "in_list_view": 1, "label": "Чат Telegram", "options": "Telegram Chat", "read_only": 1, "reqd": 1},
  {"description": "customer_chats.id в движке ИИ", "fieldname": "engine_chat_id", "fieldtype": "Int", "label": "Чат в движке", "read_only": 1},
  {"fieldname": "column_break_pause", "fieldtype": "Column Break"},
  {"default": "0", "description": "ИИ не отвечает в этом чате", "fieldname": "ai_paused", "fieldtype": "Check", "in_list_view": 1, "in_standard_filter": 1, "label": "ИИ на паузе"},
  {"depends_on": "ai_paused", "fieldname": "paused_reason", "fieldtype": "Select", "label": "Причина", "options": "\nОператор ответил вручную\nВыключено вручную\nНет прав писать", "read_only": 1},
  {"depends_on": "ai_paused", "fieldname": "paused_on", "fieldtype": "Datetime", "label": "На паузе с", "read_only": 1},
  {"fieldname": "last_processed_message", "fieldtype": "Link", "label": "Последнее отвеченное", "options": "Telegram Message", "read_only": 1}
 ],
 "in_create": 1,
 "index_web_pages_for_search": 0,
 "links": [],
 "modified": "2026-09-18 12:00:00.000000",
 "modified_by": "Administrator",
 "module": "Habibi AI",
 "name": "AI Channel Chat",
 "owner": "Administrator",
 "permissions": [
  {"delete": 1, "export": 1, "read": 1, "report": 1, "role": "System Manager", "write": 1}
 ],
 "sort_field": "modified",
 "sort_order": "DESC",
 "states": [],
 "title_field": "telegram_chat",
 "track_changes": 1
}
```

`ai_channel_chat.py`:

```python
"""Пара «канал + Telegram-чат»: чат в движке и пауза ИИ.

Отдельный доктайп, а не поля на Telegram Chat: чат именуется по chat_id, и
личный диалог с одним человеком через бота и через личный аккаунт — один и
тот же документ, а решение «отвечать ли ИИ» у этих каналов разное.
"""

from frappe.model.document import Document
from frappe.utils import now_datetime

from habibi_ai.channels.decisions import pair_name

REASON_MANUAL = "Выключено вручную"


class AIChannelChat(Document):
	def autoname(self):
		# Имя — ключ уникальности: две задачи, заводящие одну пару, упрутся в
		# первичный ключ, а не создадут дубль
		self.name = pair_name(self.channel_doctype, self.channel_name, self.telegram_chat)

	def validate(self):
		if self.ai_paused:
			self.paused_reason = self.paused_reason or REASON_MANUAL
			self.paused_on = self.paused_on or now_datetime()
		else:
			self.paused_reason = None
			self.paused_on = None
```

- [ ] **Step 4: Custom Field и хуки**

`setup.py` — в импорты добавить `from frappe.custom.doctype.custom_field.custom_field import create_custom_fields`, в конец модуля:

```python
TELEGRAM_CHANNELS = ("Telegram Bot", "Telegram Account")


def after_app_install(app_name):
	"""habibi_telegram поставили после habibi_ai — поля нужны сразу, а не с
	ближайшей миграцией: без них канал нельзя включить."""
	if app_name == "habibi_telegram":
		install_telegram_fields()


def install_telegram_fields():
	"""Поля ИИ на каналах Telegram.

	Живут в habibi_ai, а не в доктайпах habibi_telegram: Telegram ставится и
	без ИИ, и знать о нём не должен. Идемпотентно — вызывается на каждой
	миграции; update=True обновляет подписи, если они поменялись.
	"""
	if "habibi_telegram" not in frappe.get_installed_apps():
		return

	# Обе формы кончаются полем notify_role — после него и встаёт секция
	fields = [
		{"fieldname": "ai_section", "fieldtype": "Section Break", "label": "ИИ", "insert_after": "notify_role"},
		{
			"fieldname": "ai_enabled",
			"fieldtype": "Check",
			"label": "Использовать ИИ для ответа",
			"insert_after": "ai_section",
		},
		{
			"fieldname": "ai_bot",
			"fieldtype": "Autocomplete",
			"label": "ИИ-бот",
			"insert_after": "ai_enabled",
			"depends_on": "ai_enabled",
			"mandatory_depends_on": "ai_enabled",
			"description": "Бот движка ИИ, который отвечает в этом канале",
		},
	]
	create_custom_fields({doctype: fields for doctype in TELEGRAM_CHANNELS}, update=True)
```

`after_install` и `after_migrate` — добавить последней строкой вызов `install_telegram_fields()`.

`hooks.py` — добавить в конец:

```python
after_app_install = "habibi_ai.setup.after_app_install"

# Telegram как канал ИИ. Хуки на доктайпы habibi_telegram безвредны там, где
# его нет: событий этих доктайпов на таком сайте просто не бывает.
# Хук Telegram Message добавляется в Task 5 — вместе с функцией, иначе любая
# запись сообщения падала бы на импорте.
doc_events = {
	"Telegram Bot": {"validate": "habibi_ai.channels.telegram.validate_channel"},
	"Telegram Account": {"validate": "habibi_ai.channels.telegram.validate_channel"},
}

doctype_js = {
	"Telegram Bot": "public/js/telegram_channel_ai.js",
	"Telegram Account": "public/js/telegram_channel_ai.js",
}
```

`public/js/telegram_channel_ai.js`:

```javascript
// Выбор ИИ-бота на канале Telegram. Боты живут в движке (Directus), а не во
// Frappe, поэтому поле — Autocomplete со списком, который отдаёт habibi_ai:
// свои боты тенанта плюс общие.
["Telegram Bot", "Telegram Account"].forEach((doctype) => {
	frappe.ui.form.on(doctype, {
		refresh(frm) {
			load_ai_bots(frm);
		},
		ai_enabled(frm) {
			load_ai_bots(frm);
		},
	});
});

function load_ai_bots(frm) {
	if (!frm.doc.ai_enabled || frm.__ai_bots_loaded) return;
	frappe.call("habibi_ai.api.list_bots").then((r) => {
		const options = (r.message || []).map((bot) => ({
			value: String(bot.id),
			label: `${bot.name} (#${bot.id})`,
		}));
		frm.set_df_property("ai_bot", "options", options);
		frm.__ai_bots_loaded = true;
	});
}
```

- [ ] **Step 5: `channels/telegram.py` — константы и проверка канала**

```python
"""Telegram как канал ИИ: входящее → движок → ответ тем же каналом.

habibi_telegram про ИИ не знает: сюда приходят его события (after_insert у
Telegram Message), отсюда вызываются его функции отправки. Решения без
frappe — в decisions.py, здесь только клей.
"""

import frappe

from habibi_ai.channels import decisions
from habibi_ai.engine import BotNotFound
from habibi_ai.habibi_ai.doctype.ai_channel_chat.ai_channel_chat import REASON_MANUAL

PAIR = "AI Channel Chat"
REASON_OPERATOR = "Оператор ответил вручную"
REASON_FORBIDDEN = "Нет прав писать"


def validate_channel(doc, method=None):
	"""Включить ИИ можно только с существующим ботом тенанта.

	Иначе ошибка всплыла бы в фоновой задаче на первом же сообщении клиента —
	в логе, который никто не читает, а клиент остался бы без ответа.
	"""
	if not doc.get("ai_enabled"):
		return

	if not doc.get("ai_bot"):
		frappe.throw("Выберите ИИ-бота, который будет отвечать в этом канале")

	try:
		bot_id = int(doc.ai_bot)
	except (TypeError, ValueError):
		frappe.throw(f"ИИ-бот указан неверно: {doc.ai_bot}")

	from habibi_ai import api

	try:
		api.get_client()._check_bot(bot_id)
	except BotNotFound:
		frappe.throw("ИИ-бот не найден")
```

(`api.get_client()` сам бросает понятную ошибку, если движок не настроен.)

- [ ] **Step 6: Мигрировать и прогнать тесты**

```bash
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost migrate && bench --site dev.localhost clear-cache && bench --site dev.localhost run-tests --module habibi_ai.tests.test_telegram_bridge"
```

Expected: PASS, 7 тестов. `clear-cache` обязателен — README: Frappe держит хуки в redis.

- [ ] **Step 7: Проверить форму руками**

Открыть `http://dev.localhost:8000/app/telegram-bot/new`: внизу секция «ИИ», при включённой галке появляется «ИИ-бот» со списком ботов движка (если движок поднят — `./habibi/dev.sh doctor`).

- [ ] **Step 8: Commit** (репозиторий `habibi_ai`)

```bash
git add habibi_ai/habibi_ai/doctype habibi_ai/setup.py habibi_ai/hooks.py habibi_ai/public \
  habibi_ai/channels/telegram.py habibi_ai/tests/test_telegram_bridge.py
git commit -m "feat(telegram): поля ИИ на каналах Telegram и пара канал+чат"
```

---

### Task 5: Хук, пауза и задача ответа

**Files:**
- Modify: `habibi_ai/habibi_ai/channels/telegram.py`
- Modify: `habibi_ai/habibi_ai/hooks.py` (`doc_events`)
- Modify: `habibi_ai/habibi_ai/tests/test_telegram_bridge.py` (новые классы)

**Interfaces:**
- Consumes: `decisions.*` (Task 3); `api.run_turn`, `api.get_client` (Task 1); `loop.LoopExhausted`, `loop.BadStep` (Task 1); `EngineClient.create_chat(bot_id, external_user) -> {"id": int, ...}`; `ChatNotFound`, `EngineError`; `habibi_telegram.client.send_message(text, from_bot=, chat_id=, automated=)`, `habibi_telegram.user_client.send_message(account, chat_id, text, automated=)` (Task 2); поля Task 2 и Task 4.
- Produces:
  - `on_message_insert(doc, method=None)` — хук
  - `reply_job(channel_doctype, channel_name, chat)` — фоновая задача
  - `pause(channel, chat, reason)`, `get_or_create_pair(channel, chat)`, `pending_messages(channel, chat, last_processed=None)`, `send(channel, chat, text)`
  - `channel` везде — кортеж `(channel_doctype, channel_name)`

- [ ] **Step 1: Написать падающие тесты**

Дописать в `test_telegram_bridge.py`:

```python
from datetime import timedelta

from frappe.utils import now_datetime

from habibi_ai.loop import LoopExhausted

CHAT_ID = "5559100"


def make_chat(chat_id=CHAT_ID):
	name = frappe.db.get_value("Telegram Chat", {"chat_id": chat_id})
	if name:
		return name
	return frappe.get_doc({"doctype": "Telegram Chat", "chat_id": chat_id, "title": "Клиент", "type": "private"}).insert().name


def incoming(chat, message_id, text="Здравствуйте", minutes_ago=0):
	return frappe.get_doc({
		"doctype": "Telegram Message", "chat": chat, "message_id": str(message_id), "direction": "Incoming",
		"content": text, "telegram_bot": BOT, "sent_on": now_datetime() - timedelta(minutes=minutes_ago),
	}).insert(ignore_permissions=True)


def outgoing(chat, message_id, automated):
	return frappe.get_doc({
		"doctype": "Telegram Message", "chat": chat, "message_id": str(message_id), "direction": "Outgoing",
		"content": "ответ", "telegram_bot": BOT, "is_automated": 1 if automated else 0,
	}).insert(ignore_permissions=True)


class _Base(IntegrationTestCase):
	def setUp(self):
		setup.install_telegram_fields()
		make_bot(ai_enabled=1, ai_bot="3", notify_user="Administrator")
		self.chat = make_chat()
		self.channel = ("Telegram Bot", BOT)
		frappe.db.delete(bridge.PAIR, {"telegram_chat": self.chat})
		frappe.db.delete("Telegram Message", {"chat": self.chat})


class TestХук(_Base):
	def test_входящее_ставит_задачу(self):
		with patch("frappe.enqueue") as enqueue:
			incoming(self.chat, 1)
		enqueue.assert_called_once()
		kwargs = enqueue.call_args.kwargs
		self.assertEqual(kwargs["queue"], "long")
		self.assertEqual(kwargs["job_id"], f"ai-reply:Telegram Bot:{BOT}:{self.chat}")
		self.assertTrue(kwargs["deduplicate"])
		self.assertTrue(kwargs["enqueue_after_commit"])

	def test_канал_выключен(self):
		frappe.db.set_value("Telegram Bot", BOT, "ai_enabled", 0)
		with patch("frappe.enqueue") as enqueue:
			incoming(self.chat, 2)
		enqueue.assert_not_called()

	def test_старое_не_ставит(self):
		with patch("frappe.enqueue") as enqueue:
			incoming(self.chat, 3, minutes_ago=10)
		enqueue.assert_not_called()

	def test_ручное_исходящее_ставит_паузу(self):
		outgoing(self.chat, 4, automated=False)
		pair = frappe.get_doc(bridge.PAIR, decisions.pair_name(*self.channel, self.chat))
		self.assertEqual(pair.ai_paused, 1)
		self.assertEqual(pair.paused_reason, bridge.REASON_OPERATOR)

	def test_автоматическое_исходящее_паузы_не_ставит(self):
		outgoing(self.chat, 5, automated=True)
		self.assertFalse(frappe.db.get_value(bridge.PAIR, decisions.pair_name(*self.channel, self.chat), "ai_paused"))

	def test_на_паузе_не_ставит(self):
		outgoing(self.chat, 6, automated=False)
		with patch("frappe.enqueue") as enqueue:
			incoming(self.chat, 7)
		enqueue.assert_not_called()

	def test_ошибка_хука_не_роняет_запись_сообщения(self):
		with patch("habibi_ai.channels.telegram.channel_settings", side_effect=RuntimeError("сбой")):
			doc = incoming(self.chat, 8)
		self.assertTrue(frappe.db.exists("Telegram Message", doc.name))


class TestЗадача(_Base):
	def _run(self, run_turn=None, send_error=None):
		client = Mock()
		client.create_chat = Mock(return_value={"id": 42})
		telegram_api = Mock()
		telegram_api.send_message = Mock(
			side_effect=send_error,
			return_value={"message_id": 900, "chat": {"id": int(CHAT_ID), "type": "private"}, "text": "ответ ИИ"},
		)
		with (
			patch("time.sleep"),
			patch("frappe.enqueue"),
			patch("habibi_ai.api.get_client", return_value=client),
			patch("habibi_ai.api.run_turn", run_turn or Mock(return_value={"response": "ответ ИИ", "debug": []})) as turn,
			patch("habibi_telegram.client.get_bot", return_value=telegram_api),
		):
			bridge.reply_job("Telegram Bot", BOT, self.chat)
		return client, turn, telegram_api

	def test_отвечает_на_всё_накопленное_одним_сообщением(self):
		with patch("frappe.enqueue"):
			incoming(self.chat, 10, "Здравствуйте")
			incoming(self.chat, 11, "[photo]")
			last = incoming(self.chat, 12, "хочу пиццу")
		client, turn, telegram_api = self._run()

		client.create_chat.assert_called_once_with(3, f"telegram:Telegram Bot:{BOT}:{CHAT_ID}")
		args = turn.call_args.args
		self.assertEqual((args[1], args[2], args[3]), (42, "Здравствуйте\nхочу пиццу", 3))
		telegram_api.send_message.assert_called_once()

		pair = frappe.get_doc(bridge.PAIR, decisions.pair_name(*self.channel, self.chat))
		self.assertEqual(pair.engine_chat_id, 42)
		self.assertEqual(pair.last_processed_message, last.name)
		self.assertFalse(pair.ai_paused)
		reply = frappe.get_doc("Telegram Message", {"chat": self.chat, "message_id": "900"})
		self.assertEqual(reply.is_automated, 1)

	def test_старая_история_не_уходит_в_движок(self):
		with patch("frappe.enqueue"):
			incoming(self.chat, 20, "вчерашнее", minutes_ago=60 * 24)
			incoming(self.chat, 21, "сегодняшнее")
		_, turn, _ = self._run()
		self.assertEqual(turn.call_args.args[2], "сегодняшнее")

	def test_нечего_отвечать(self):
		_, turn, telegram_api = self._run()
		turn.assert_not_called()
		telegram_api.send_message.assert_not_called()

	def test_запрет_писать_ставит_паузу(self):
		from habibi_telegram.telegram_api import TelegramAPIError

		with patch("frappe.enqueue"):
			incoming(self.chat, 30)
		self._run(send_error=TelegramAPIError("Forbidden: bot was blocked by the user"))
		pair = frappe.get_doc(bridge.PAIR, decisions.pair_name(*self.channel, self.chat))
		self.assertEqual(pair.ai_paused, 1)
		self.assertEqual(pair.paused_reason, bridge.REASON_FORBIDDEN)

	def test_исчерпан_лимит_оповещает_оператора(self):
		with patch("frappe.enqueue"):
			incoming(self.chat, 40)
		before = frappe.db.count("Notification Log", {"for_user": "Administrator", "document_name": self.chat})
		_, _, telegram_api = self._run(run_turn=Mock(side_effect=LoopExhausted(8)))
		telegram_api.send_message.assert_not_called()
		after = frappe.db.count("Notification Log", {"for_user": "Administrator", "document_name": self.chat})
		self.assertEqual(after, before + 1)

	def test_пауза_проверяется_в_задаче(self):
		with patch("frappe.enqueue"):
			incoming(self.chat, 50)
		bridge.pause(self.channel, self.chat, bridge.REASON_OPERATOR)
		_, turn, _ = self._run()
		turn.assert_not_called()
```

- [ ] **Step 2: Убедиться, что падают**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module habibi_ai.tests.test_telegram_bridge"`
Expected: FAIL — `AttributeError: module 'habibi_ai.channels.telegram' has no attribute 'reply_job'` (и хук ещё не существует — `on_message_insert` не найден при вставке сообщения).

- [ ] **Step 3: Реализовать клей**

В `channels/telegram.py` импорты заменить на:

```python
import time

import frappe
import requests
from frappe.utils import get_datetime, now_datetime

from habibi_ai.channels import decisions
from habibi_ai.engine import BotNotFound, ChatNotFound, EngineError
from habibi_ai.habibi_ai.doctype.ai_channel_chat.ai_channel_chat import REASON_MANUAL
from habibi_ai.loop import LoopExhausted
```

после `REASON_FORBIDDEN` добавить:

```python
# Поле сообщения → доктайп канала. У входящего заполнено ровно одно.
CHANNEL_FIELDS = {"telegram_bot": "Telegram Bot", "telegram_account": "Telegram Account"}

# Люди пишут несколькими сообщениями подряд — ждём, пока допишут
DEBOUNCE_SECONDS = 3
RETRY_DELAY_SECONDS = 30
# Сколько раз подряд отвечать в одной задаче, если пока шла генерация,
# пришло ещё. Больше — это уже не «дописал», а живой диалог, и пусть его
# ведёт следующая задача.
MAX_ROUNDS = 5
LOCK_TIMEOUT = 600
PENDING_LIMIT = 20
```

и в конец модуля:

```python
def channel_of(message):
	"""(доктайп, имя) канала, через который прошло сообщение, или None."""
	for field, doctype in CHANNEL_FIELDS.items():
		if message.get(field):
			return doctype, message.get(field)
	return None


def channel_settings(channel_doctype, channel_name):
	"""Настройки ИИ канала; None, если полей ещё нет (не было миграции)."""
	if not frappe.get_meta(channel_doctype).has_field("ai_enabled"):
		return None
	return frappe.db.get_value(
		channel_doctype, channel_name, ["ai_enabled", "ai_bot", "notify_user"], as_dict=True
	)


def on_message_insert(doc, method=None):
	"""after_insert у Telegram Message.

	Ошибка здесь не должна ронять запись сообщения: хук выполняется внутри
	вебхука и синхронизации, и упавший ИИ стоил бы потерянной истории.
	"""
	try:
		_on_message_insert(doc)
	except Exception:
		frappe.log_error(title="ИИ: разбор сообщения Telegram", message=frappe.get_traceback())


def _on_message_insert(doc):
	channel = channel_of(doc)
	if not channel:
		return

	settings = channel_settings(*channel)
	if not settings or not settings.ai_enabled:
		return

	if doc.direction == "Outgoing":
		# Написал человек — дальше диалог ведёт он, ИИ не перебивает
		if not doc.get("is_automated"):
			pause(channel, doc.chat, REASON_OPERATOR)
		return

	pair = frappe.db.get_value(PAIR, decisions.pair_name(*channel, doc.chat), ["ai_paused"], as_dict=True)
	message = {
		"direction": doc.direction,
		"content": doc.content,
		"sent_on": get_datetime(doc.sent_on) if doc.sent_on else None,
	}
	if decisions.should_reply(message, settings, pair, _sender_is_bot(doc.from_user), now_datetime()):
		enqueue_reply(channel, doc.chat)


def _sender_is_bot(telegram_user):
	return bool(telegram_user and frappe.db.get_value("Telegram User", telegram_user, "is_bot"))


def enqueue_reply(channel, chat):
	"""Одна задача на пару: пока она ждёт или идёт, новых не ставим — новое
	сообщение подберёт она сама (reply_job, следующий раунд).

	enqueue_after_commit: если вебхук откатится, ответа на несуществующее
	сообщение не будет.
	"""
	frappe.enqueue(
		"habibi_ai.channels.telegram.reply_job",
		queue="long",
		job_id=f"ai-reply:{decisions.pair_name(*channel, chat)}",
		deduplicate=True,
		enqueue_after_commit=True,
		channel_doctype=channel[0],
		channel_name=channel[1],
		chat=chat,
	)


def get_or_create_pair(channel, chat):
	name = decisions.pair_name(*channel, chat)
	if frappe.db.exists(PAIR, name):
		return frappe.get_doc(PAIR, name)
	doc = frappe.get_doc(
		{"doctype": PAIR, "channel_doctype": channel[0], "channel_name": channel[1], "telegram_chat": chat}
	)
	try:
		doc.insert(ignore_permissions=True)
	except frappe.DuplicateEntryError:
		# Пару одновременно завела параллельная задача — берём её
		return frappe.get_doc(PAIR, name)
	return doc


def pause(channel, chat, reason):
	"""Выключить ИИ в чате. Уже стоящую паузу не трогаем — первая причина
	важнее: «оператор ответил» не должно затираться «нет прав»."""
	pair = get_or_create_pair(channel, chat)
	if pair.ai_paused:
		return
	frappe.db.set_value(PAIR, pair.name, {"ai_paused": 1, "paused_reason": reason, "paused_on": now_datetime()})


def pending_messages(channel, chat, last_processed=None):
	"""Входящие этого канала в чате после последнего отвеченного.

	Берём последние PENDING_LIMIT и отбрасываем несвежие: на первом сообщении
	пары last_processed пуст, и без этого в движок ушла бы вся история.
	"""
	field = next(f for f, doctype in CHANNEL_FIELDS.items() if doctype == channel[0])
	filters = {"chat": chat, field: channel[1], "direction": "Incoming"}
	if last_processed:
		created = frappe.db.get_value("Telegram Message", last_processed, "creation")
		if created:
			filters["creation"] = (">", created)

	rows = frappe.get_all(
		"Telegram Message",
		filters=filters,
		fields=["name", "direction", "content", "sent_on", "from_user"],
		order_by="creation desc",
		limit=PENDING_LIMIT,
	)
	now = now_datetime()
	return [
		row
		for row in reversed(rows)
		if decisions.is_replyable(
			{"direction": row.direction, "content": row.content, "sent_on": row.sent_on},
			_sender_is_bot(row.from_user),
			now,
		)
	]


def reply_job(channel_doctype, channel_name, chat):
	"""Фоновая задача: ответить на всё, что накопилось в чате.

	От Administrator: задачу ставит вебхук от имени Guest, а инструментам
	нужен понятный пользователь. Сейчас они только читают.
	"""
	frappe.set_user("Administrator")
	channel = (channel_doctype, channel_name)
	time.sleep(DEBOUNCE_SECONDS)

	lock = frappe.cache().lock(
		f"{frappe.local.site}:ai-reply:{decisions.pair_name(*channel, chat)}", timeout=LOCK_TIMEOUT
	)
	if not lock.acquire(blocking=True, blocking_timeout=LOCK_TIMEOUT):
		return

	try:
		for _round in range(MAX_ROUNDS):
			if not _reply_round(channel, chat):
				break
	finally:
		try:
			lock.release()
		except Exception:
			# Истёк по таймауту — отпускать нечего
			pass


def _reply_round(channel, chat):
	"""Один ответ на накопленное. True — ответ ушёл, стоит проверить ещё раз."""
	# Свежий снимок: в REPEATABLE READ задача иначе не увидит ни сообщений,
	# пришедших за время генерации, ни паузы, выставленной оператором
	frappe.db.rollback()

	settings = channel_settings(*channel)
	if not settings or not settings.ai_enabled or not settings.ai_bot:
		return False

	pair = get_or_create_pair(channel, chat)
	if pair.ai_paused:
		return False

	pending = pending_messages(channel, chat, pair.last_processed_message)
	if not pending:
		return False

	text = decisions.combine(row.content for row in pending)
	last = pending[-1].name

	try:
		reply = _generate(pair, int(settings.ai_bot), text, chat)
	except LoopExhausted as e:
		_report(channel, chat, str(e), notify_user=settings.notify_user)
		_mark_processed(pair, last)
		return False
	except Exception:
		# Клиенту ничего не пишем: пусть лучше ответит оператор, чем бот
		# пришлёт «ошибка»
		_report(channel, chat, frappe.get_traceback())
		_mark_processed(pair, last)
		return False

	if not (reply or "").strip():
		_mark_processed(pair, last)
		return False

	try:
		send(channel, chat, reply)
	except Exception as e:
		if decisions.is_write_forbidden(str(e)):
			pause(channel, chat, REASON_FORBIDDEN)
		_report(channel, chat, frappe.get_traceback())
		_mark_processed(pair, last)
		return False

	_mark_processed(pair, last)
	return True


def _generate(pair, bot_id, text, chat):
	"""Ход агента с одной повторной попыткой на сбой движка.

	Чат движка мог быть удалён в админке — тогда заводим новый: история
	переписки в движке потеряна, но клиент ответ получит.
	"""
	from habibi_ai import api

	client = api.get_client()
	for attempt in (1, 2):
		try:
			engine_chat_id = _engine_chat(client, pair, bot_id, chat)
			return api.run_turn(client, engine_chat_id, text, bot_id)["response"]
		except ChatNotFound:
			if attempt == 2:
				raise
			pair.db_set("engine_chat_id", None)
			frappe.db.commit()
		except (EngineError, requests.RequestException):
			if attempt == 2:
				raise
			time.sleep(RETRY_DELAY_SECONDS)


def _engine_chat(client, pair, bot_id, chat):
	if pair.engine_chat_id:
		return pair.engine_chat_id
	chat_id = frappe.db.get_value("Telegram Chat", chat, "chat_id")
	created = client.create_chat(bot_id, decisions.external_user(pair.channel_doctype, pair.channel_name, chat_id))
	pair.db_set("engine_chat_id", created["id"])
	# Сразу: следующий раунд начинается с rollback, и без коммита чат в
	# движке заводился бы заново на каждое сообщение
	frappe.db.commit()
	return created["id"]


def send(channel, chat, text):
	"""Ответ тем же каналом, с пометкой «не человек» — иначе наш же ответ
	поставил бы чат на паузу."""
	chat_id = frappe.db.get_value("Telegram Chat", chat, "chat_id")
	if channel[0] == "Telegram Bot":
		from habibi_telegram.client import send_message

		send_message(text, from_bot=channel[1], chat_id=chat_id, automated=True)
	else:
		from habibi_telegram.user_client import send_message

		send_message(channel[1], chat_id, text, automated=True)


def _mark_processed(pair, last):
	frappe.db.set_value(PAIR, pair.name, "last_processed_message", last)
	frappe.db.commit()


def _report(channel, chat, detail, notify_user=None):
	frappe.log_error(title=f"ИИ не ответил в Telegram ({channel[1]})", message=f"Чат: {chat}\n\n{detail}")
	if notify_user:
		frappe.get_doc(
			{
				"doctype": "Notification Log",
				"for_user": notify_user,
				"type": "Alert",
				"subject": f"ИИ не смог ответить в чате {chat}",
				"email_content": detail,
				"document_type": "Telegram Chat",
				"document_name": chat,
			}
		).insert(ignore_permissions=True)
	frappe.db.commit()
```

В `hooks.py` в `doc_events` добавить первой строкой (комментарий «Хук Telegram Message добавляется в Task 5…» удалить):

```python
	"Telegram Message": {"after_insert": "habibi_ai.channels.telegram.on_message_insert"},
```

Замечание про тесты: `_reply_round` делает `frappe.db.rollback()` и `commit()`, поэтому данные тестов коммитятся. `_Base.setUp` чистит пары и сообщения тестового чата — тесты от этого не зависят друг от друга.

- [ ] **Step 4: Прогнать тесты**

```bash
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost clear-cache && bench --site dev.localhost run-tests --module habibi_ai.tests.test_telegram_bridge"
```

Expected: PASS, 20 тестов. Если `test_отвечает_на_всё_накопленное...` падает на `reply.is_automated` — проверить, что Task 2 передаёт `automated` в `log_outgoing_message`.

- [ ] **Step 5: Прогнать все тесты `habibi_ai`**

```bash
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && env/bin/python -m unittest habibi_ai.tests.test_loop habibi_ai.tests.test_engine habibi_ai.tests.test_api habibi_ai.tests.test_tools habibi_ai.tests.test_channel_decisions -v && bench --site dev.localhost run-tests --app habibi_ai"
```

Expected: PASS все.

- [ ] **Step 6: Проверка в dev руками**

1. В `http://dev.localhost:8000/app/telegram-bot` завести бота с реальным тестовым токеном (`@BotFather`), включить «Использовать ИИ для ответа», выбрать ИИ-бота.
2. Вебхук на dev не дойдёт (локальный хост). Эмулировать апдейт:

```bash
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost execute '__import__(\"habibi_telegram.dispatcher\", fromlist=[\"x\"]).process_update' --kwargs '{\"telegram_bot\": \"<имя бота>\", \"update\": {\"update_id\": 1, \"message\": {\"message_id\": 1, \"date\": '\$(date +%s)', \"chat\": {\"id\": <ваш telegram id>, \"type\": \"private\"}, \"from\": {\"id\": <ваш telegram id>, \"is_bot\": false, \"first_name\": \"Тест\"}, \"text\": \"Что у вас есть?\"}}}' && bench --site dev.localhost execute frappe.db.commit"
```

3. Убедиться, что в `queue-long` воркере dev прошла задача (`bench worker` должен быть запущен — `./habibi/dev.sh up`), и в личку от бота пришёл ответ ИИ; в `AI Channel Chat` появилась пара с `engine_chat_id`.

- [ ] **Step 7: Commit** (репозиторий `habibi_ai`)

```bash
git add habibi_ai/channels/telegram.py habibi_ai/hooks.py habibi_ai/tests/test_telegram_bridge.py
git commit -m "feat(telegram): ИИ отвечает во входящих Telegram — бот и личный аккаунт"
```

---

### Task 6: Слушатель MTProto

**Files:**
- Create: `habibi_telegram/habibi_telegram/listener.py`
- Modify: `habibi_telegram/habibi_telegram/user_client.py` (`sync_all_accounts`, `listen`)
- Modify: `habibi_telegram/habibi_telegram/commands/__init__.py`
- Create: `habibi_telegram/habibi_telegram/tests/test_listener.py`
- Create: `habibi_docker/habibi/overrides/compose.telegram-listener.yaml`

**Interfaces:**
- Produces:
  - `listener.HEARTBEAT_EVERY = 30`, `listener.HEARTBEAT_TTL = 90`, `listener.RESCAN_EVERY = 60`
  - `listener.mark_alive(account: str)`, `listener.is_alive(account: str) -> bool`, `listener.should_listen(account: str) -> bool`, `listener.run_all()`
  - `user_client.listen(account, forever=True, seconds=None, heartbeat=False)`
  - команда `bench telegram listen-all`

- [ ] **Step 1: Написать падающие тесты**

`habibi_telegram/habibi_telegram/tests/test_listener.py`:

```python
"""Слушатель и cron не должны работать с одной сессией одновременно.

Одна сессия Telethon в двух соединениях — повод для Telegram разорвать её
(AUTH_KEY_DUPLICATED). Поэтому cron пропускает аккаунт, пока жив heartbeat
слушателя, и возвращается к нему сам, когда heartbeat протух.
"""

from unittest.mock import patch

import frappe
from frappe.tests import IntegrationTestCase

from habibi_telegram import listener, user_client

TITLE = "listener-test-account"


class TestHeartbeat(IntegrationTestCase):
	def setUp(self):
		if not frappe.db.exists("Telegram Account", TITLE):
			frappe.get_doc({
				"doctype": "Telegram Account", "title": TITLE, "phone": "+70000000001",
				"api_id": "1", "api_hash": "x",
			}).insert()
		frappe.db.set_value("Telegram Account", TITLE, {"enabled": 1, "sync_enabled": 1, "status": "Connected"})
		# should_listen делает rollback, чтобы видеть свежие данные, — без
		# коммита он откатил бы и эту подготовку
		frappe.db.commit()
		frappe.cache().delete_value(listener._heartbeat_key(TITLE))

	def test_без_слушателя_cron_синхронизирует(self):
		with patch("frappe.enqueue") as enqueue:
			user_client.sync_all_accounts()
		accounts = [c.kwargs["account"] for c in enqueue.call_args_list]
		self.assertIn(TITLE, accounts)

	def test_живой_слушатель_отключает_cron(self):
		listener.mark_alive(TITLE)
		self.assertTrue(listener.is_alive(TITLE))
		with patch("frappe.enqueue") as enqueue:
			user_client.sync_all_accounts()
		accounts = [c.kwargs["account"] for c in enqueue.call_args_list]
		self.assertNotIn(TITLE, accounts)

	def test_слушать_только_подключённые(self):
		self.assertTrue(listener.should_listen(TITLE))
		frappe.db.set_value("Telegram Account", TITLE, "sync_enabled", 0)
		frappe.db.commit()
		self.assertFalse(listener.should_listen(TITLE))
```

- [ ] **Step 2: Убедиться, что падают**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module habibi_telegram.tests.test_listener"`
Expected: FAIL — `ImportError: cannot import name 'listener'`.

- [ ] **Step 3: `listener.py`**

```python
"""
Постоянные соединения MTProto для всех аккаунтов всех сайтов.

`bench telegram listen-all` — один процесс на весь бенч: по потоку на каждый
подключённый аккаунт, раз в минуту список перечитывается. Без него личные
аккаунты получают сообщения раз в минуту через getDifference, а с ним —
сразу, как и боты с вебхуком.

Пока слушатель жив, он раз в HEARTBEAT_EVERY пишет heartbeat в redis, и cron
этот аккаунт пропускает: одна сессия Telethon в двух соединениях — повод для
Telegram её разорвать. Упал слушатель — heartbeat протух, и через минуту
аккаунт снова на cron: медленнее, но без потерь.
"""

import threading
import time

import frappe
from frappe.utils import get_sites

HEARTBEAT_EVERY = 30
HEARTBEAT_TTL = 90
RESCAN_EVERY = 60


def _heartbeat_key(account: str) -> str:
	# Префикс сайта redis-обёртка frappe добавляет сама
	return f"telegram-listener:{account}"


def mark_alive(account: str):
	frappe.cache().set_value(_heartbeat_key(account), 1, expires_in_sec=HEARTBEAT_TTL)


def is_alive(account: str) -> bool:
	return bool(frappe.cache().get_value(_heartbeat_key(account)))


def should_listen(account: str) -> bool:
	"""Аккаунт всё ещё включён и подключён.

	rollback — чтобы увидеть свежие данные: процесс живёт часами в одной
	транзакции, и в REPEATABLE READ выключенный на форме аккаунт выглядел бы
	включённым вечно.
	"""
	frappe.db.rollback()
	row = frappe.db.get_value("Telegram Account", account, ["enabled", "sync_enabled", "status"], as_dict=True)
	return bool(row and row.enabled and row.sync_enabled and row.status == "Connected")


def run_all():
	threads = {}

	while True:
		for site in get_sites():
			for account in _accounts_to_listen(site):
				key = (site, account)
				if key in threads and threads[key].is_alive():
					continue
				# Упавший поток перезапускается здесь же — не чаще раза в RESCAN_EVERY
				thread = threading.Thread(
					target=_listen_one, args=(site, account), name=f"telegram:{site}:{account}", daemon=True
				)
				thread.start()
				threads[key] = thread

		time.sleep(RESCAN_EVERY)


def _accounts_to_listen(site: str) -> list[str]:
	try:
		frappe.init(site=site)
		frappe.connect()
		if "habibi_telegram" not in frappe.get_installed_apps():
			return []
		return frappe.get_all(
			"Telegram Account",
			filters={"enabled": 1, "sync_enabled": 1, "status": "Connected"},
			pluck="name",
		)
	except Exception as e:
		# Сайт в миграции или без базы — не повод ронять слушателей остальных
		print(f"[telegram listen-all] {site}: {e}", flush=True)
		return []
	finally:
		frappe.destroy()


def _listen_one(site: str, account: str):
	frappe.init(site=site)
	frappe.connect()
	try:
		from habibi_telegram.user_client import listen

		listen(account, forever=True, heartbeat=True)
	except Exception:
		frappe.log_error(title=f"Telegram listener stopped ({account})", message=frappe.get_traceback())
		frappe.db.commit()
	finally:
		frappe.destroy()
```

- [ ] **Step 4: `user_client.py`**

В `sync_all_accounts` цикл заменить на:

```python
	from habibi_telegram import listener

	for name in accounts:
		# Аккаунт держит слушатель — второе соединение той же сессией
		# Telegram может счесть угоном и разорвать обе
		if listener.is_alive(name):
			continue

		frappe.enqueue(
			"habibi_telegram.user_client.sync_account",
			queue="long",
			account=name,
			job_id=f"telegram-sync-{name}",
			deduplicate=True,
		)
```

`listen` — сигнатура `def listen(account, forever: bool = True, seconds: int = None, heartbeat: bool = False):`, в докстринг — абзац:

```
	heartbeat — для listen-all: отмечаться в redis, чтобы cron не открывал
	второе соединение, и отключиться самому, когда аккаунт выключат на форме.
```

внутри `_op` перед `if forever:` добавить:

```python
		if heartbeat:
			import asyncio

			from habibi_telegram import listener

			async def _beat():
				while True:
					listener.mark_alive(account.name)
					await asyncio.sleep(listener.HEARTBEAT_EVERY)
					if not listener.should_listen(account.name):
						await client.disconnect()
						return

			asyncio.get_running_loop().create_task(_beat())
```

- [ ] **Step 5: Команда**

В `commands/__init__.py` перед `telegram.add_command(list_bots)`:

```python
@click.command("listen-all")
def listen_all():
	"""
	Слушать все подключённые аккаунты всех сайтов бенча.

	Для отдельного сервиса в compose: один процесс на бенч, аккаунты
	подхватываются и отпускаются сами, раз в минуту.
	"""
	from habibi_telegram.listener import run_all

	click.echo("Listening for all Telegram accounts. Ctrl-C to stop.")
	try:
		run_all()
	except KeyboardInterrupt:
		click.echo("Stopped")
```

и в конец списка регистраций — `telegram.add_command(listen_all)`.

- [ ] **Step 6: Прогнать тесты**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module habibi_telegram.tests.test_listener && bench --site dev.localhost run-tests --module habibi_telegram.tests.test_message_origin"`
Expected: PASS.

- [ ] **Step 7: Проверить команду**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && timeout 5 bench telegram listen-all; echo exit=\$?"`
Expected: строка `Listening for all Telegram accounts. Ctrl-C to stop.`, затем `exit=124` (прервано `timeout`), без трейсбеков.

- [ ] **Step 8: Сервис в compose**

`habibi_docker/habibi/overrides/compose.telegram-listener.yaml`:

```yaml
# Слушатель MTProto: мгновенный приём сообщений личных аккаунтов Telegram.
#
# Без него аккаунты синхронизируются cron'ом раз в минуту (updates.getDifference)
# — работает, но ответ ИИ приходит с задержкой до минуты. Бот с вебхуком от
# этого сервиса не зависит.
#
# Один процесс на бенч: `bench telegram listen-all` сам находит сайты с
# habibi_telegram и подключённые аккаунты, раз в минуту перечитывает список.
# Пока слушатель жив, cron аккаунт пропускает (heartbeat в redis), упал —
# через минуту всё возвращается на cron.
#
# Реплика строго одна: два слушателя открыли бы одну сессию дважды, и
# Telegram разорвал бы её.
#
# Подключать в COMPOSE_FILE после compose.yaml и оверрайдов redis/mariadb.

services:
  telegram-listener:
    image: ${CUSTOM_IMAGE:?CUSTOM_IMAGE not set}:${CUSTOM_TAG:?CUSTOM_TAG not set}
    pull_policy: ${PULL_POLICY:-always}
    restart: ${RESTART_POLICY:-unless-stopped}
    platform: linux/amd64
    command: bench telegram listen-all
    volumes:
      - sites:/home/frappe/frappe-bench/sites
    depends_on:
      configurator:
        condition: service_completed_successfully
```

Проверить синтаксис с продовым набором файлов (локально, `.env` не нужен — подставляем заглушки):

```bash
CUSTOM_IMAGE=x CUSTOM_TAG=y docker compose -f compose.yaml -f overrides/compose.redis.yaml -f habibi/overrides/compose.telegram-listener.yaml config --services | grep telegram-listener
```

Expected: `telegram-listener`.

- [ ] **Step 9: Commit** (два репозитория)

```bash
cd /Users/fsa/Projects/habibi/habibi_telegram
git add habibi_telegram/listener.py habibi_telegram/user_client.py habibi_telegram/commands/__init__.py habibi_telegram/tests/test_listener.py
git commit -m "feat: bench telegram listen-all — мгновенный приём у личных аккаунтов"

cd /Users/fsa/Projects/habibi/habibi_docker
git checkout -b feat/telegram-ai-replies
git add habibi/overrides/compose.telegram-listener.yaml
git commit -m "feat(compose): сервис telegram-listener для личных аккаунтов Telegram"
```

---

### Task 7: Релиз и сквозная проверка на `client1.example.com`

Каждый шаг этой задачи трогает прод — **перед каждым спросить подтверждение у пользователя**.

**Files:** нет изменений кода.

- [ ] **Step 1: Слить ветки и запушить приложения**

После ревью: влить `feat/telegram-ai-replies` в `master` (`habibi_telegram`) и `main` (`habibi_ai`, `habibi_docker`), запушить. Образ собирается из веток `apps.json` (`habibi/apps.json`), поэтому сначала приложения, потом тег.

- [ ] **Step 2: Релиз по тегу** (CLAUDE.md)

```bash
cd /Users/fsa/Projects/habibi/habibi_docker
git push
git tag v1.3.5 && git push --tags
```

Номер — следующий за текущим `v1.3.4` (`ssh habibi 'cd habibi_docker && docker compose ps --format "{{.Image}}" | grep habibi:'`). Дождаться зелёного GitHub Actions.

- [ ] **Step 3: Миграция и кэш на сайтах**

```bash
ssh habibi 'cd habibi_docker && for s in erp.habibi-erp.com naqwa.habibi-erp.com client1.example.com; do docker compose exec -T backend bench --site $s migrate && docker compose exec -T backend bench --site $s clear-cache; done'
```

Expected: без ошибок. На `erp` и `naqwa` появятся поля «ИИ» у каналов (галка по умолчанию выключена — поведение не меняется).

- [ ] **Step 4: Сквозная проверка — бот**

1. Поставить `habibi_telegram` на `client1.example.com` через `/app/site-manager` админки (или `bench --site client1.example.com install-app habibi_telegram`).
2. Завести тестового бота у `@BotFather`, создать Telegram Bot на client1, `Set Webhook`, включить ИИ, выбрать ИИ-бота.
3. Написать боту «Что у вас есть?» → пришёл ответ ИИ; в `AI Channel Chat` пара с `engine_chat_id`; в Directus — чат `telegram:Telegram Bot:...`; у ответа `is_automated = 1`.
4. Три сообщения подряд быстро → один ответ.
5. Ответить вручную из консоли чатов → пара на паузе «Оператор ответил вручную»; следующее сообщение клиента без ответа ИИ.
6. Снять паузу в AI Channel Chat → ИИ снова отвечает.

- [ ] **Step 5: Сквозная проверка — личный аккаунт, без слушателя**

Подключить тестовый личный аккаунт на client1, включить ИИ. Написать ему с другого аккаунта → ответ ИИ в пределах ~1 минуты. Ответить с телефона вручную → пауза.

- [ ] **Step 6: Включить слушатель**

Добавить в `COMPOSE_FILE` в `/home/ubuntu/habibi_docker/.env` в конец `:habibi/overrides/compose.telegram-listener.yaml`, затем:

```bash
ssh habibi 'cd habibi_docker && docker compose up -d telegram-listener && sleep 90 && docker compose logs --tail 20 telegram-listener'
```

Expected: `Listening for all Telegram accounts.`, без трейсбеков. Написать тестовому аккаунту → ответ ИИ за секунды.

- [ ] **Step 7: Итог пользователю**

Сообщить: что выкачено (тег), где включается ИИ, что проверено, что `client1` остаётся с тестовым ботом/аккаунтом (или удалить их — спросить).
