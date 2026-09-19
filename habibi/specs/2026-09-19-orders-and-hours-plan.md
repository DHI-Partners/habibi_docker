# Приём заказов и режим работы — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Бот оформляет заказ черновиком Sales Order по расчёту, который посчитал ERP и услышал клиент, и отвечает про режим работы из справочника, а не из промпта.

**Architecture:** `run_turn` собирает серверный контекст хода (`turn_id`, чат движка, канальный чат) и отдаёт его инструментам, объявившим `context=True`. `quote_order` считает несохранённый Sales Order средствами ERPNext и сохраняет расчёт `AI Order Quote`; `create_order` принимает только номер расчёта и отказывает в том же ходе. Правила без frappe (`order_rules.py`, `schedule.py`) покрыты быстрыми тестами, связка с ERP — интеграционными на `dev.localhost`.

**Tech Stack:** Frappe v16 / ERPNext v16 (Python 3.14, `unittest`, `frappe.tests.IntegrationTestCase`), Directus-движок `habibi_ai_engine` (не меняется), MCP `directus-habibi-ai` для промптов.

**Spec:** `habibi/specs/2026-09-19-orders-and-hours-design.md` — читать вместе с планом.

## Global Constraints

- Отступы — табы, `line-length = 110`, как в `pyproject.toml` приложения.
- Комментарии и докстринги — по-русски, объясняют «почему», в стиле соседнего кода.
- Имена тестов — по-русски (`test_заказ_в_том_же_ходе_отклоняется`), как в `habibi_ai/tests`.
- `engine.py`, `loop.py`, `channels/decisions.py`, **`order_rules.py`, `schedule.py` не импортируют frappe**.
- Инструмент всегда возвращает строку. Отказ — строка, которая говорит модели, что делать дальше.
- Итог, налог и цены — только из ERP. Сумма, названная моделью, не принимается ни в каком виде.
- Клиент и чат — только из серверного контекста, никогда из аргументов модели.
- Компания заказа — только из `Habibi AI Settings.company`; `Global Defaults` не используется.
- Срок жизни расчёта — 30 минут. Количество позиции — целое от 1 до 50. Телефон — 10–15 цифр.
- Позиция доставки — `SRV-DELIVERY`.
- Заказ вставляется без проведения (`docstatus = 0`); состояние `New` ставит воркфлоу сайта.
- При изменении JSON доктайпа обязательно обновлять `"modified"` — иначе `bench migrate` изменения не подхватит.
- Ветки: `habibi_ai` — фича-ветка `feat/orders-and-hours` от `main`; `habibi_docker` — `main`.

## Как запускать команды

Все команды — из `/Users/fsa/Projects/habibi/habibi_docker`. Dev-бенч живёт в devcontainer:

```bash
DC="docker compose -f .devcontainer/docker-compose.yml"
# быстрые тесты без сайта:
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench/apps/habibi_ai && ../../env/bin/python -m unittest <модуль> -v"
# тесты на сайте:
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module <модуль>"
```

Если контейнер не поднят: `./habibi/dev.sh up`. Docker Desktop должен быть запущен.

## Карта файлов

Все пути `habibi_ai` — от `/Users/fsa/Projects/habibi/habibi_ai/`.

| Файл | Что | Задача |
|---|---|---|
| `habibi_ai/tools/__init__.py` | `tool(..., context=False)`, `execute(name, args, context=None)` | 1 |
| `habibi_ai/api.py` | `run_turn(..., channel_chat=None)` собирает контекст | 1 |
| `habibi_ai/channels/telegram.py` | `_generate` передаёт `channel_chat` | 1 |
| `habibi_ai/schedule.py` | новый, без frappe: интервалы, «открыто ли», текст недели | 2 |
| `habibi_ai/habibi_ai/doctype/habibi_ai_settings/` | новый single: `company` | 3 |
| `habibi_ai/habibi_ai/doctype/working_hours*/` | новые: справочник и две child-таблицы | 3 |
| `habibi_ai/tools/hours.py` | новый: `get_working_hours`, `closed_warning` | 3 |
| `habibi_ai/order_rules.py` | новый, без frappe: позиции, зона, телефон, проверка расчёта, текст | 4 |
| `habibi_ai/tools/menu.py` | + `valid_prices`, `sellable_catalog` | 5 |
| `habibi_ai/habibi_ai/doctype/ai_order_quote*/` | новые: расчёт и его строки | 6 |
| `habibi_ai/customers.py` | новый: клиент по чату/телефону, создание, привязка | 6 |
| `habibi_ai/tools/orders.py` | новый: `quote_order`, `create_order` | 6, 7 |
| `habibi_ai/setup.py` | + `install_order_source_option` | 7 |
| `habibi_ai/hooks.py` | `required_apps` + `erpnext` | 7 |
| `habibi_ai/tests/test_tools.py` | + контекст | 1 |
| `habibi_ai/tests/test_api.py`, `test_telegram_bridge.py` | правка под контекст | 1 |
| `habibi_ai/tests/test_schedule.py` | новый | 2 |
| `habibi_ai/tests/test_hours.py` | новый | 3 |
| `habibi_ai/tests/test_order_rules.py` | новый | 4 |
| `habibi_ai/tests/test_orders.py` | новый, интеграционный | 8 |
| `habibi_docker/habibi/docs/agent-core.md` | раздел 10 и «Инструмент, который пишет» | 9 |

---

### Task 0: Ветка и окружение

**Files:** нет изменений кода.

- [ ] **Step 1: Ветка**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai && git checkout main && git pull && git checkout -b feat/orders-and-hours
```

- [ ] **Step 2: Поднять dev-бенч и проверить ERPNext на сайте**

```bash
cd /Users/fsa/Projects/habibi/habibi_docker && ./habibi/dev.sh up
DC="docker compose -f .devcontainer/docker-compose.yml"
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost list-apps"
```

Expected: в списке `erpnext`, `habibi_ai`, `habibi_telegram`. Если `erpnext` нет:

```bash
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost install-app erpnext"
```

- [ ] **Step 3: Базовая линия тестов**

```bash
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --app habibi_ai"
```

Expected: всё зелёное. Если что-то красное до наших правок — записать, какие тесты, и не чинить их в этом плане.

---

### Task 1: Контекст хода для инструментов

**Files:**
- Modify: `habibi_ai/tools/__init__.py`
- Modify: `habibi_ai/api.py` (`run_turn`)
- Modify: `habibi_ai/channels/telegram.py` (`_generate`)
- Test: `habibi_ai/tests/test_tools.py`, `habibi_ai/tests/test_api.py`, `habibi_ai/tests/test_telegram_bridge.py`

**Interfaces:**
- Produces: `tools.tool(name, description, input_schema, context=False)`; `tools.execute(name, args, context=None) -> str`; инструмент с `context=True` вызывается как `run(context=<dict>, **args)`. Контекст: `{"turn_id": str, "engine_chat_id": int, "channel_chat": tuple[str, str] | None}`. `api.run_turn(client, chat_id, message, bot_id=None, debug=False, channel_chat=None)`.

- [ ] **Step 1: Падающие тесты реестра** — дописать в конец `habibi_ai/tests/test_tools.py`:

```python
class TestКонтекст(unittest.TestCase):
	"""Контекст хода кладёт сервер. Модель не может ни увидеть его, ни подменить:
	из контекста инструмент заказа узнаёт чат, а значит — клиента."""

	def setUp(self):
		self._saved = dict(tools._REGISTRY)

		@tools.tool("_с_контекстом", "тест", {"type": "object", "properties": {}}, context=True)
		def _with(context, x=None):
			return f"{context.get('turn_id')}|{x}"

		@tools.tool("_без_контекста", "тест", {"type": "object", "properties": {}})
		def _without(x=None):
			return f"{x}"

	def tearDown(self):
		tools._REGISTRY.clear()
		tools._REGISTRY.update(self._saved)

	def test_инструмент_с_контекстом_получает_серверный(self):
		self.assertEqual(tools.execute("_с_контекстом", {"x": 1}, {"turn_id": "t1"}), "t1|1")

	def test_context_от_модели_отбрасывается(self):
		result = tools.execute("_с_контекстом", {"context": {"turn_id": "чужой"}}, {"turn_id": "t1"})
		self.assertEqual(result, "t1|None")

	def test_инструмент_без_объявления_контекста_его_не_получает(self):
		self.assertEqual(tools.execute("_без_контекста", {"x": 2}, {"turn_id": "t1"}), "2")

	def test_контекст_не_виден_в_определениях(self):
		definition = tools.definitions(["_с_контекстом"])[0]
		self.assertNotIn("context", definition)
		self.assertNotIn("run", definition)
```

- [ ] **Step 2: Убедиться, что падают**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench/apps/habibi_ai && ../../env/bin/python -m unittest habibi_ai.tests.test_tools -v"`
Expected: FAIL — `tool() got an unexpected keyword argument 'context'`.

- [ ] **Step 3: Реализация в `habibi_ai/tools/__init__.py`** — заменить `tool`, `definitions`, `execute`:

```python
def tool(name, description, input_schema, context=False):
	"""Объявляет функцию инструментом, видимым модели.

	context=True — инструмент получает серверный контекст хода аргументом
	context: чей это чат и какой это ход. Модели он не виден и подменить его
	она не может — из него инструмент заказа узнаёт клиента.
	"""

	def decorator(func):
		_REGISTRY[name] = {
			"name": name,
			"description": description,
			"input_schema": input_schema,
			"run": func,
			"context": context,
		}
		return func

	return decorator


def definitions(names):
	"""Описания для модели — только по запрошенным именам.

	Неизвестное имя пропускается: конфигурацию правят без ревью, и опечатка не
	повод обрывать диалог. Движок такие имена показывает в трассировке.
	"""
	return [
		{k: v for k, v in _REGISTRY[n].items() if k not in ("run", "context")}
		for n in names
		if n in _REGISTRY
	]


def execute(name, args, context=None):
	"""Исполняет инструмент, всегда возвращая строку для модели.

	Отказ — тоже строка, а не исключение: модель должна увидеть причину и
	исправиться сама. Исключение оборвало бы весь ход.

	Ключ context из аргументов модели выбрасывается до вызова: иначе модель
	могла бы подложить чужой чат туда, где инструмент ждёт серверный.
	"""
	entry = _REGISTRY.get(name)
	if entry is None:
		return f"Инструмент {name} недоступен. Доступные: {', '.join(sorted(_REGISTRY))}"

	args = {k: v for k, v in (args or {}).items() if k != "context"}
	try:
		if entry["context"]:
			return entry["run"](context=context or {}, **args)
		return entry["run"](**args)
	except TypeError as e:
		return f"Неверные аргументы для {name}: {e}"
	except Exception as e:
		return f"Инструмент {name} завершился ошибкой: {e}"
```

- [ ] **Step 4: Тесты реестра зелёные**

Run: тот же, что в Step 2. Expected: PASS.

- [ ] **Step 5: Падающие тесты `run_turn`** — в `habibi_ai/tests/test_api.py` в `test_вызов_инструмента_исполняется_и_цикл_продолжается` заменить строку `run.assert_called_once_with("get_menu", {})` на:

```python
		run.assert_called_once()
		name, args, context = run.call_args.args
		self.assertEqual((name, args), ("get_menu", {}))
		# Консоль отладки: канального чата нет, клиента узнают только по телефону
		self.assertEqual(context["engine_chat_id"], 1)
		self.assertIsNone(context["channel_chat"])
		self.assertTrue(context["turn_id"])
```

И добавить в тот же класс (рядом с этим тестом; хелпер `_client_с_шагами` уже есть в классе):

```python
	def test_каждый_ход_получает_свой_turn_id(self):
		# create_order отказывает в том же ходе, что quote_order. Совпади
		# turn_id у двух ходов — отказ сработал бы и там, где клиент уже
		# ответил «да».
		seen = []
		for _ in range(2):
			client = self._client_с_шагами([
				{"type": "tool_use", "id": "t1", "name": "get_menu", "input": {}},
				{"type": "text", "content": "ок"},
			])
			with patch("habibi_ai.tools.execute", return_value="меню") as run:
				api.run_turn(client, 7, "что есть?", channel_chat=("Telegram Chat", "c1"))
			seen.append(run.call_args.args[2])
		self.assertNotEqual(seen[0]["turn_id"], seen[1]["turn_id"])
		self.assertEqual(seen[0]["channel_chat"], ("Telegram Chat", "c1"))
		self.assertEqual(seen[0]["engine_chat_id"], 7)
```

В `habibi_ai/tests/test_telegram_bridge.py`, в `test_отвечает_на_всё_накопленное_одним_сообщением`, после строки `self.assertEqual((args[1], args[2], args[3]), (42, "Здравствуйте\nхочу пиццу", 3))` добавить:

```python
		self.assertEqual(turn.call_args.kwargs["channel_chat"], ("Telegram Chat", self.chat))
```

- [ ] **Step 6: Убедиться, что падают**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module habibi_ai.tests.test_api"` и то же для `habibi_ai.tests.test_telegram_bridge`.
Expected: FAIL — `run_turn() got an unexpected keyword argument 'channel_chat'` и `KeyError: 'channel_chat'`.

- [ ] **Step 7: Реализация `run_turn`** — в `habibi_ai/api.py` добавить `import uuid` к импортам и заменить `run_turn`:

```python
def run_turn(client, chat_id, message, bot_id=None, debug=False, channel_chat=None):
	"""Один ход агента — общий для браузера и каналов.

	Ошибки движка и цикла пробрасываются как есть: браузеру их переводит в
	человеческий текст call(), а канальный адаптер решает сам — повторить,
	поставить чат на паузу или оповестить оператора.

	Лимит задаётся полем бота; бот тот же, что и в step: явный bot_id, иначе
	бот чата.

	context собирается здесь, на сервере, и уходит только инструментам: чей
	это чат (channel_chat — канальный, если ход пришёл из канала) и какой это
	ход. turn_id новый на каждый ход — по нему create_order узнаёт, что
	клиент успел ответить после расчёта.
	"""
	max_loop = loop.resolve_max_loop(client.get_max_loop(chat_id, bot_id), MAX_LOOP)
	offered = _tool_names()
	context = {"turn_id": uuid.uuid4().hex, "engine_chat_id": chat_id, "channel_chat": channel_chat}
	return loop.run(
		lambda text, **kwargs: client.step(chat_id, text, bot_id, **kwargs),
		message,
		offered=offered,
		definitions=tools.definitions(offered),
		execute=lambda name, args: tools.execute(name, args, context),
		max_loop=max_loop,
		debug=debug,
	)
```

В `habibi_ai/channels/telegram.py`, в `_generate`, заменить строку вызова:

```python
			return api.run_turn(
				client, engine_chat_id, text, bot_id, channel_chat=("Telegram Chat", chat)
			)["response"]
```

- [ ] **Step 8: Все тесты приложения зелёные**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --app habibi_ai"`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai
git add habibi_ai/tools/__init__.py habibi_ai/api.py habibi_ai/channels/telegram.py habibi_ai/tests/test_tools.py habibi_ai/tests/test_api.py habibi_ai/tests/test_telegram_bridge.py
git commit -m "feat(tools): серверный контекст хода — чат и turn_id для инструментов"
```

---

### Task 2: Расписание без frappe — `schedule.py`

**Files:**
- Create: `habibi_ai/schedule.py`
- Test: `habibi_ai/tests/test_schedule.py`

**Interfaces:**
- Produces: `KIND_WORK = "Работа"`, `KIND_DELIVERY = "Доставка"`, `WEEKDAYS` (полные русские имена, Пн=0); строка расписания — `{"weekday": str, "kind": str, "opens", "closes"}` (время — `datetime.time`, `timedelta` или `"HH:MM[:SS]"`); исключение — `{"date": date, "closed": int, "opens", "closes", "note"}`. Функции: `open_interval(now, kind, schedule, exceptions) -> (start, end) | None`, `status_line(now, kind, schedule, exceptions) -> str`, `has_kind(schedule, kind) -> bool`, `describe(now, schedule, exceptions, days=7) -> str`. `now` — наивный `datetime` в поясе заведения.

- [ ] **Step 1: Падающие тесты** — `habibi_ai/tests/test_schedule.py`:

```python
"""Режим работы: открыто ли сейчас и что сказать про неделю.

Без frappe: время модели считают плохо, поэтому считает код, и проверяться
это должно за секунды — особенно полночь и дни-исключения.
"""

import unittest
from datetime import date, datetime, timedelta

from habibi_ai import schedule as s

# 2026-09-21 — понедельник
MON = date(2026, 9, 21)


def row(weekday, opens, closes, kind=s.KIND_WORK):
	return {"weekday": s.WEEKDAYS[weekday], "kind": kind, "opens": opens, "closes": closes}


WEEK = [row(d, "09:00", "21:00") for d in range(7)] + [row(d, "10:00", "23:00", s.KIND_DELIVERY) for d in range(7)]


def at(day, hh, mm=0):
	return datetime.combine(day, datetime.min.time()) + timedelta(hours=hh, minutes=mm)


class TestОткрытоЛи(unittest.TestCase):
	def test_внутри_интервала_открыто(self):
		self.assertEqual(s.open_interval(at(MON, 12), s.KIND_WORK, WEEK, [])[1], at(MON, 21))

	def test_граница_закрытия_уже_закрыто(self):
		self.assertIsNone(s.open_interval(at(MON, 21), s.KIND_WORK, WEEK, []))

	def test_работа_через_полночь_открыто_после_полуночи(self):
		# Пятница 18:00–02:00: в субботу в 01:00 ещё открыто — по вчерашней строке
		night = [row(4, "18:00", "02:00")]
		saturday = MON + timedelta(days=5)
		self.assertIsNotNone(s.open_interval(at(saturday, 1), s.KIND_WORK, night, []))
		self.assertIsNone(s.open_interval(at(saturday, 3), s.KIND_WORK, night, []))

	def test_исключение_закрыто_перекрывает_расписание(self):
		exc = [{"date": MON, "closed": 1, "opens": None, "closes": None, "note": "Праздник"}]
		self.assertIsNone(s.open_interval(at(MON, 12), s.KIND_WORK, WEEK, exc))

	def test_особые_часы_действуют_на_работу_и_доставку(self):
		exc = [{"date": MON, "closed": 0, "opens": "12:00", "closes": "16:00", "note": None}]
		self.assertIsNone(s.open_interval(at(MON, 10), s.KIND_WORK, WEEK, exc))
		self.assertEqual(s.open_interval(at(MON, 13), s.KIND_DELIVERY, WEEK, exc)[1], at(MON, 16))

	def test_время_из_базы_приходит_timedelta(self):
		# Frappe отдаёт поле Time как timedelta — это не должно ломать расчёт
		rows = [row(0, timedelta(hours=9), timedelta(hours=21))]
		self.assertIsNotNone(s.open_interval(at(MON, 10), s.KIND_WORK, rows, []))


class TestТекст(unittest.TestCase):
	def test_закрыто_говорит_когда_откроется(self):
		self.assertIn("откроется сегодня в 09:00", s.status_line(at(MON, 7), s.KIND_WORK, WEEK, []))

	def test_открыто_говорит_до_скольки(self):
		self.assertIn("открыто до 21:00", s.status_line(at(MON, 12), s.KIND_WORK, WEEK, []))

	def test_неделя_начинается_с_сегодня_и_содержит_исключение(self):
		exc = [{"date": MON + timedelta(days=1), "closed": 1, "opens": None, "closes": None, "note": "Праздник"}]
		text = s.describe(at(MON, 12), WEEK, exc)
		lines = [line for line in text.splitlines() if line.startswith("- ")]
		self.assertEqual(len(lines), 7)
		self.assertTrue(lines[0].startswith("- Пн 21.09"))
		self.assertIn("выходной (Праздник)", lines[1])
		self.assertIn("доставка 10:00–23:00", lines[0])

	def test_без_строк_доставки_про_доставку_не_говорит(self):
		work_only = [row(d, "09:00", "21:00") for d in range(7)]
		self.assertNotIn("доставка", s.describe(at(MON, 12), work_only, []).lower())

	def test_неделя_без_работы_говорит_словами(self):
		self.assertIn("в ближайшие 7 дней", s.status_line(at(MON, 12), s.KIND_WORK, [], []))
```

- [ ] **Step 2: Убедиться, что падают**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench/apps/habibi_ai && ../../env/bin/python -m unittest habibi_ai.tests.test_schedule -v"`
Expected: FAIL — `ImportError: cannot import name 'schedule'`.

- [ ] **Step 3: Реализация** — `habibi_ai/schedule.py`:

```python
"""Режим работы заведения: открыто ли сейчас и что сказать про неделю.

Без frappe, как loop.py и decisions.py: время модели считают плохо — путают
полночь, день недели, «через час». Поэтому «открыто ли» считает код, а
модель пересказывает готовую фразу. И проверяется это за секунды.

now везде — наивное время в поясе заведения; перевод из пояса сайта делает
вызывающий (tools/hours.py).
"""

from datetime import date, datetime, time, timedelta

KIND_WORK = "Работа"
KIND_DELIVERY = "Доставка"

WEEKDAYS = ("Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье")
SHORT = ("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс")

# Сколько дней вперёд ищем ближайшее открытие и сколько показываем в неделе
HORIZON_DAYS = 7


def _to_time(value):
	"""Время из поля Time: Frappe отдаёт timedelta, форма — строку, тесты — что удобно."""
	if isinstance(value, time):
		return value
	if isinstance(value, timedelta):
		seconds = int(value.total_seconds()) % 86400
		return time(seconds // 3600, seconds % 3600 // 60)
	hh, mm, *_ = str(value).split(":")
	return time(int(hh), int(mm))


def _interval(day, opens, closes):
	start = datetime.combine(day, _to_time(opens))
	end = datetime.combine(day, _to_time(closes))
	# Закрытие раньше открытия — работа через полночь: 18:00–02:00
	if end <= start:
		end += timedelta(days=1)
	return start, end


def _exception(day, exceptions):
	return next((e for e in exceptions if e["date"] == day), None)


def has_kind(schedule, kind):
	return any(r["kind"] == kind for r in schedule)


def intervals_for(day, kind, schedule, exceptions):
	"""Интервалы вида kind, которые начинаются в дату day.

	Особые часы исключения действуют и на работу, и на доставку: в
	сокращённый день доставка не может работать дольше самого заведения.
	"""
	exc = _exception(day, exceptions)
	if exc:
		if exc.get("closed"):
			return []
		if exc.get("opens") and exc.get("closes"):
			return [_interval(day, exc["opens"], exc["closes"])] if has_kind(schedule, kind) else []
	weekday = WEEKDAYS[day.weekday()]
	return sorted(
		_interval(day, r["opens"], r["closes"]) for r in schedule if r["weekday"] == weekday and r["kind"] == kind
	)


def open_interval(now, kind, schedule, exceptions):
	"""Интервал, внутри которого now, или None.

	Смотрим и вчерашний день: интервал пятницы 18:00–02:00 в субботу в 01:00
	ещё идёт, а в субботних строках его нет.
	"""
	for day in (now.date() - timedelta(days=1), now.date()):
		for start, end in intervals_for(day, kind, schedule, exceptions):
			if start <= now < end:
				return start, end
	return None


def _next_opening(now, kind, schedule, exceptions):
	for offset in range(HORIZON_DAYS + 1):
		for start, _ in intervals_for(now.date() + timedelta(days=offset), kind, schedule, exceptions):
			if start > now:
				return start
	return None


def status_line(now, kind, schedule, exceptions):
	"""Фраза о текущем состоянии: «открыто до 21:00», «закрыто, откроется завтра…»."""
	is_work = kind == KIND_WORK
	current = open_interval(now, kind, schedule, exceptions)
	if current:
		return f"{'открыто' if is_work else 'доставка работает'} до {current[1]:%H:%M}"

	subject = "закрыто" if is_work else "доставка не работает"
	verb = "откроется" if is_work else "начнётся"
	start = _next_opening(now, kind, schedule, exceptions)
	if start is None:
		return f"{subject}, в ближайшие {HORIZON_DAYS} дней не {'открываемся' if is_work else 'работает'}"
	if start.date() == now.date():
		when = f"сегодня в {start:%H:%M}"
	elif start.date() == now.date() + timedelta(days=1):
		when = f"завтра в {start:%H:%M}"
	else:
		when = f"{SHORT[start.weekday()]} {start:%d.%m} в {start:%H:%M}"
	return f"{subject}, {verb} {when}"


def describe(now, schedule, exceptions, days=HORIZON_DAYS):
	"""Ответ get_working_hours: состояние сейчас и расписание на неделю с сегодня."""
	kinds = [KIND_WORK] + ([KIND_DELIVERY] if has_kind(schedule, KIND_DELIVERY) else [])
	head = "; ".join(status_line(now, kind, schedule, exceptions) for kind in kinds)
	lines = [f"Сейчас {SHORT[now.weekday()]} {now:%d.%m %H:%M}: {head}.", "Расписание:"]

	for offset in range(days):
		day = now.date() + timedelta(days=offset)
		parts = []
		for kind in kinds:
			spans = intervals_for(day, kind, schedule, exceptions)
			if spans:
				parts.append(f"{kind.lower()} " + ", ".join(f"{a:%H:%M}–{b:%H:%M}" for a, b in spans))
		text = "; ".join(parts) or "выходной"
		exc = _exception(day, exceptions)
		if exc and exc.get("note"):
			text += f" ({exc['note']})"
		lines.append(f"- {SHORT[day.weekday()]} {day:%d.%m}: {text}")

	return "\n".join(lines)
```

- [ ] **Step 4: Тесты зелёные**

Run: тот же, что в Step 2. Expected: PASS (11 тестов).

- [ ] **Step 5: Commit**

```bash
git add habibi_ai/schedule.py habibi_ai/tests/test_schedule.py
git commit -m "feat(hours): расчёт режима работы без frappe — полночь, исключения, неделя"
```

---

### Task 3: Настройки, справочник `Working Hours` и `get_working_hours`

**Files:**
- Create: `habibi_ai/habibi_ai/doctype/habibi_ai_settings/{__init__.py,habibi_ai_settings.json,habibi_ai_settings.py}`
- Create: `habibi_ai/habibi_ai/doctype/working_hours/{__init__.py,working_hours.json,working_hours.py}`
- Create: `habibi_ai/habibi_ai/doctype/working_hours_slot/{__init__.py,working_hours_slot.json,working_hours_slot.py}`
- Create: `habibi_ai/habibi_ai/doctype/working_hours_exception/{__init__.py,working_hours_exception.json,working_hours_exception.py}`
- Create: `habibi_ai/tools/hours.py`
- Modify: `habibi_ai/tools/__init__.py` (регистрация импортом)
- Test: `habibi_ai/tests/test_hours.py`

**Interfaces:**
- Consumes: `schedule.describe`, `schedule.open_interval`, `schedule.status_line`, `schedule.has_kind`, `KIND_WORK`, `KIND_DELIVERY` (Task 2).
- Produces: `habibi_ai.habibi_ai.doctype.habibi_ai_settings.habibi_ai_settings.get_company() -> str | None`; `tools.hours.load_hours() -> (schedule, exceptions, tz) | None`; `tools.hours.closed_warning(fulfilment: str) -> str | None` (`fulfilment` — `"delivery"`/`"pickup"`); инструмент `get_working_hours`.

- [ ] **Step 1: Доктайп `Habibi AI Settings`**

`habibi_ai/habibi_ai/doctype/habibi_ai_settings/__init__.py` — пустой.

`habibi_ai/habibi_ai/doctype/habibi_ai_settings/habibi_ai_settings.json`:

```json
{
 "actions": [],
 "creation": "2026-09-19 12:00:00.000000",
 "doctype": "DocType",
 "engine": "InnoDB",
 "field_order": ["company"],
 "fields": [
  {
   "description": "На эту компанию бот оформляет заказы; её режим работы называет. Пусто — приём заказов выключен.",
   "fieldname": "company",
   "fieldtype": "Link",
   "label": "Компания",
   "options": "Company"
  }
 ],
 "issingle": 1,
 "links": [],
 "modified": "2026-09-19 12:00:00.000000",
 "modified_by": "Administrator",
 "module": "Habibi AI",
 "name": "Habibi AI Settings",
 "owner": "Administrator",
 "permissions": [
  {"create": 1, "read": 1, "role": "System Manager", "write": 1}
 ],
 "sort_field": "modified",
 "sort_order": "DESC",
 "states": [],
 "track_changes": 1
}
```

`habibi_ai/habibi_ai/doctype/habibi_ai_settings/habibi_ai_settings.py`:

```python
"""Настройки ИИ на сайте.

Компания — отдельной настройкой, а не из Global Defaults: на тестовом сайте
умолчанием стоит Test (Demo) в SAR, и бот оформлял бы заказы бургерной в
риалах, не сказав никому.
"""

import frappe
from frappe.model.document import Document

DOCTYPE = "Habibi AI Settings"


class HabibiAISettings(Document):
	pass


def get_company():
	return frappe.db.get_single_value(DOCTYPE, "company") or None
```

- [ ] **Step 2: Доктайпы `Working Hours`, `Working Hours Slot`, `Working Hours Exception`**

`working_hours_slot/__init__.py`, `working_hours_exception/__init__.py`, `working_hours/__init__.py` — пустые.

`habibi_ai/habibi_ai/doctype/working_hours_slot/working_hours_slot.json`:

```json
{
 "actions": [],
 "creation": "2026-09-19 12:00:00.000000",
 "doctype": "DocType",
 "editable_grid": 1,
 "engine": "InnoDB",
 "field_order": ["weekday", "kind", "opens", "closes"],
 "fields": [
  {"fieldname": "weekday", "fieldtype": "Select", "in_list_view": 1, "label": "День", "reqd": 1,
   "options": "Понедельник\nВторник\nСреда\nЧетверг\nПятница\nСуббота\nВоскресенье"},
  {"default": "Работа", "fieldname": "kind", "fieldtype": "Select", "in_list_view": 1, "label": "Что",
   "options": "Работа\nДоставка", "reqd": 1},
  {"fieldname": "opens", "fieldtype": "Time", "in_list_view": 1, "label": "С", "reqd": 1},
  {"description": "Раньше открытия — работа через полночь", "fieldname": "closes", "fieldtype": "Time",
   "in_list_view": 1, "label": "До", "reqd": 1}
 ],
 "istable": 1,
 "links": [],
 "modified": "2026-09-19 12:00:00.000000",
 "modified_by": "Administrator",
 "module": "Habibi AI",
 "name": "Working Hours Slot",
 "owner": "Administrator",
 "permissions": [],
 "sort_field": "modified",
 "sort_order": "DESC",
 "states": []
}
```

`habibi_ai/habibi_ai/doctype/working_hours_exception/working_hours_exception.json`:

```json
{
 "actions": [],
 "creation": "2026-09-19 12:00:00.000000",
 "doctype": "DocType",
 "editable_grid": 1,
 "engine": "InnoDB",
 "field_order": ["date", "closed", "opens", "closes", "note"],
 "fields": [
  {"fieldname": "date", "fieldtype": "Date", "in_list_view": 1, "label": "Дата", "reqd": 1},
  {"default": "0", "fieldname": "closed", "fieldtype": "Check", "in_list_view": 1, "label": "Закрыто"},
  {"depends_on": "eval:!doc.closed", "fieldname": "opens", "fieldtype": "Time", "in_list_view": 1, "label": "С"},
  {"depends_on": "eval:!doc.closed", "fieldname": "closes", "fieldtype": "Time", "in_list_view": 1, "label": "До"},
  {"fieldname": "note", "fieldtype": "Data", "in_list_view": 1, "label": "Причина"}
 ],
 "istable": 1,
 "links": [],
 "modified": "2026-09-19 12:00:00.000000",
 "modified_by": "Administrator",
 "module": "Habibi AI",
 "name": "Working Hours Exception",
 "owner": "Administrator",
 "permissions": [],
 "sort_field": "modified",
 "sort_order": "DESC",
 "states": []
}
```

`working_hours_slot.py` и `working_hours_exception.py`:

```python
from frappe.model.document import Document


class WorkingHoursSlot(Document):
	pass
```

(во втором файле класс `WorkingHoursException`.)

`habibi_ai/habibi_ai/doctype/working_hours/working_hours.json`:

```json
{
 "actions": [],
 "autoname": "field:company",
 "creation": "2026-09-19 12:00:00.000000",
 "doctype": "DocType",
 "engine": "InnoDB",
 "field_order": ["company", "time_zone", "schedule_section", "schedule", "exceptions_section", "exceptions"],
 "fields": [
  {"fieldname": "company", "fieldtype": "Link", "in_list_view": 1, "label": "Компания", "options": "Company",
   "reqd": 1, "unique": 1},
  {"description": "Например Asia/Almaty. Пусто — пояс сайта. Нужен, когда заведение не в поясе сервера.",
   "fieldname": "time_zone", "fieldtype": "Data", "label": "Часовой пояс"},
  {"fieldname": "schedule_section", "fieldtype": "Section Break", "label": "По дням недели"},
  {"fieldname": "schedule", "fieldtype": "Table", "label": "Расписание", "options": "Working Hours Slot"},
  {"fieldname": "exceptions_section", "fieldtype": "Section Break", "label": "Исключения"},
  {"fieldname": "exceptions", "fieldtype": "Table", "label": "Особые дни", "options": "Working Hours Exception"}
 ],
 "links": [],
 "modified": "2026-09-19 12:00:00.000000",
 "modified_by": "Administrator",
 "module": "Habibi AI",
 "name": "Working Hours",
 "owner": "Administrator",
 "permissions": [
  {"create": 1, "delete": 1, "read": 1, "role": "System Manager", "write": 1}
 ],
 "sort_field": "modified",
 "sort_order": "DESC",
 "states": [],
 "track_changes": 1
}
```

`habibi_ai/habibi_ai/doctype/working_hours/working_hours.py`:

```python
"""Режим работы заведения — справочник, из которого бот отвечает «до скольки».

Живёт в приложении, а не заводится руками на сайте: он нужен каждому
заведению, и руками на третьем сайте он разошёлся бы полями с первыми двумя.
"""

from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import frappe
from frappe import _
from frappe.model.document import Document


class WorkingHours(Document):
	def validate(self):
		if self.time_zone:
			try:
				ZoneInfo(self.time_zone)
			except (ZoneInfoNotFoundError, ValueError):
				frappe.throw(_("Неизвестный часовой пояс {0}. Пример: Asia/Almaty").format(self.time_zone))

		for row in self.exceptions:
			if not row.closed and not (row.opens and row.closes):
				frappe.throw(_("Строка {0} исключений: либо «Закрыто», либо часы «С» и «До»").format(row.idx))

		for row in self.schedule:
			if row.opens == row.closes:
				frappe.throw(_("Строка {0} расписания: «С» и «До» совпадают").format(row.idx))
```

- [ ] **Step 3: Падающие тесты инструмента** — `habibi_ai/tests/test_hours.py`:

```python
"""get_working_hours и предупреждение для расчёта заказа.

Сайт не нужен: справочник подменяется через load_hours. Главный случай —
не настроено: бот не должен назвать часы, которых нет.
"""

import unittest
from datetime import datetime
from unittest.mock import patch

from habibi_ai import schedule as s
from habibi_ai import tools
from habibi_ai.tools import hours

WEEK = [{"weekday": s.WEEKDAYS[d], "kind": s.KIND_WORK, "opens": "09:00", "closes": "21:00"} for d in range(7)] + [
	{"weekday": s.WEEKDAYS[d], "kind": s.KIND_DELIVERY, "opens": "10:00", "closes": "23:00"} for d in range(7)
]


class TestGetWorkingHours(unittest.TestCase):
	def test_не_настроено_бот_не_называет_часов(self):
		with patch.object(hours, "load_hours", return_value=None):
			result = tools.execute("get_working_hours", {})
		self.assertIn("не настроен", result)
		self.assertIn("Не называй", result)

	def test_настроено_отдаёт_состояние_и_неделю(self):
		with (
			patch.object(hours, "load_hours", return_value=(WEEK, [], "Asia/Almaty")),
			patch.object(hours, "local_now", return_value=datetime(2026, 9, 21, 12, 0)),
		):
			result = tools.execute("get_working_hours", {})
		self.assertIn("открыто до 21:00", result)
		self.assertIn("доставка работает до 23:00", result)


class TestПредупреждение(unittest.TestCase):
	def _warning(self, now, fulfilment):
		with (
			patch.object(hours, "load_hours", return_value=(WEEK, [], "Asia/Almaty")),
			patch.object(hours, "local_now", return_value=now),
		):
			return hours.closed_warning(fulfilment)

	def test_в_рабочее_время_предупреждения_нет(self):
		self.assertIsNone(self._warning(datetime(2026, 9, 21, 12, 0), "delivery"))

	def test_доставка_ночью_предупреждает(self):
		warning = self._warning(datetime(2026, 9, 21, 23, 30), "delivery")
		self.assertIn("доставка не работает", warning)

	def test_самовывоз_смотрит_часы_работы_а_не_доставки(self):
		# 22:00 — доставка ещё работает, заведение уже закрыто
		self.assertIn("закрыто", self._warning(datetime(2026, 9, 21, 22, 0), "pickup"))

	def test_без_справочника_предупреждения_нет(self):
		with patch.object(hours, "load_hours", return_value=None):
			self.assertIsNone(hours.closed_warning("delivery"))
```

- [ ] **Step 4: Убедиться, что падают**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench/apps/habibi_ai && ../../env/bin/python -m unittest habibi_ai.tests.test_hours -v"`
Expected: FAIL — `ImportError: cannot import name 'hours'`.

- [ ] **Step 5: Реализация** — `habibi_ai/tools/hours.py`:

```python
"""Режим работы из справочника Working Hours.

Последний факт, который жил в персоне бота. Записанный в промпт, он
устаревает молча: график сменился, а бот продолжает звать клиентов к девяти.
"""

from datetime import datetime
from zoneinfo import ZoneInfo

import frappe

from habibi_ai import schedule
from habibi_ai.habibi_ai.doctype.habibi_ai_settings.habibi_ai_settings import get_company
from habibi_ai.tools import tool

DOCTYPE = "Working Hours"

NOT_CONFIGURED = (
	"Режим работы в системе не настроен. Не называй часы работы и доставки, "
	"предложи уточнить у оператора."
)


def load_hours():
	"""(расписание, исключения, пояс) компании из настроек, или None — не настроено."""
	company = get_company()
	name = company and frappe.db.get_value(DOCTYPE, {"company": company})
	if not name:
		return None

	doc = frappe.get_doc(DOCTYPE, name)
	if not doc.schedule:
		return None

	rows = [{"weekday": r.weekday, "kind": r.kind, "opens": r.opens, "closes": r.closes} for r in doc.schedule]
	exceptions = [
		{
			"date": frappe.utils.getdate(r.date),
			"closed": r.closed,
			"opens": r.opens,
			"closes": r.closes,
			"note": r.note,
		}
		for r in doc.exceptions
	]
	# Пояс заведения, а не сайта: erp.habibi-erp.com стоит в Asia/Riyadh, а
	# бургерная в Казахстане — по поясу сайта бот ошибался бы на два часа
	tz = doc.time_zone or frappe.db.get_single_value("System Settings", "time_zone") or "UTC"
	return rows, exceptions, tz


def local_now(tz):
	return datetime.now(ZoneInfo(tz)).replace(tzinfo=None)


@tool(
	name="get_working_hours",
	description=(
		"Режим работы и доставки: открыто ли сейчас, до скольки, и расписание на неделю. "
		"Вызывай, когда спрашивают, работаете ли, до скольки, когда откроетесь, — "
		"часы меняются, помнить их нельзя."
	),
	input_schema={"type": "object", "properties": {}},
)
def get_working_hours():
	loaded = load_hours()
	if loaded is None:
		return NOT_CONFIGURED
	rows, exceptions, tz = loaded
	return schedule.describe(local_now(tz), rows, exceptions)


def closed_warning(fulfilment):
	"""Предупреждение для расчёта заказа, если сейчас его не выполнят; None — всё в порядке.

	Не запрет: заказ на утро — нормальный заказ. Но клиент должен услышать,
	что ночью его не привезут, до того, как скажет «да».
	"""
	loaded = load_hours()
	if loaded is None:
		return None
	rows, exceptions, tz = loaded

	kind = schedule.KIND_WORK
	if fulfilment == "delivery" and schedule.has_kind(rows, schedule.KIND_DELIVERY):
		kind = schedule.KIND_DELIVERY

	now = local_now(tz)
	if schedule.open_interval(now, kind, rows, exceptions):
		return None
	return (
		f"Внимание: сейчас {schedule.status_line(now, kind, rows, exceptions)}. "
		"Предупреди клиента, что заказ выполнят, когда откроемся."
	)
```

В конец `habibi_ai/tools/__init__.py` дописать:

```python
from habibi_ai.tools import hours  # noqa: E402,F401  регистрация при импорте пакета
```

- [ ] **Step 6: Тесты зелёные, миграция проходит**

Run: тот же, что в Step 4. Expected: PASS.
Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost migrate"`
Expected: без ошибок; в Desk открываются «Habibi AI Settings» и «Working Hours».

- [ ] **Step 7: Commit**

```bash
git add habibi_ai/habibi_ai/doctype/habibi_ai_settings habibi_ai/habibi_ai/doctype/working_hours habibi_ai/habibi_ai/doctype/working_hours_slot habibi_ai/habibi_ai/doctype/working_hours_exception habibi_ai/tools/hours.py habibi_ai/tools/__init__.py habibi_ai/tests/test_hours.py
git commit -m "feat(hours): справочник режима работы и инструмент get_working_hours"
```

---

### Task 4: Правила заказа без frappe — `order_rules.py`

**Files:**
- Create: `habibi_ai/order_rules.py`
- Test: `habibi_ai/tests/test_order_rules.py`

**Interfaces:**
- Produces:
  - `class Refusal(Exception)` — текст отказа для модели.
  - `MAX_QTY = 50`, `QUOTE_TTL = timedelta(minutes=30)`, `DELIVERY_ITEM = "SRV-DELIVERY"`.
  - `normalize_phone(raw) -> str | None` — `"+"` и 10–15 цифр.
  - `money(value) -> str` — `4670.0 → "4 670"`, `500.36 → "500.36"`.
  - `resolve_lines(requested, catalog) -> list[dict]`; `catalog = {item_code: {"item_name", "rate", "uom"}}`; строка — `{"item_code", "item_name", "qty": int, "rate": float, "uom"}`.
  - `match_zone(requested, zones) -> dict`; зона — `{"name", "delivery_fee", "free_above"}`.
  - `delivery_line(zone, goods_total, uom) -> dict` — строка той же формы, что у `resolve_lines`.
  - `check_quote(quote, context, now) -> "done" | "create"`; `quote` — dict с `engine_chat_id`, `turn_id`, `expires_on`, `sales_order` или `None`.
  - `item_lines(rows, currency) -> list[str]`; `rows` — `[{"item_code", "item_name", "qty", "amount"}]`.
  - `total_line(payable, taxes, currency) -> str`; `taxes` — `[{"description", "amount"}]`.

- [ ] **Step 1: Падающие тесты** — `habibi_ai/tests/test_order_rules.py`:

```python
"""Правила заказа без frappe: что модель может и чего не может передать.

Аргументы приходят от модели — это недоверенный ввод. Каждый отказ здесь —
текст, по которому модель исправится сама, а не исключение, которое
оборвало бы разговор.
"""

import unittest
from datetime import datetime, timedelta

from habibi_ai import order_rules as r

CATALOG = {
	"BRG-CLASSIC": {"item_name": "Classic Burger", "rate": 2490.0, "uom": "Nos"},
	"DRK-COLA": {"item_name": "Cola 0.5 L", "rate": 690.0, "uom": "Nos"},
}
ZONES = [
	{"name": "Center", "delivery_fee": 800.0, "free_above": 10000.0},
	{"name": "North", "delivery_fee": 1200.0, "free_above": None},
]
NOW = datetime(2026, 9, 21, 12, 0)
CTX = {"engine_chat_id": 5, "turn_id": "t2"}


def quote(**kw):
	base = {"engine_chat_id": 5, "turn_id": "t1", "expires_on": NOW + timedelta(minutes=10), "sales_order": None}
	base.update(kw)
	return base


class TestПозиции(unittest.TestCase):
	def test_позиции_берут_цену_из_каталога(self):
		lines = r.resolve_lines([{"item_code": "BRG-CLASSIC", "qty": 2}], CATALOG)
		self.assertEqual(lines, [{"item_code": "BRG-CLASSIC", "item_name": "Classic Burger", "qty": 2, "rate": 2490.0, "uom": "Nos"}])

	def test_позицию_можно_назвать_по_имени(self):
		# Модель часто передаёт то, что видела в меню, — название, а не код
		lines = r.resolve_lines([{"item_code": "classic burger", "qty": 1}], CATALOG)
		self.assertEqual(lines[0]["item_code"], "BRG-CLASSIC")

	def test_неизвестная_позиция_отказ_со_списком_доступных(self):
		with self.assertRaises(r.Refusal) as cm:
			r.resolve_lines([{"item_code": "пицца", "qty": 1}], CATALOG)
		self.assertIn("«пицца»", str(cm.exception))
		self.assertIn("Classic Burger (BRG-CLASSIC)", str(cm.exception))

	def test_повтор_позиции_складывается(self):
		lines = r.resolve_lines([{"item_code": "DRK-COLA", "qty": 1}, {"item_code": "DRK-COLA", "qty": 2}], CATALOG)
		self.assertEqual([(line["item_code"], line["qty"]) for line in lines], [("DRK-COLA", 3)])

	def test_количество_вне_границ_отказ(self):
		for qty in (0, -1, 1.5, 51, "2", True, None):
			with self.subTest(qty=qty), self.assertRaises(r.Refusal):
				r.resolve_lines([{"item_code": "DRK-COLA", "qty": qty}], CATALOG)

	def test_целое_во_float_принимается(self):
		self.assertEqual(r.resolve_lines([{"item_code": "DRK-COLA", "qty": 2.0}], CATALOG)[0]["qty"], 2)

	def test_пустой_состав_отказ(self):
		for items in ([], None, "бургер"):
			with self.subTest(items=items), self.assertRaises(r.Refusal):
				r.resolve_lines(items, CATALOG)


class TestДоставка(unittest.TestCase):
	def test_зона_по_имени_без_учёта_регистра(self):
		self.assertEqual(r.match_zone("center", ZONES)["name"], "Center")

	def test_неизвестная_зона_отказ_со_списком(self):
		with self.assertRaises(r.Refusal) as cm:
			r.match_zone("Луна", ZONES)
		self.assertIn("Center, North", str(cm.exception))

	def test_зона_не_названа_просит_спросить(self):
		with self.assertRaises(r.Refusal) as cm:
			r.match_zone(None, ZONES)
		self.assertIn("Спроси", str(cm.exception))

	def test_бесплатно_от_порога(self):
		self.assertEqual(r.delivery_line(ZONES[0], 10000.0, "Nos")["rate"], 0.0)
		self.assertEqual(r.delivery_line(ZONES[0], 9999.0, "Nos")["rate"], 800.0)

	def test_без_порога_всегда_платно(self):
		line = r.delivery_line(ZONES[1], 50000.0, "Nos")
		self.assertEqual((line["item_code"], line["rate"], line["item_name"]), ("SRV-DELIVERY", 1200.0, "Доставка (North)"))


class TestТелефон(unittest.TestCase):
	def test_нормализация(self):
		self.assertEqual(r.normalize_phone("+7 (701) 555-01-04"), "+77015550104")
		self.assertEqual(r.normalize_phone("87015550104"), "+87015550104")

	def test_короткий_или_пустой_номер(self):
		for raw in ("12345", "", None, "позвоните"):
			with self.subTest(raw=raw):
				self.assertIsNone(r.normalize_phone(raw))


class TestПроверкаРасчёта(unittest.TestCase):
	def test_расчёт_из_другого_чата_не_найден(self):
		with self.assertRaises(r.Refusal) as cm:
			r.check_quote(quote(engine_chat_id=6), CTX, NOW)
		self.assertIn("не найден", str(cm.exception))

	def test_нет_расчёта_не_найден(self):
		with self.assertRaises(r.Refusal):
			r.check_quote(None, CTX, NOW)

	def test_тот_же_ход_отказ(self):
		with self.assertRaises(r.Refusal) as cm:
			r.check_quote(quote(turn_id="t2"), CTX, NOW)
		self.assertIn("дождись", str(cm.exception))

	def test_просроченный_отказ(self):
		with self.assertRaises(r.Refusal) as cm:
			r.check_quote(quote(expires_on=NOW - timedelta(seconds=1)), CTX, NOW)
		self.assertIn("устарел", str(cm.exception))

	def test_уже_оформленный_возвращает_done_даже_в_том_же_ходе(self):
		self.assertEqual(r.check_quote(quote(turn_id="t2", sales_order="SO-1"), CTX, NOW), "done")

	def test_годный_расчёт(self):
		self.assertEqual(r.check_quote(quote(), CTX, NOW), "create")


class TestТекст(unittest.TestCase):
	def test_деньги(self):
		self.assertEqual(r.money(4670.0), "4 670")
		self.assertEqual(r.money(500.36), "500.36")
		self.assertEqual(r.money(100), "100")
		self.assertEqual(r.money(1234567.5), "1 234 567.50")

	def test_строки_позиций_и_доставки(self):
		rows = [
			{"item_code": "BRG-CLASSIC", "item_name": "Classic Burger", "qty": 1, "amount": 2490.0},
			{"item_code": "SRV-DELIVERY", "item_name": "Доставка (Center)", "qty": 1, "amount": 0.0},
		]
		self.assertEqual(
			r.item_lines(rows, "KZT"),
			["- Classic Burger × 1 — 2 490 KZT", "- Доставка (Center) — бесплатно"],
		)

	def test_итог_с_налогом(self):
		line = r.total_line(4670.0, [{"description": "VAT 12%", "amount": 500.36}], "KZT")
		self.assertEqual(line, "Итого: 4 670 KZT, включая VAT 12% — 500.36 KZT")
```

- [ ] **Step 2: Убедиться, что падают**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench/apps/habibi_ai && ../../env/bin/python -m unittest habibi_ai.tests.test_order_rules -v"`
Expected: FAIL — `ImportError: cannot import name 'order_rules'`.

- [ ] **Step 3: Реализация** — `habibi_ai/order_rules.py`:

```python
"""Правила заказа, не зависящие от frappe.

Всё, что проверяет аргументы модели и решает судьбу расчёта, — здесь, без
ERP: цена ошибки — заказ не того состава или второй заказ вместо одного, и
проверяться это должно за секунды. ERP-связка — в tools/orders.py.
"""

import re
from datetime import timedelta

MAX_QTY = 50
QUOTE_TTL = timedelta(minutes=30)
DELIVERY_ITEM = "SRV-DELIVERY"


class Refusal(Exception):
	"""Отказ, который модель увидит текстом и по которому исправится сама."""


def normalize_phone(raw):
	"""+ и цифры; None, если на номер не похоже.

	Клиент пишет номер как угодно: «+7 (701) 555-01-04», «8701…». Сравнивать
	и хранить надо одну форму — иначе один человек станет двумя клиентами.
	"""
	digits = re.sub(r"\D", "", str(raw or ""))
	if not 10 <= len(digits) <= 15:
		return None
	return "+" + digits


def money(value):
	"""4 670 и 500.36: без копеек, когда их нет, — так пишут цены в меню."""
	whole, frac = f"{float(value or 0):,.2f}".split(".")
	whole = whole.replace(",", " ")
	return whole if frac == "00" else f"{whole}.{frac}"


def _valid_qty(qty):
	# bool — подкласс int: True прошёл бы как «одна штука»
	if isinstance(qty, bool) or not isinstance(qty, (int, float)):
		return False
	return qty == int(qty) and 1 <= qty <= MAX_QTY


def resolve_lines(requested, catalog):
	"""Состав от модели → строки с ценой из каталога.

	Цена берётся только из каталога: в аргументах её нет вовсе. Позицию можно
	назвать кодом или названием — модель видела в меню и то и другое.
	"""
	if not isinstance(requested, list) or not requested:
		raise Refusal(
			"Состав заказа пуст. Передай в items весь заказ целиком: [{item_code, qty}] — "
			"код или название позиции из get_menu и количество."
		)

	by_name = {v["item_name"].casefold(): code for code, v in catalog.items()}
	quantities = {}
	unknown = []
	for row in requested:
		if not isinstance(row, dict):
			raise Refusal("Каждая позиция — объект {item_code, qty}.")
		key = str(row.get("item_code") or "").strip()
		code = key if key in catalog else by_name.get(key.casefold())
		if code is None:
			unknown.append(key or "(пусто)")
			continue
		qty = row.get("qty")
		if not _valid_qty(qty):
			raise Refusal(
				f"Количество «{qty}» для {catalog[code]['item_name']} не подходит: нужно целое от 1 до {MAX_QTY}."
			)
		quantities[code] = quantities.get(code, 0) + int(qty)

	if unknown:
		available = ", ".join(f"{v['item_name']} ({code})" for code, v in sorted(catalog.items()))
		missing = ", ".join(f"«{name}»" for name in unknown)
		raise Refusal(f"Нет в меню: {missing}. Доступно: {available}. Уточни у клиента, что он имел в виду.")

	for code, qty in quantities.items():
		if qty > MAX_QTY:
			raise Refusal(f"{catalog[code]['item_name']}: больше {MAX_QTY} штук бот не оформляет — предложи оператора.")

	return [
		{
			"item_code": code,
			"item_name": catalog[code]["item_name"],
			"qty": qty,
			"rate": float(catalog[code]["rate"]),
			"uom": catalog[code]["uom"],
		}
		for code, qty in quantities.items()
	]


def match_zone(requested, zones):
	if not zones:
		raise Refusal("Ни одна зона доставки не активна — доставку оформить нельзя. Предложи самовывоз или оператора.")
	names = ", ".join(z["name"] for z in zones)
	if not requested:
		raise Refusal(f"Спроси у клиента район доставки. Доступны: {names}.")
	for zone in zones:
		if zone["name"].casefold() == str(requested).strip().casefold():
			return zone
	raise Refusal(f"Зоны «{requested}» нет. Доступны: {names}. Уточни у клиента.")


def delivery_line(zone, goods_total, uom):
	"""Доставка — строкой заказа: кухня и касса видят её там же, где еду."""
	fee = float(zone.get("delivery_fee") or 0)
	free_above = zone.get("free_above")
	if free_above and goods_total >= float(free_above):
		fee = 0.0
	return {
		"item_code": DELIVERY_ITEM,
		"item_name": f"Доставка ({zone['name']})",
		"qty": 1,
		"rate": fee,
		"uom": uom,
	}


def check_quote(quote, context, now):
	"""Можно ли оформить заказ по расчёту: "create", "done" (уже оформлен) или Refusal.

	Порядок важен. Сначала чат: чужой расчёт не существует, даже если он
	оформлен. Затем оформленный — повтор возвращает тот же заказ в любом ходе.
	И только потом ход и срок.
	"""
	if not quote or quote.get("engine_chat_id") != context.get("engine_chat_id"):
		raise Refusal("Расчёт не найден. Сделай новый quote_order по составу, который назвал клиент.")
	if quote.get("sales_order"):
		return "done"
	if quote.get("turn_id") == context.get("turn_id"):
		# Главное правило: между расчётом и заказом должно быть сообщение
		# клиента. Проверяет код, а не инструкция, которую модель может забыть.
		raise Refusal(
			"Сначала зачитай расчёт клиенту и дождись его явного согласия. "
			"create_order вызывается после ответа клиента, а не в том же ответе, что quote_order."
		)
	if now > quote["expires_on"]:
		raise Refusal("Расчёт устарел — цены могли измениться. Сделай новый quote_order и зачитай его клиенту.")
	return "create"


def item_lines(rows, currency):
	lines = []
	for row in rows:
		if row["item_code"] == DELIVERY_ITEM:
			price = f"{money(row['amount'])} {currency}" if row["amount"] else "бесплатно"
			lines.append(f"- {row['item_name']} — {price}")
		else:
			lines.append(f"- {row['item_name']} × {money(row['qty'])} — {money(row['amount'])} {currency}")
	return lines


def total_line(payable, taxes, currency):
	line = f"Итого: {money(payable)} {currency}"
	for tax in taxes:
		if tax["amount"]:
			line += f", включая {tax['description']} — {money(tax['amount'])} {currency}"
	return line
```

- [ ] **Step 4: Тесты зелёные**

Run: тот же, что в Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add habibi_ai/order_rules.py habibi_ai/tests/test_order_rules.py
git commit -m "feat(orders): правила заказа без frappe — состав, зона, телефон, расчёт"
```

---

### Task 5: Каталог заказа по правилам меню

**Files:**
- Modify: `habibi_ai/tools/menu.py`
- Test: `habibi_ai/tests/test_tools.py`

**Interfaces:**
- Consumes: `order_rules.DELIVERY_ITEM` (Task 4).
- Produces: `menu.valid_prices(rows, today) -> list`; `menu.sellable_catalog(price_list) -> {item_code: {"item_name", "rate", "uom"}}` — без `SRV-DELIVERY`.

- [ ] **Step 1: Падающие тесты** — дописать в `habibi_ai/tests/test_tools.py`:

```python
class TestКаталогЗаказа(unittest.TestCase):
	"""Заказать можно ровно то, что бот показал бы в меню: иначе он назвал бы
	позицию, а оформить её было бы нельзя, — или наоборот."""

	def _frappe(self, prices, items):
		def get_all(doctype, **kwargs):
			return list(prices) if doctype == "Item Price" else list(items)

		return patch.multiple(
			"frappe",
			get_all=Mock(side_effect=get_all),
			utils=Mock(nowdate=Mock(return_value="2026-09-12")),
		)

	def test_каталог_по_действующим_ценам_без_доставки(self):
		from habibi_ai.tools import menu

		prices = [
			{"item_code": "A", "price_list_rate": 100.0, "valid_from": None, "valid_upto": None},
			{"item_code": "OLD", "price_list_rate": 5.0, "valid_from": None, "valid_upto": "2026-01-01"},
			{"item_code": "SRV-DELIVERY", "price_list_rate": 800.0, "valid_from": None, "valid_upto": None},
		]
		items = [
			{"item_code": "A", "item_name": "Позиция A", "stock_uom": "Nos"},
			{"item_code": "SRV-DELIVERY", "item_name": "Delivery", "stock_uom": "Nos"},
		]
		with self._frappe(prices, items):
			catalog = menu.sellable_catalog("Habibi Menu")
		self.assertEqual(catalog, {"A": {"item_name": "Позиция A", "rate": 100.0, "uom": "Nos"}})

	def test_пустой_прайс_пустой_каталог(self):
		from habibi_ai.tools import menu

		with self._frappe([], []):
			self.assertEqual(menu.sellable_catalog("Habibi Menu"), {})
```

- [ ] **Step 2: Убедиться, что падают**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench/apps/habibi_ai && ../../env/bin/python -m unittest habibi_ai.tests.test_tools -v"`
Expected: FAIL — `AttributeError: module 'habibi_ai.tools.menu' has no attribute 'sellable_catalog'`.

- [ ] **Step 3: Реализация** — в `habibi_ai/tools/menu.py`:

Добавить импорт после `from habibi_ai.tools import tool`:

```python
from habibi_ai.order_rules import DELIVERY_ITEM
```

Добавить перед `@tool(name="get_menu", ...)`:

```python
def valid_prices(rows, today):
	"""Цены, действующие сегодня.

	Срок действия проверяем здесь, а не условием в запросе: сравнение с NULL
	в SQL ложно, и фильтр «valid_upto >= сегодня» выбросил бы как раз обычный
	случай — цену без даты окончания, то есть бессрочную.
	"""
	return [
		r
		for r in rows
		if (not r.get("valid_from") or str(r["valid_from"]) <= today)
		and (not r.get("valid_upto") or str(r["valid_upto"]) >= today)
	]


def sellable_catalog(price_list):
	"""Что можно заказать: те же правила, что у get_menu, но без лимита.

	Бот, показавший позицию в меню и не сумевший её оформить, — или
	оформивший то, чего в меню нет, — хуже бота без заказов. Доставка из
	каталога исключена: её строку добавляет код по зоне, а не модель.
	"""
	rows = frappe.get_all(
		"Item Price",
		filters={"price_list": price_list, "selling": 1},
		fields=["item_code", "price_list_rate", "valid_from", "valid_upto"],
		order_by="item_code",
		limit_page_length=0,
	)
	by_code = {}
	for p in valid_prices(rows, frappe.utils.nowdate()):
		by_code.setdefault(p["item_code"], p)
	by_code.pop(DELIVERY_ITEM, None)
	if not by_code:
		return {}

	items = frappe.get_all(
		"Item",
		filters={"item_code": ["in", list(by_code)], "is_sales_item": 1, "disabled": 0},
		fields=["item_code", "item_name", "stock_uom"],
		limit_page_length=0,
	)
	return {
		i["item_code"]: {
			"item_name": i["item_name"],
			"rate": float(by_code[i["item_code"]]["price_list_rate"]),
			"uom": i["stock_uom"],
		}
		for i in items
		if i["item_code"] != DELIVERY_ITEM
	}
```

В `get_menu` заменить блок от комментария «Срок действия проверяем здесь…» до конца списка `prices = [...]` на:

```python
	prices = valid_prices(rows, frappe.utils.nowdate())
```

- [ ] **Step 4: Все тесты инструментов зелёные**

Run: тот же, что в Step 2. Expected: PASS, включая старые тесты `TestGetMenu`.

- [ ] **Step 5: Commit**

```bash
git add habibi_ai/tools/menu.py habibi_ai/tests/test_tools.py
git commit -m "refactor(menu): правила действующей цены общие для меню и каталога заказа"
```

---

### Task 6: Расчёт `quote_order`

**Files:**
- Create: `habibi_ai/habibi_ai/doctype/ai_order_quote/{__init__.py,ai_order_quote.json,ai_order_quote.py}`
- Create: `habibi_ai/habibi_ai/doctype/ai_order_quote_item/{__init__.py,ai_order_quote_item.json,ai_order_quote_item.py}`
- Create: `habibi_ai/customers.py`
- Create: `habibi_ai/tools/orders.py`
- Modify: `habibi_ai/tools/__init__.py`

**Interfaces:**
- Consumes: `tools.tool(..., context=True)` (Task 1); `hours.closed_warning(fulfilment)` (Task 3); `get_company()` (Task 3); всё из `order_rules` (Task 4); `menu.sellable_catalog(price_list)` (Task 5).
- Produces: `customers.linked_customer(channel_chat) -> str | None`, `customers.find_by_phone(phone) -> str | None`, `customers.create(customer_name, phone) -> str`, `customers.link_chat(channel_chat, customer) -> None`; `orders.load_settings() -> frappe._dict(company, price_list, currency, tax)`; `orders.build_sales_order(settings, lines, customer=None) -> Document` (не сохранён, итоги посчитаны); `orders.payable(so) -> float`; `orders.taxes_of(so) -> list[dict]`; `orders.rows_of(so) -> list[dict]`; инструмент `quote_order`. Доктайп `AI Order Quote` с полями из спеки.

Поведение проверяется интеграционными тестами Task 8 — здесь нет самостоятельной логики, которой не покрыли бы `order_rules` и ERP.

- [ ] **Step 1: Доктайпы**

`ai_order_quote/__init__.py`, `ai_order_quote_item/__init__.py` — пустые.

`habibi_ai/habibi_ai/doctype/ai_order_quote_item/ai_order_quote_item.json`:

```json
{
 "actions": [],
 "creation": "2026-09-19 12:00:00.000000",
 "doctype": "DocType",
 "engine": "InnoDB",
 "field_order": ["item_code", "item_name", "qty", "uom", "rate", "amount"],
 "fields": [
  {"fieldname": "item_code", "fieldtype": "Link", "in_list_view": 1, "label": "Позиция", "options": "Item", "reqd": 1},
  {"fieldname": "item_name", "fieldtype": "Data", "in_list_view": 1, "label": "Название"},
  {"fieldname": "qty", "fieldtype": "Float", "in_list_view": 1, "label": "Кол-во", "reqd": 1},
  {"fieldname": "uom", "fieldtype": "Link", "label": "Ед.", "options": "UOM"},
  {"fieldname": "rate", "fieldtype": "Currency", "in_list_view": 1, "label": "Цена"},
  {"fieldname": "amount", "fieldtype": "Currency", "in_list_view": 1, "label": "Сумма"}
 ],
 "istable": 1,
 "links": [],
 "modified": "2026-09-19 12:00:00.000000",
 "modified_by": "Administrator",
 "module": "Habibi AI",
 "name": "AI Order Quote Item",
 "owner": "Administrator",
 "permissions": [],
 "sort_field": "modified",
 "sort_order": "DESC",
 "states": []
}
```

`habibi_ai/habibi_ai/doctype/ai_order_quote/ai_order_quote.json`:

```json
{
 "actions": [],
 "autoname": "AIQ-.#####",
 "creation": "2026-09-19 12:00:00.000000",
 "doctype": "DocType",
 "engine": "InnoDB",
 "field_order": [
  "engine_chat_id", "channel_doctype", "channel_name", "turn_id", "column_break_chat",
  "customer", "customer_name", "phone", "order_section", "fulfilment", "delivery_zone", "notes",
  "items", "totals_section", "currency", "total_taxes", "grand_total", "column_break_totals",
  "expires_on", "sales_order"
 ],
 "fields": [
  {"fieldname": "engine_chat_id", "fieldtype": "Int", "label": "Чат движка", "read_only": 1},
  {"fieldname": "channel_doctype", "fieldtype": "Link", "label": "Тип канального чата", "options": "DocType", "read_only": 1},
  {"fieldname": "channel_name", "fieldtype": "Dynamic Link", "label": "Канальный чат", "options": "channel_doctype", "read_only": 1},
  {"fieldname": "turn_id", "fieldtype": "Data", "label": "Ход", "read_only": 1},
  {"fieldname": "column_break_chat", "fieldtype": "Column Break"},
  {"fieldname": "customer", "fieldtype": "Link", "label": "Клиент", "options": "Customer", "read_only": 1},
  {"fieldname": "customer_name", "fieldtype": "Data", "in_list_view": 1, "label": "Имя", "read_only": 1},
  {"fieldname": "phone", "fieldtype": "Data", "label": "Телефон", "options": "Phone", "read_only": 1},
  {"fieldname": "order_section", "fieldtype": "Section Break", "label": "Заказ"},
  {"fieldname": "fulfilment", "fieldtype": "Select", "label": "Получение", "options": "Delivery\nPickup", "read_only": 1},
  {"description": "Имя зоны текстом: справочника Delivery Zone на сайте может не быть", "fieldname": "delivery_zone", "fieldtype": "Data", "label": "Зона доставки", "read_only": 1},
  {"fieldname": "notes", "fieldtype": "Small Text", "label": "Пожелания", "read_only": 1},
  {"fieldname": "items", "fieldtype": "Table", "label": "Позиции", "options": "AI Order Quote Item", "read_only": 1},
  {"fieldname": "totals_section", "fieldtype": "Section Break", "label": "Итог"},
  {"fieldname": "currency", "fieldtype": "Link", "label": "Валюта", "options": "Currency", "read_only": 1},
  {"fieldname": "total_taxes", "fieldtype": "Currency", "label": "Налоги", "options": "currency", "read_only": 1},
  {"fieldname": "grand_total", "fieldtype": "Currency", "in_list_view": 1, "label": "К оплате", "options": "currency", "read_only": 1},
  {"fieldname": "column_break_totals", "fieldtype": "Column Break"},
  {"fieldname": "expires_on", "fieldtype": "Datetime", "label": "Действует до", "read_only": 1},
  {"fieldname": "sales_order", "fieldtype": "Link", "in_list_view": 1, "label": "Заказ", "options": "Sales Order", "read_only": 1}
 ],
 "in_create": 1,
 "links": [],
 "modified": "2026-09-19 12:00:00.000000",
 "modified_by": "Administrator",
 "module": "Habibi AI",
 "name": "AI Order Quote",
 "owner": "Administrator",
 "permissions": [
  {"delete": 1, "read": 1, "report": 1, "role": "System Manager"}
 ],
 "sort_field": "modified",
 "sort_order": "DESC",
 "states": [],
 "title_field": "customer_name",
 "track_changes": 0
}
```

`ai_order_quote.py`:

```python
"""Расчёт заказа, который бот зачитал клиенту.

create_order принимает только номер расчёта: в ERP уходит ровно то, что
клиент услышал. Хранится в базе, а не в кэше — переживает перезапуск, и по
нему оператор разбирает спорный заказ.
"""

from frappe.model.document import Document


class AIOrderQuote(Document):
	pass
```

`ai_order_quote_item.py`:

```python
from frappe.model.document import Document


class AIOrderQuoteItem(Document):
	pass
```

- [ ] **Step 2: `habibi_ai/customers.py`**

```python
"""Клиент заказа: по привязке чата, по телефону или новый.

Клиента никогда не называет модель — только сервер по чату, из которого
пришёл ход, или по телефону, который клиент продиктовал. Иначе заказ можно
было бы оформить на чужое имя.
"""

import frappe

from habibi_ai.order_rules import normalize_phone


def linked_customer(channel_chat):
	"""Customer, к которому привязан канальный чат (строкой links), или None."""
	if not channel_chat:
		return None
	doctype, name = channel_chat
	if not frappe.db.exists(doctype, name):
		return None
	for row in frappe.get_doc(doctype, name).get("links") or []:
		if row.link_doctype == "Customer" and frappe.db.get_value("Customer", row.link_name, "disabled") == 0:
			return row.link_name
	return None


def find_by_phone(phone):
	"""Customer с тем же номером; сравнение — по нормализованной форме.

	В базе номера лежат как ввели: «+966 55 214 8890», «+77015550104». LIKE по
	последним цифрам сужает выборку, окончательно сравнивает normalize_phone.
	"""
	digits = phone.lstrip("+")
	candidates = frappe.get_all(
		"Customer",
		filters={"disabled": 0, "mobile_no": ["like", f"%{digits[-4:]}"]},
		fields=["name", "mobile_no"],
		order_by="creation asc",
		limit_page_length=0,
	)
	for candidate in candidates:
		if normalize_phone(candidate.mobile_no) == phone:
			return candidate.name
	return None


def create(customer_name, phone):
	"""Новый Customer. mobile_no на вставке ERPNext превращает в основной контакт."""
	group = frappe.db.get_single_value("Selling Settings", "customer_group") or frappe.db.get_value(
		"Customer Group", {"lft": 1}
	)
	territory = frappe.db.get_single_value("Selling Settings", "territory") or frappe.db.get_value(
		"Territory", {"lft": 1}
	)
	doc = frappe.get_doc(
		{
			"doctype": "Customer",
			"customer_name": customer_name,
			"customer_type": "Individual",
			"customer_group": group,
			"territory": territory,
			"mobile_no": phone,
		}
	)
	doc.insert(ignore_permissions=True)
	return doc.name


def link_chat(channel_chat, customer):
	"""Привязать канальный чат к клиенту — в следующий раз бот узнает его сам.

	Той же таблицей links, что правит карточка собеседника в консоли чатов
	habibi_telegram: оператор видит связь и может её снять.
	"""
	doctype, name = channel_chat
	if not frappe.db.exists(doctype, name) or not frappe.get_meta(doctype).has_field("links"):
		return
	doc = frappe.get_doc(doctype, name)
	if any(r.link_doctype == "Customer" and r.link_name == customer for r in doc.links):
		return
	doc.append("links", {"link_doctype": "Customer", "link_name": customer})
	doc.save(ignore_permissions=True)
```

- [ ] **Step 3: `habibi_ai/tools/orders.py` — общая часть и `quote_order`**

```python
"""Приём заказа: расчёт, который слышит клиент, и заказ ровно по нему.

Модель ведёт разговор, но цифр не называет и заказ не собирает: состав
сверяется с каталогом, итог и налог считает ERPNext, клиент берётся из чата
или телефона. create_order получает только номер расчёта — в ERP уходит то,
что зачитали клиенту, — и не срабатывает в том же ходе, что расчёт.
"""

import frappe
from frappe.utils import add_to_date, now_datetime, nowdate, strip_html

from habibi_ai import customers
from habibi_ai import order_rules as rules
from habibi_ai.habibi_ai.doctype.habibi_ai_settings.habibi_ai_settings import get_company
from habibi_ai.order_rules import Refusal
from habibi_ai.tools import tool
from habibi_ai.tools.hours import closed_warning
from habibi_ai.tools.menu import sellable_catalog

QUOTE = "AI Order Quote"
ZONE_DOCTYPE = "Delivery Zone"
FULFILMENT = {"delivery": "Delivery", "pickup": "Pickup"}
# Источник заказа по типу канального чата. Консоли отладки здесь нет
# намеренно: заказ из неё — проверка, а не заказ из канала.
SOURCE_BY_CHANNEL = {"Telegram Chat": "Telegram"}


def load_settings():
	company = get_company()
	if not company:
		raise Refusal(
			"Приём заказов в этой системе не настроен. Не оформляй заказ, предложи связаться с оператором."
		)
	price_list = frappe.db.get_single_value("Selling Settings", "selling_price_list")
	if not price_list:
		raise Refusal("Прайс-лист продаж не настроен — оформить заказ нельзя. Предложи оператора.")

	currency = frappe.db.get_value("Price List", price_list, "currency")
	company_currency = frappe.db.get_value("Company", company, "default_currency")
	if currency != company_currency:
		raise Refusal(
			f"Валюта прайс-листа «{price_list}» ({currency}) не совпадает с валютой компании "
			f"«{company}» ({company_currency}). Приём заказов настроен неверно — предложи оператора."
		)

	tax = frappe.db.get_value(
		"Sales Taxes and Charges Template", {"company": company, "is_default": 1, "disabled": 0}, "name"
	)
	return frappe._dict(company=company, price_list=price_list, currency=currency, tax=tax)


def build_sales_order(settings, lines, customer=None):
	"""Sales Order с посчитанными налогами и итогом — ещё не сохранённый.

	Один и тот же сборщик для расчёта и для заказа: иначе клиенту зачитали бы
	одну сумму, а в ERP легла бы другая. Цены — из строк (каталога или
	расчёта); ignore_pricing_rule — потому что расчёт правил цен не видит, и
	скидка, применённая только в заказе, разошлась бы с услышанным итогом.
	"""
	from erpnext.controllers.accounts_controller import get_taxes_and_charges

	today = nowdate()
	so = frappe.new_doc("Sales Order")
	so.update(
		{
			"company": settings.company,
			"customer": customer,
			"currency": settings.currency,
			"conversion_rate": 1,
			"selling_price_list": settings.price_list,
			"price_list_currency": settings.currency,
			"plc_conversion_rate": 1,
			"ignore_pricing_rule": 1,
			"transaction_date": today,
			"delivery_date": today,
			"taxes_and_charges": settings.tax,
		}
	)
	for line in lines:
		so.append(
			"items",
			{
				"item_code": line["item_code"],
				"item_name": line["item_name"],
				"qty": line["qty"],
				"rate": line["rate"],
				"price_list_rate": line["rate"],
				"uom": line["uom"],
				"stock_uom": line["uom"],
				"conversion_factor": 1,
				"delivery_date": today,
			},
		)
	if settings.tax:
		so.set("taxes", get_taxes_and_charges("Sales Taxes and Charges Template", settings.tax))
	so.calculate_taxes_and_totals()
	return so


def payable(so):
	"""К оплате: округлённый итог, если округление на сайте включено."""
	return float(so.rounded_total or so.grand_total)


def taxes_of(so):
	return [{"description": t.description, "amount": float(t.tax_amount or 0)} for t in so.taxes]


def rows_of(so):
	return [
		{"item_code": i.item_code, "item_name": i.item_name, "qty": i.qty, "amount": float(i.amount)}
		for i in so.items
	]


def _customer_line(name, phone):
	return f"Клиент: {name}, {phone}" if phone else f"Клиент: {name}"


def _delivery(zone, goods_total):
	if not frappe.db.exists("DocType", ZONE_DOCTYPE):
		raise Refusal("Доставка в этой системе не настроена. Предложи самовывоз или оператора.")
	zones = frappe.get_all(
		ZONE_DOCTYPE,
		filters={"is_active": 1},
		fields=["name", "delivery_fee", "free_above"],
		order_by="delivery_fee",
		limit_page_length=0,
	)
	matched = rules.match_zone(zone, zones)
	uom = frappe.db.get_value("Item", rules.DELIVERY_ITEM, "stock_uom")
	if not uom:
		raise Refusal("Позиция доставки не заведена — доставку оформить нельзя. Предложи оператора.")
	return rules.delivery_line(matched, goods_total, uom), matched["name"]


def _who(context, customer_name, phone):
	"""(Customer | None, имя, телефон) — из привязки чата или от клиента."""
	linked = customers.linked_customer(context.get("channel_chat"))
	if linked:
		name, mobile = frappe.db.get_value("Customer", linked, ["customer_name", "mobile_no"])
		return linked, name, rules.normalize_phone(mobile) or mobile

	name = str(customer_name or "").strip()
	if not name or not phone:
		raise Refusal("Для заказа нужны имя и телефон клиента. Спроси их и повтори quote_order.")
	normalized = rules.normalize_phone(phone)
	if not normalized:
		raise Refusal(f"«{phone}» не похоже на номер телефона. Переспроси номер вместе с кодом страны.")
	return None, name, normalized


QUOTE_SCHEMA = {
	"type": "object",
	"properties": {
		"items": {
			"type": "array",
			"description": "Весь заказ целиком, а не добавка к прошлому расчёту.",
			"items": {
				"type": "object",
				"properties": {
					"item_code": {"type": "string", "description": "Код или название позиции из get_menu"},
					"qty": {"type": "integer", "minimum": 1, "maximum": rules.MAX_QTY},
				},
				"required": ["item_code", "qty"],
			},
		},
		"fulfilment": {"type": "string", "enum": ["delivery", "pickup"]},
		"zone": {"type": "string", "description": "Зона доставки из get_delivery_zones; для самовывоза не нужна"},
		"customer_name": {"type": "string", "description": "Имя клиента, если система его ещё не знает"},
		"phone": {"type": "string", "description": "Телефон клиента, если система его ещё не знает"},
		"notes": {"type": "string", "description": "Пожелания для кухни, если клиент их назвал"},
	},
	"required": ["items", "fulfilment"],
}


@tool(
	name="quote_order",
	description=(
		"Расчёт заказа: сверяет состав с меню, считает доставку, налог и итог в ERP. "
		"Вызывай, когда клиент назвал, что хочет, и способ получения, — до того как "
		"называть итог. Ответ зачитай клиенту целиком и спроси, оформлять ли. "
		"Если система не знает клиента, ответ попросит имя и телефон."
	),
	input_schema=QUOTE_SCHEMA,
	context=True,
)
def quote_order(context, items=None, fulfilment=None, zone=None, customer_name=None, phone=None, notes=None):
	try:
		return _quote(context, items, fulfilment, zone, customer_name, phone, notes)
	except Refusal as e:
		return str(e)


def _quote(context, items, fulfilment, zone, customer_name, phone, notes):
	settings = load_settings()
	catalog = sellable_catalog(settings.price_list)
	if not catalog:
		raise Refusal("В меню нет позиций с действующими ценами — оформить заказ нельзя. Предложи оператора.")
	if fulfilment not in FULFILMENT:
		raise Refusal("Уточни у клиента: доставка или самовывоз? fulfilment — delivery или pickup.")

	lines = rules.resolve_lines(items, catalog)
	zone_name = None
	if fulfilment == "delivery":
		delivery, zone_name = _delivery(zone, sum(line["qty"] * line["rate"] for line in lines))
		lines.append(delivery)

	customer, name, phone = _who(context, customer_name, phone)
	so = build_sales_order(settings, lines, customer)
	channel = context.get("channel_chat") or (None, None)
	notes = str(notes or "").strip() or None

	quote = frappe.get_doc(
		{
			"doctype": QUOTE,
			"engine_chat_id": context.get("engine_chat_id"),
			"channel_doctype": channel[0],
			"channel_name": channel[1],
			"turn_id": context.get("turn_id"),
			"customer": customer,
			"customer_name": name,
			"phone": phone,
			"fulfilment": FULFILMENT[fulfilment],
			"delivery_zone": zone_name,
			"notes": notes,
			"items": [
				{
					"item_code": i.item_code,
					"item_name": i.item_name,
					"qty": i.qty,
					"uom": i.uom,
					"rate": i.rate,
					"amount": i.amount,
				}
				for i in so.items
			],
			"currency": settings.currency,
			"total_taxes": so.total_taxes_and_charges,
			"grand_total": payable(so),
			"expires_on": add_to_date(now_datetime(), minutes=int(rules.QUOTE_TTL.total_seconds() // 60)),
		}
	).insert(ignore_permissions=True)

	parts = [
		f"Расчёт {quote.name}, действует {int(rules.QUOTE_TTL.total_seconds() // 60)} минут.",
		_customer_line(name, phone),
		*rules.item_lines(rows_of(so), settings.currency),
		rules.total_line(payable(so), taxes_of(so), settings.currency),
	]
	if notes:
		parts.append(f"Пожелания: {notes}")
	warning = closed_warning(fulfilment)
	if warning:
		parts.append(warning)
	parts.append(
		"Зачитай клиенту состав и итог и спроси, оформлять ли. После его явного согласия вызови "
		f"create_order с quote_id «{quote.name}». Если клиент что-то меняет — сделай новый quote_order."
	)
	return "\n".join(parts)
```

- [ ] **Step 4: Регистрация** — в конец `habibi_ai/tools/__init__.py`:

```python
from habibi_ai.tools import orders  # noqa: E402,F401  регистрация при импорте пакета
```

- [ ] **Step 5: Миграция и быстрые тесты**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost migrate"` — без ошибок.
Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --app habibi_ai"` — PASS (регистрация нового модуля ничего не ломает).

- [ ] **Step 6: Commit**

```bash
git add habibi_ai/habibi_ai/doctype/ai_order_quote habibi_ai/habibi_ai/doctype/ai_order_quote_item habibi_ai/customers.py habibi_ai/tools/orders.py habibi_ai/tools/__init__.py
git commit -m "feat(orders): quote_order — расчёт заказа средствами ERP с сохранением"
```

---

### Task 7: `create_order`, опция источника, зависимость от ERPNext

**Files:**
- Modify: `habibi_ai/tools/orders.py`
- Modify: `habibi_ai/setup.py`
- Modify: `habibi_ai/hooks.py`

**Interfaces:**
- Consumes: `load_settings`, `build_sales_order`, `payable`, `taxes_of`, `rows_of`, `_customer_line`, `QUOTE`, `ZONE_DOCTYPE`, `SOURCE_BY_CHANNEL` (Task 6); `customers.*` (Task 6); `rules.check_quote`, `rules.money` (Task 4).
- Produces: инструмент `create_order(quote_id)`; `setup.install_order_source_option()`.

- [ ] **Step 1: `create_order`** — дописать в конец `habibi_ai/tools/orders.py`:

```python
@tool(
	name="create_order",
	description=(
		"Оформляет заказ по расчёту quote_order — черновиком, который подтвердит оператор. "
		"Вызывай только после явного согласия клиента на зачитанный расчёт. "
		"Говори «заказ оформлен» только пересказом ответа этого инструмента."
	),
	input_schema={
		"type": "object",
		"properties": {"quote_id": {"type": "string", "description": "Номер расчёта из ответа quote_order"}},
		"required": ["quote_id"],
	},
	context=True,
)
def create_order(context, quote_id=None):
	try:
		return _create(context, quote_id)
	except Refusal as e:
		return str(e)


def _create(context, quote_id):
	quote = frappe.get_doc(QUOTE, quote_id) if quote_id and frappe.db.exists(QUOTE, quote_id) else None
	verdict = rules.check_quote(quote.as_dict() if quote else None, context, now_datetime())
	if verdict == "done":
		return _order_text(frappe.get_doc("Sales Order", quote.sales_order), quote, repeated=True)

	settings = load_settings()
	# Клиент, привязка чата и заказ — одно целое: упал заказ — не должно
	# остаться ни нового клиента, ни привязки к нему
	frappe.db.savepoint("create_order")
	try:
		customer = quote.customer or customers.find_by_phone(quote.phone) or customers.create(
			quote.customer_name, quote.phone
		)
		if quote.channel_doctype and quote.channel_name:
			customers.link_chat((quote.channel_doctype, quote.channel_name), customer)
		lines = [
			{"item_code": r.item_code, "item_name": r.item_name, "qty": r.qty, "rate": r.rate, "uom": r.uom}
			for r in quote.items
		]
		so = build_sales_order(settings, lines, customer)
		_set_optional_fields(so, quote)
		so.insert(ignore_permissions=True)
		quote.db_set("sales_order", so.name)
	except Exception as e:
		frappe.db.rollback(save_point="create_order")
		frappe.log_error(title="create_order", message=frappe.get_traceback())
		raise Refusal(
			f"Не удалось оформить заказ: {strip_html(str(e))[:200]}. Не говори клиенту, что заказ создан; "
			"предложи связаться с оператором."
		) from e

	text = _order_text(so, quote)
	if abs(payable(so) - float(quote.grand_total)) >= 0.01:
		text += (
			f"\nВнимание: итог изменился — в расчёте было {rules.money(quote.grand_total)}, в заказе "
			f"{rules.money(payable(so))} {so.currency}. Назови клиенту новую сумму."
		)
	return text


def _set_optional_fields(so, quote):
	"""Поля, заведённые руками на конкретном сайте: ставим только существующие.

	custom_* на erp.habibi-erp.com есть, на naqwa их нет — там заказ должен
	создаваться так же, просто без этих пометок.
	"""
	meta = frappe.get_meta("Sales Order")
	values = {
		"custom_fulfilment_type": quote.fulfilment,
		"custom_agent_handled": 1,
		"custom_whatsapp_number": quote.phone,
		"custom_kitchen_notes": quote.notes,
	}
	if quote.delivery_zone and frappe.db.exists("DocType", ZONE_DOCTYPE) and frappe.db.exists(
		ZONE_DOCTYPE, quote.delivery_zone
	):
		values["custom_delivery_zone"] = quote.delivery_zone

	source = SOURCE_BY_CHANNEL.get(quote.channel_doctype)
	field = meta.get_field("custom_order_source")
	if source and field and source in (field.options or "").split("\n"):
		values["custom_order_source"] = source

	for fieldname, value in values.items():
		if value and meta.has_field(fieldname):
			so.set(fieldname, value)


def _order_text(so, quote, repeated=False):
	head = (
		f"Заказ {so.name} уже создан по этому расчёту — второй не создавался."
		if repeated
		else f"Заказ {so.name} создан — черновик, ждёт подтверждения оператора."
	)
	return "\n".join(
		[
			head,
			_customer_line(quote.customer_name, quote.phone),
			*rules.item_lines(rows_of(so), so.currency),
			rules.total_line(payable(so), taxes_of(so), so.currency),
			"Сообщи клиенту номер заказа и что оператор его подтвердит. Не обещай, что заказ уже готовят.",
		]
	)
```

- [ ] **Step 2: Опция источника** — в `habibi_ai/setup.py` добавить вызов `install_order_source_option()` последней строкой в `after_install` и в `after_migrate`, и функцию в конец файла:

```python
ORDER_SOURCE = "Telegram"


def install_order_source_option():
	"""Вариант Telegram в источнике заказа — там, где поле источника есть.

	Не фикстурой: custom_order_source заведён руками на одном сайте, и
	фикстура Property Setter разъехалась бы на все, где такого поля нет.
	Идемпотентно — вызывается на каждой миграции.
	"""
	name = frappe.db.get_value("Custom Field", {"dt": "Sales Order", "fieldname": "custom_order_source"})
	if not name:
		return
	field = frappe.get_doc("Custom Field", name)
	options = [o for o in (field.options or "").split("\n") if o]
	if ORDER_SOURCE in options:
		return
	field.options = "\n".join([*options, ORDER_SOURCE])
	field.save(ignore_permissions=True)
```

- [ ] **Step 3: Зависимость** — в `habibi_ai/hooks.py` заменить строку `required_apps = ["habibi_ui"]` на:

```python
# erpnext — потому что инструменты заказа и справочники ссылаются на Company,
# Customer, Sales Order: без него миграция приложения падает на Link.
required_apps = ["habibi_ui", "erpnext"]
```

- [ ] **Step 4: Миграция и все тесты**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost migrate && bench --site dev.localhost run-tests --app habibi_ai"`
Expected: миграция без ошибок, тесты PASS.

- [ ] **Step 5: Commit**

```bash
git add habibi_ai/tools/orders.py habibi_ai/setup.py habibi_ai/hooks.py
git commit -m "feat(orders): create_order — черновик Sales Order только по расчёту из прошлого хода"
```

---

### Task 8: Интеграционные тесты заказа на `dev.localhost`

**Files:**
- Test: `habibi_ai/tests/test_orders.py`

**Interfaces:**
- Consumes: `tools.execute(name, args, context)` (Task 1); `quote_order`, `create_order` (Tasks 6–7); `Habibi AI Settings` (Task 3).

Тесты заводят свою компанию `_Habibi Test Co` в KZT, прайс-лист, позиции и налоговый шаблон — не зависят от данных dev-сайта. Доставку ERP-уровнем здесь не проверяем: справочника `Delivery Zone` на dev-сайте нет, а заводить доктайп в тесте — это DDL с неявным commit. Правила доставки покрыты `test_order_rules`, ERP-путь — живой проверкой в Task 9.

- [ ] **Step 1: Тесты** — `habibi_ai/tests/test_orders.py`:

```python
"""Заказ целиком через ERPNext: расчёт, согласие в следующем ходе, черновик.

Проверяется то, что увидит модель, и то, что ляжет в ERP. Своя компания в KZT
и свой прайс-лист — чтобы не зависеть от того, что заведено на dev-сайте.
"""

import frappe
from frappe.tests import IntegrationTestCase

from habibi_ai import tools

CO = "_Habibi Test Co"
PRICE_LIST = "_Habibi Test Menu"
BURGER = "_HBT-BURGER"
COLA = "_HBT-COLA"
PHONE = "+77019990011"


def _setup_erp():
	if not frappe.db.exists("Company", CO):
		frappe.get_doc(
			{
				"doctype": "Company",
				"company_name": CO,
				"abbr": "HBTC",
				"default_currency": "KZT",
				"country": "Kazakhstan",
				"create_chart_of_accounts_based_on": "Standard Template",
				"chart_of_accounts": "Standard",
			}
		).insert()

	if not frappe.db.exists("Price List", PRICE_LIST):
		frappe.get_doc(
			{"doctype": "Price List", "price_list_name": PRICE_LIST, "currency": "KZT", "selling": 1, "enabled": 1}
		).insert()

	root_group = frappe.db.get_value("Item Group", {"lft": 1})
	for code, name, rate in ((BURGER, "Test Burger", 2490), (COLA, "Test Cola", 690)):
		if not frappe.db.exists("Item", code):
			frappe.get_doc(
				{
					"doctype": "Item",
					"item_code": code,
					"item_name": name,
					"item_group": root_group,
					"stock_uom": "Nos",
					"is_stock_item": 0,
					"is_sales_item": 1,
				}
			).insert()
		if not frappe.db.exists("Item Price", {"item_code": code, "price_list": PRICE_LIST}):
			frappe.get_doc(
				{"doctype": "Item Price", "item_code": code, "price_list": PRICE_LIST, "price_list_rate": rate}
			).insert()

	abbr = frappe.db.get_value("Company", CO, "abbr")
	account = f"_Test VAT 12% - {abbr}"
	if not frappe.db.exists("Account", account):
		parent = frappe.db.get_value("Account", {"company": CO, "account_type": "Tax", "is_group": 1}) or frappe.db.get_value(
			"Account", {"company": CO, "root_type": "Liability", "is_group": 1}
		)
		frappe.get_doc(
			{
				"doctype": "Account",
				"account_name": "_Test VAT 12%",
				"parent_account": parent,
				"company": CO,
				"account_type": "Tax",
				"tax_rate": 12,
			}
		).insert()
	if not frappe.db.exists("Sales Taxes and Charges Template", {"company": CO, "is_default": 1}):
		frappe.get_doc(
			{
				"doctype": "Sales Taxes and Charges Template",
				"title": "_Test KZ VAT",
				"company": CO,
				"is_default": 1,
				"taxes": [
					{
						"charge_type": "On Net Total",
						"account_head": account,
						"description": "VAT 12%",
						"rate": 12,
						"included_in_print_rate": 1,
					}
				],
			}
		).insert()

	frappe.db.set_single_value("Selling Settings", "selling_price_list", PRICE_LIST)
	frappe.db.set_single_value("Habibi AI Settings", "company", CO)


def ctx(turn, chat=501, channel=None):
	return {"turn_id": turn, "engine_chat_id": chat, "channel_chat": channel}


ORDER = {
	"items": [{"item_code": BURGER, "qty": 1}, {"item_code": "Test Cola", "qty": 2}],
	"fulfilment": "pickup",
	"customer_name": "Тест Клиент",
	"phone": "+7 (701) 999-00-11",
}


def quote_id(text):
	return text.split()[1].rstrip(",")


class TestЗаказ(IntegrationTestCase):
	@classmethod
	def setUpClass(cls):
		super().setUpClass()
		_setup_erp()

	def _quote(self, turn="t1", **kw):
		return tools.execute("quote_order", {**ORDER, **kw}, ctx(turn))

	def test_расчёт_считает_итог_и_ндс_в_erp(self):
		text = self._quote()
		# 2490 + 2×690 = 3870; НДС 12% внутри цены = 3870×12/112 = 414.64
		self.assertIn("Итого: 3 870 KZT, включая VAT 12% — 414.64 KZT", text)
		self.assertIn("Test Cola × 2 — 1 380 KZT", text)
		self.assertIn("Клиент: Тест Клиент, +77019990011", text)
		quote = frappe.get_doc("AI Order Quote", quote_id(text))
		self.assertEqual((quote.grand_total, quote.engine_chat_id, quote.turn_id), (3870, 501, "t1"))

	def test_заказ_в_том_же_ходе_отклоняется(self):
		qid = quote_id(self._quote(turn="t1"))
		result = tools.execute("create_order", {"quote_id": qid}, ctx("t1"))
		self.assertIn("дождись", result)
		self.assertFalse(frappe.db.get_value("AI Order Quote", qid, "sales_order"))

	def test_заказ_создаёт_черновик_с_суммой_расчёта(self):
		qid = quote_id(self._quote())
		result = tools.execute("create_order", {"quote_id": qid}, ctx("t2"))
		so_name = frappe.db.get_value("AI Order Quote", qid, "sales_order")
		self.assertIn(f"Заказ {so_name} создан — черновик", result)
		so = frappe.get_doc("Sales Order", so_name)
		self.assertEqual((so.docstatus, so.company, so.grand_total), (0, CO, 3870))
		self.assertEqual(frappe.db.get_value("Customer", so.customer, "mobile_no"), PHONE)

	def test_повтор_не_создаёт_второй_заказ(self):
		qid = quote_id(self._quote())
		first = tools.execute("create_order", {"quote_id": qid}, ctx("t2"))
		before = frappe.db.count("Sales Order", {"company": CO})
		second = tools.execute("create_order", {"quote_id": qid}, ctx("t3"))
		self.assertEqual(frappe.db.count("Sales Order", {"company": CO}), before)
		self.assertIn("уже создан", second)
		self.assertEqual(first.split()[1], second.split()[1])

	def test_клиент_находится_по_телефону_а_не_заводится_заново(self):
		tools.execute("create_order", {"quote_id": quote_id(self._quote())}, ctx("t2"))
		customers_before = frappe.db.count("Customer")
		# Тот же номер, записанный иначе, — тот же человек
		qid = quote_id(self._quote(customer_name="Другое Имя", phone="+7 701 999 00 11"))
		tools.execute("create_order", {"quote_id": qid}, ctx("t4"))
		self.assertEqual(frappe.db.count("Customer"), customers_before)

	def test_чужой_чат_не_видит_расчёт(self):
		qid = quote_id(self._quote())
		result = tools.execute("create_order", {"quote_id": qid}, ctx("t2", chat=999))
		self.assertIn("не найден", result)

	def test_неизвестная_позиция_не_доходит_до_erp(self):
		before = frappe.db.count("AI Order Quote")
		result = self._quote(items=[{"item_code": "пицца", "qty": 1}])
		self.assertIn("Нет в меню: «пицца»", result)
		self.assertEqual(frappe.db.count("AI Order Quote"), before)

	def test_без_телефона_бот_просит_спросить(self):
		self.assertIn("имя и телефон", self._quote(phone=None))

	def test_без_компании_приём_не_настроен(self):
		frappe.db.set_single_value("Habibi AI Settings", "company", None)
		try:
			self.assertIn("не настроен", self._quote())
		finally:
			frappe.db.set_single_value("Habibi AI Settings", "company", CO)


class TestПривязкаЧата(IntegrationTestCase):
	"""Совмещённая схема: чат без привязки — имя и телефон, после заказа
	чат привязан, и следующий расчёт их уже не просит."""

	@classmethod
	def setUpClass(cls):
		super().setUpClass()
		_setup_erp()

	def test_после_заказа_чат_узнаёт_клиента(self):
		if "habibi_telegram" not in frappe.get_installed_apps():
			self.skipTest("habibi_telegram не установлен")
		chat = frappe.get_doc(
			{"doctype": "Telegram Chat", "chat_id": "990011", "type": "private", "title": "Тест"}
		).insert(ignore_permissions=True)
		channel = ("Telegram Chat", chat.name)

		text = tools.execute("quote_order", ORDER, ctx("t1", channel=channel))
		tools.execute("create_order", {"quote_id": quote_id(text)}, ctx("t2", channel=channel))

		links = frappe.get_doc("Telegram Chat", chat.name).links
		self.assertEqual([(r.link_doctype) for r in links], ["Customer"])

		again = tools.execute(
			"quote_order", {"items": ORDER["items"], "fulfilment": "pickup"}, ctx("t3", channel=channel)
		)
		self.assertIn("Клиент: Тест Клиент", again)
```

- [ ] **Step 2: Прогон**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module habibi_ai.tests.test_orders"`
Expected: PASS. Если падает на создании компании/счёта (различия ERPNext v16 в плане счетов) — чинить фикстуру теста, а не код инструментов; если падает на коде — это находка, чинить код и дописать случай в `test_order_rules`, если он чистый.

Особо проверить по выводу:
- `test_заказ_создаёт_черновик…` — `mobile_no` у нового клиента заполнен. Если ERPNext v16 не переносит `mobile_no` при вставке Customer, `find_by_phone` не найдёт клиента и `test_клиент_находится_по_телефону` упадёт. Тогда в `customers.create` после `insert` добавить `frappe.db.set_value("Customer", doc.name, "mobile_no", phone)` и прогнать снова.

- [ ] **Step 3: Весь набор**

Run: `$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --app habibi_ai"`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add habibi_ai/tests/test_orders.py habibi_ai/customers.py
git commit -m "test(orders): заказ через ERPNext — расчёт, следующий ход, повтор, клиент по телефону"
```

---

### Task 9: Выкат, данные, промпты, живая проверка, документация

**Files:**
- Modify: `habibi_docker/habibi/docs/agent-core.md`
- Данные: `erp.habibi-erp.com` (Desk), Directus `ai.habibi-erp.com` (MCP `directus-habibi-ai`)

- [ ] **Step 1: Ревью и слияние** — прогнать `superpowers:requesting-code-review` по ветке, затем слить `feat/orders-and-hours` в `main` `habibi_ai` и запушить.

- [ ] **Step 2: Выкат — только с подтверждения пользователя.** По процедуре из `agent-core.md`, раздел 4: тег `v*` в `habibi_docker` собирает образ `habibi` с приложениями из их `main`; на сервере обновить тег, перезапустить и `bench --site erp.habibi-erp.com migrate`, `bench --site naqwa.habibi-erp.com migrate`. Проверить: `bench --site erp.habibi-erp.com console` → `frappe.get_meta("Sales Order").get_field("custom_order_source").options` содержит `Telegram`.

- [ ] **Step 3: Данные на `erp.habibi-erp.com`** — спросить у пользователя реальные часы (в промпте сейчас «ежедневно 9:00–21:00, доставка до 23:00» — это наследство, не эталон). Затем:
  - `Habibi AI Settings.company` = `Habibi Burger`;
  - `Working Hours` для `Habibi Burger`: `time_zone` = `Asia/Almaty`, семь строк «Работа» и семь «Доставка» по ответу пользователя.

- [ ] **Step 4: Directus** — через MCP `directus-habibi-ai`:
  - прочитать `ai_bots` (бот бургерной) и `ai_prompts` сценариев бота;
  - из `global_system_prompt` убрать абзац про часы работы и «минимальный заказ 500 рублей»;
  - в `chatbot_scenarios.tools` сценария заказа дописать `quote_order`, `create_order`, `get_working_hours` (в общий/справочный сценарий — `get_working_hours`);
  - в промпт сценария заказа дописать:

```
Режим работы — только из get_working_hours.
Состав и цены — из get_menu, доставка — из get_delivery_zones.
Когда клиент назвал заказ и способ получения — вызови quote_order с полным составом и зачитай ответ целиком. Спроси, оформлять ли.
После явного согласия — create_order с номером расчёта. Любое изменение состава — новый quote_order.
«Заказ оформлен» говори только пересказом ответа create_order. Отказ инструмента передай клиенту как есть.
```

  Показать пользователю итоговые тексты промптов до записи.

- [ ] **Step 5: Живая проверка** в консоли отладки (`/ui/ai`) на `erp.habibi-erp.com`:
  1. «до скольки работаете?» → ответ из справочника, трассировка показывает `get_working_hours`.
  2. «классик и две колы, доставка в центр» → `quote_order`; бот просит имя и телефон, потом зачитывает итог 4670 KZT с НДС 500.36.
  3. «да» → `create_order` в **следующем** ходе; в ERP `Sales Order` в состоянии `New`, компания `Habibi Burger`, итог 4670, строка доставки, `custom_agent_handled` = 1.
  4. Ещё раз «да» → «уже создан», второго заказа нет.
  5. Тот же диалог через Telegram-бота: после заказа у `Telegram Chat` в `links` появился Customer; следующий заказ не спрашивает телефон; источник — `Telegram`.
  Тестовые заказы после проверки — спросить пользователя: отменить или оставить.

- [ ] **Step 6: Документация** — в `habibi_docker/habibi/docs/agent-core.md`:
  - в таблице раздела 10 отметить **есть** у режима работы (`get_working_hours`, справочник `Working Hours`), клиента (`customers.py`: привязка чата, телефон) и заказа (`quote_order` + `create_order`);
  - убрать фразу «Режим работы пока живёт в персоне бота…»;
  - в «Инструмент, который пишет» добавить: контекст хода (`context=True`), расчёт → заказ по номеру, отказ в том же ходе, идемпотентность через `AI Order Quote.sales_order`;
  - в таблицу раздела 4 — строки «Компания для заказов → Habibi AI Settings» и «Режим работы → Working Hours», обе «выкат не нужен».

```bash
cd /Users/fsa/Projects/habibi/habibi_docker
git add habibi/docs/agent-core.md
git commit -m "docs(agent-core): приём заказов и режим работы — как устроено сейчас"
```
