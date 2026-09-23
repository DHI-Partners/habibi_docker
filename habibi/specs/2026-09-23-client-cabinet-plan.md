# Кабинет клиента — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Владелец мелкого бизнеса работает в простом кабинете внутри `habibi_ui`: видит заказы и переписки, принимает заказы с уведомлением клиента, ведёт меню, режим работы и данные компании для бота — без Desk.

**Architecture:** Общий механизм — в `habibi_ui`: настройки разделов `Cabinet Settings`, методы `habibi_ui.api.v1.cabinet.*`, которые режут поля по конфигурации, и реестр адаптеров и флагов через хуки. Всё предметное — в `habibi_ai` (он зависит от `habibi_ui`, а не наоборот): адаптер цены, заказы, переписки, режим работы, бизнес-профиль, флаги возможностей, пресет вертикали. Профиль уходит в system prompt новым необязательным полем запроса к движку `habibi_ai_engine`. Экраны — в `habibi_ui/frontend` под `/ui/c`.

**Tech Stack:** Frappe v16 / ERPNext v16 (Python 3.14, `unittest`, `frappe.tests.IntegrationTestCase`), Vite 7 + React 19 + TanStack Query 5 + Tailwind 4, Directus-расширение на TypeScript (vitest).

**Spec:** `habibi/specs/2026-09-23-client-cabinet-design.md` — читать вместе с планом.

**Отклонения от спеки** (зафиксированы здесь и правятся в спеке задачей 16):

1. Методы заказов, переписок, режима работы, профиля и Telegram живут в `habibi_ai.cabinet.*`, а не в `habibi_ui.api.v1.*`: `habibi_ai` объявляет `required_apps = ["habibi_ui", ...]`, и обратный импорт создал бы цикл. `habibi_ui` про `habibi_ai` не знает ничего — только хуки.
2. Флаги возможностей — два поля `Check` в `Habibi AI Settings` (`feature_delivery`, `feature_orders`), а не таблица: флагов два, таблица — лишняя сущность. Пустое значение = включено, чтобы на `erp.habibi-erp.com` бот не потерял инструменты после миграции.
3. Профиль попадает в промпт через новое поле `tenant_context` запроса `ai-process-message` — сейчас у движка нет способа принять текст от тенанта.

## Global Constraints

- Python: отступы — табы, `line-length = 110`, ruff по `pyproject.toml` приложения.
- Комментарии и докстринги — по-русски, объясняют «почему», в стиле соседнего кода.
- Имена тестов — по-русски (`test_лишнее_поле_не_пишется`), как в `habibi_ai/tests`.
- Модули без frappe — `habibi_ui/cabinet/fields.py`, `habibi_ai/features.py`, `habibi_ai/profile.py`, `habibi_ai/notify_rules.py`, `habibi_ai/preset_rules.py` — **не импортируют frappe**, их тесты идут без сайта.
- `habibi_ui` не импортирует `habibi_ai`. Связь — только хуки `habibi_cabinet_adapters` и `habibi_cabinet_features`.
- Ни одно поле вне `list_fields` / `form_fields` раздела не читается и не пишется методами кабинета. Запись — только `frappe.get_doc(...).save()` / `.insert()`, без `ignore_permissions`.
- Роли: `Habibi Owner`, `Habibi Staff`. Настройки (меню, зоны, режим работы, профиль, Telegram) `Habibi Staff` не видит.
- Порядок «принять»: сначала переход заказа, потом уведомление. Сорвалась отправка — заказ остаётся принятым.
- При изменении JSON доктайпа обязательно обновлять `"modified"` — иначе `bench migrate` изменения не подхватит.
- TypeScript: 2 пробела, двойные кавычки, импорты относительные, как в `frontend/src`. Модули фронта не импортируют друг друга, только `shared`.
- Ветки: `habibi_ui`, `habibi_ai` — `feat/client-cabinet` от `main`; `habibi_ai_engine` — `feat/tenant-context` от `main`; `habibi_docker` — `main`.

## Review Focus

1. **Раздел, чей DocType или поле отсутствует на сайте** (`Delivery Zone` без `habibi_core`, как на `dev.localhost`) — раздел молча выпадает из `config()`, остальной кабинет работает. Тест — задача 3.
2. **Сайт без воркфлоу у Sales Order** (`dev.localhost`) — «Принять» = submit, «Отклонить» = удаление черновика; кнопки есть. Тест — задача 8.
3. **Заказ без канального чата** (создан вручную в Desk, попал в раздел) — уведомление не предлагается, переход работает. Тест — задача 8.
4. **Повторный `apply-preset`** после того, как владелец заполнил правила и поправил шаблон, — ничего не перетирается. Тест — задача 12.
5. **Флаги на сайте, где настройки ни разу не сохранялись** (`erp.habibi-erp.com` после миграции) — обе возможности включены, бот не теряет `quote_order`. Тест — задача 5.

## Как запускать команды

Все команды — из `/Users/fsa/Projects/habibi/habibi_docker`. Dev-бенч живёт в devcontainer, репозитории смонтированы в `/workspace/repos/<app>` (на хосте — `/Users/fsa/Projects/habibi/<app>`).

```bash
DC="docker compose -f .devcontainer/docker-compose.yml"
PY=/workspace/development/frappe-bench/env/bin/python
# быстрые тесты без сайта:
$DC exec -T frappe bash -lc "cd /workspace/repos/<app> && $PY -m unittest <модуль> -v"
# тесты на сайте:
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module <модуль>"
# миграция после изменения доктайпов:
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost migrate"
# фронт:
$DC exec -T frappe bash -lc "cd /workspace/repos/habibi_ui && yarn typecheck && yarn build"
```

Если контейнер не поднят: запустить Docker Desktop, затем `./habibi/dev.sh up`.

Движок (`habibi_ai_engine`) тестируется на хосте: `cd /Users/fsa/Projects/habibi/habibi_ai_engine/extensions/ai && npm test`.

## Карта файлов

| Файл | Что | Задача |
|---|---|---|
| `habibi_ai_engine/extensions/ai/src/process-message/utils/system-prompt.ts` | новый: `composeSystemPrompt` | 1 |
| `habibi_ai_engine/extensions/ai/src/process-message/index.ts`, `types.ts` | поле `tenant_context` | 1 |
| `habibi_ui/habibi_ui/cabinet/fields.py` | новый, без frappe: разбор строк полей, фильтр значений и фильтров | 2 |
| `habibi_ui/habibi_ui/cabinet/registry.py` | новый: адаптеры и флаги из хуков | 3 |
| `habibi_ui/habibi_ui/habibi_ui/doctype/cabinet_settings/`, `cabinet_section/` | новые доктайпы | 3 |
| `habibi_ui/habibi_ui/api/v1/cabinet.py` | новый: `config/list/get/save/delete` | 3 |
| `habibi_ui/habibi_ui/fixtures/role.json`, `hooks.py` | роли `Habibi Owner/Staff`, `role_home_page` | 4 |
| `habibi_ui/habibi_ui/api/v1/session.py`, `typegen.py` | `Me.home`, типы кабинета | 4 |
| `habibi_ai_engine` → `habibi_ai/engine.py` | `step(..., tenant_context=None)` | 5 |
| `habibi_ai/habibi_ai/features.py` | новый, без frappe: какие инструменты предлагать | 5 |
| `habibi_ai/habibi_ai/profile.py` | новый, без frappe: профиль → текст промпта | 5 |
| `habibi_ai/habibi_ai/habibi_ai/doctype/business_profile*/` | новые доктайпы | 5 |
| `habibi_ai/habibi_ai/habibi_ai/doctype/habibi_ai_settings/` | + флаги, действия воркфлоу | 5, 8 |
| `habibi_ai/habibi_ai/api.py` | `run_turn` шлёт профиль, режет инструменты флагами | 5 |
| `habibi_ai/habibi_ai/cabinet/adapters.py` | новый: `@selling_price` | 6 |
| `habibi_ai/habibi_ai/hooks.py` | хуки кабинета, doc_events realtime | 6, 11 |
| `habibi_ai/habibi_ai/notify_rules.py` | новый, без frappe: шаблон уведомления, вид действия | 7 |
| `habibi_ai/habibi_ai/cabinet/orders.py` | новый: действия и уведомление | 8 |
| `habibi_ai/habibi_ai/cabinet/chats.py` | новый: переписки | 9 |
| `habibi_ai/habibi_ai/cabinet/settings.py` | новый: режим работы, профиль, Telegram | 10 |
| `habibi_ai/habibi_ai/cabinet/realtime.py` | новый: события | 11 |
| `habibi_ai/habibi_ai/preset_rules.py` | новый, без frappe: слияние пресета | 12 |
| `habibi_ai/habibi_ai/presets/food.json`, `presets.py`, `commands/__init__.py` | пресет и команда | 12 |
| `habibi_ui/frontend/src/features/cabinet/**` | экраны кабинета | 13–15 |
| `habibi_ui/package.json` | скрипт `typecheck` | 13 |
| спека, `habibi/docs/` | правки по итогам | 16 |

---

### Task 0: Ветки и окружение

**Files:** нет изменений кода.

- [ ] **Step 1: Ветки**

```bash
for r in habibi_ui habibi_ai; do cd /Users/fsa/Projects/habibi/$r && git checkout main && git pull && git checkout -b feat/client-cabinet; done
cd /Users/fsa/Projects/habibi/habibi_ai_engine && git checkout main && git pull && git checkout -b feat/tenant-context
```

- [ ] **Step 2: Бенч поднят, тесты зелёные до начала**

```bash
cd /Users/fsa/Projects/habibi/habibi_docker && ./habibi/dev.sh up
DC="docker compose -f .devcontainer/docker-compose.yml"
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --app habibi_ui && bench --site dev.localhost run-tests --app habibi_ai"
```

Expected: все тесты проходят. Если нет — остановиться и сообщить: чинить чужие падения в рамках плана нельзя.

- [ ] **Step 3: Имена действий воркфлоу на проде (только чтение)**

```bash
ssh habibi 'docker exec habibi_docker-backend-1 bash -lc "cd /home/frappe/frappe-bench && echo \"print([(t.state, t.action, t.next_state) for t in frappe.get_doc(\\\"Workflow\\\", \\\"Habibi Burger Order\\\").transitions])\" | bench --site erp.habibi-erp.com console"'
```

Записать действие перехода `New → Confirmed` и действие перехода в `Cancelled` из `New`. Они нужны в задаче 12 (`food.json`, ключи `accept_action`, `reject_action`). Если имена отличаются от `Confirm` / `Cancel`, подставить фактические.

---

### Task 1: Движок принимает `tenant_context`

**Files:**
- Create: `habibi_ai_engine/extensions/ai/src/process-message/utils/system-prompt.ts`
- Create: `habibi_ai_engine/extensions/ai/src/process-message/utils/system-prompt.test.ts`
- Modify: `habibi_ai_engine/extensions/ai/src/process-message/index.ts:24-31,90-92`
- Modify: `habibi_ai_engine/extensions/ai/src/process-message/types.ts:27-45`

**Interfaces:**
- Produces: запрос `POST /ai-process-message` принимает необязательное `tenant_context: string`. Текст дописывается **после** `global_system_prompt` и инструкции сценария. Старые клиенты без поля работают как раньше.

- [ ] **Step 1: Тест**

```ts
// src/process-message/utils/system-prompt.test.ts
import { describe, expect, it } from "vitest";

import { composeSystemPrompt } from "./system-prompt";

describe("composeSystemPrompt", () => {
  it("склеивает промпт бота, инструкцию и контекст тенанта по порядку", () => {
    expect(composeSystemPrompt("Ты бот.", "Сценарий.", "О компании: X")).toBe(
      "Ты бот.\n\nСценарий.\n\nО компании: X"
    );
  });

  it("без контекста тенанта — как раньше", () => {
    expect(composeSystemPrompt("Ты бот.", "Сценарий.", undefined)).toBe("Ты бот.\n\nСценарий.");
  });

  it("пустые и пробельные части пропускаются", () => {
    expect(composeSystemPrompt("", "Сценарий.", "   ")).toBe("Сценарий.");
  });

  it("не строка в tenant_context игнорируется", () => {
    expect(composeSystemPrompt("Ты бот.", "", 42 as unknown as string)).toBe("Ты бот.");
  });
});
```

- [ ] **Step 2: Запустить — падает**

Run: `cd /Users/fsa/Projects/habibi/habibi_ai_engine/extensions/ai && npx vitest run src/process-message/utils/system-prompt.test.ts`
Expected: FAIL — `Cannot find module './system-prompt'`.

- [ ] **Step 3: Реализация**

```ts
// src/process-message/utils/system-prompt.ts
/**
 * System prompt хода: промпт бота, инструкция сценария, контекст тенанта.
 *
 * Контекст тенанта присылает habibi_ai — это данные компании, которые владелец
 * заполнил в кабинете. Он идёт последним: общие правила бота и сценария
 * задают поведение, а данные компании — факты, на которые оно опирается.
 * Не строка — игнорируется: поле приходит по сети, и число или объект не
 * должны превратиться в "[object Object]" внутри промпта.
 */
export function composeSystemPrompt(
  globalPrompt: string,
  instruction: string,
  tenantContext: string | undefined
): string {
  const context = typeof tenantContext === "string" ? tenantContext : "";
  return [globalPrompt, instruction, context]
    .map((part) => (part || "").trim())
    .filter(Boolean)
    .join("\n\n");
}
```

В `types.ts` в `ProcessMessageRequest` после `tools?`:

```ts
  /**
   * Данные компании для промпта. Собирает habibi_ai из бизнес-профиля
   * тенанта; движок только дописывает текст в конец system prompt.
   */
  tenant_context?: string;
```

В `index.ts` — деструктуризация и сборка:

```ts
      const {
        chat_id,
        user_message,
        bot_id,
        turn = [],
        tools = [],
        debug,
        tenant_context,
      }: ProcessMessageRequest = req.body;
```

```ts
      const systemPrompt = composeSystemPrompt(bot.global_system_prompt || "", instruction, tenant_context);
```

и импорт `import { composeSystemPrompt } from "./utils/system-prompt";` рядом с остальными импортами `./utils/*`.

- [ ] **Step 4: Тесты и сборка**

Run: `cd /Users/fsa/Projects/habibi/habibi_ai_engine/extensions/ai && npm test && npm run build`
Expected: все тесты PASS, сборка без ошибок.

- [ ] **Step 5: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai_engine && git add extensions/ai/src && git commit -m "feat(agent): контекст тенанта дописывается в system prompt"
```

Выкатка движка — по `habibi_ai_engine/README.md`, после мержа. Поле обратно совместимо в обе стороны: старый движок его игнорирует, поэтому порядок выкатки `habibi_ai` и движка не важен.

---

### Task 2: Фильтр полей раздела (без frappe)

**Files:**
- Create: `habibi_ui/habibi_ui/cabinet/__init__.py` (пустой)
- Create: `habibi_ui/habibi_ui/cabinet/fields.py`
- Test: `habibi_ui/habibi_ui/tests/test_cabinet_fields.py`

**Interfaces:**
- Produces:
  - `FieldSpec(fieldname: str, label: str | None, adapter: bool)` — frozen dataclass.
  - `parse_fields(text: str | None) -> list[FieldSpec]` — строки `fieldname`, `fieldname:Подпись`, `@adapter:Подпись`; пустые строки и дубли пропускаются.
  - `split_values(values: dict, specs: list[FieldSpec]) -> tuple[dict, dict]` — `(обычные, адаптеры)`, всё остальное отброшено; имя адаптера без `@`.
  - `merge_filters(base: str | None, user: list | None, allowed: set[str]) -> list[list]` — фильтры `[[field, op, value], ...]`: базовые (JSON-объект `{field: value}` или список троек) плюс пользовательские только по `allowed`.

- [ ] **Step 1: Тест**

```python
"""Фильтр полей раздела кабинета — граница того, что владелец читает и пишет.

Без frappe: это главный тест безопасности кабинета, и он должен идти за
секунды, а не ждать сайт.
"""

import unittest

from habibi_ui.cabinet.fields import FieldSpec, merge_filters, parse_fields, split_values


class TestParseFields(unittest.TestCase):
	def test_имя_и_подпись(self):
		self.assertEqual(
			parse_fields("item_name:Название\nitem_group"),
			[FieldSpec("item_name", "Название", False), FieldSpec("item_group", None, False)],
		)

	def test_адаптер_помечается_и_теряет_собаку(self):
		self.assertEqual(parse_fields("@selling_price:Цена"), [FieldSpec("selling_price", "Цена", True)])

	def test_пустые_строки_пробелы_и_дубли_пропускаются(self):
		self.assertEqual(parse_fields("  a  \n\n a:Другая\n"), [FieldSpec("a", None, False)])

	def test_пустой_текст(self):
		self.assertEqual(parse_fields(None), [])
		self.assertEqual(parse_fields(""), [])


class TestSplitValues(unittest.TestCase):
	SPECS = parse_fields("item_name\n@selling_price")

	def test_лишнее_поле_не_пишется(self):
		plain, adapters = split_values({"item_name": "Бургер", "valuation_rate": 1, "owner": "x"}, self.SPECS)
		self.assertEqual(plain, {"item_name": "Бургер"})
		self.assertEqual(adapters, {})

	def test_адаптер_отдельно(self):
		plain, adapters = split_values({"selling_price": 2490}, self.SPECS)
		self.assertEqual(plain, {})
		self.assertEqual(adapters, {"selling_price": 2490})

	def test_адаптер_с_собакой_в_ключе_не_принимается(self):
		# Ключи приходят с фронта; "@selling_price" — не наш формат, и пропускать
		# его значило бы иметь два имени у одного поля.
		plain, adapters = split_values({"@selling_price": 1}, self.SPECS)
		self.assertEqual((plain, adapters), ({}, {}))

	def test_служебные_поля_не_пишутся_даже_если_перечислены(self):
		specs = parse_fields("name\nowner\ndocstatus\nitem_name")
		plain, _ = split_values({"name": "X", "owner": "y", "docstatus": 1, "item_name": "Б"}, specs)
		self.assertEqual(plain, {"item_name": "Б"})


class TestMergeFilters(unittest.TestCase):
	def test_базовый_фильтр_не_снимается(self):
		result = merge_filters('{"disabled": 0}', [["disabled", "=", 1]], {"item_name"})
		self.assertEqual(result, [["disabled", "=", 0]])

	def test_пользовательский_только_по_разрешённым(self):
		result = merge_filters(None, [["item_name", "like", "%бур%"], ["valuation_rate", ">", 0]], {"item_name"})
		self.assertEqual(result, [["item_name", "like", "%бур%"]])

	def test_базовый_списком_троек(self):
		self.assertEqual(merge_filters('[["docstatus", "<", 2]]', None, set()), [["docstatus", "<", 2]])

	def test_недопустимый_оператор_отбрасывается(self):
		self.assertEqual(merge_filters(None, [["item_name", "; drop", "x"]], {"item_name"}), [])

	def test_битый_json_базы_это_ошибка_настройки(self):
		with self.assertRaises(ValueError):
			merge_filters("{oops", None, set())
```

- [ ] **Step 2: Запустить — падает**

Run: `$DC exec -T frappe bash -lc "cd /workspace/repos/habibi_ui && $PY -m unittest habibi_ui.tests.test_cabinet_fields -v"`
Expected: FAIL — `ModuleNotFoundError: No module named 'habibi_ui.cabinet'`.

- [ ] **Step 3: Реализация**

```python
"""Какие поля раздела кабинета видны и какие пишутся.

Без frappe: это граница данных кабинета, и её тесты не должны ждать сайт.
Права Frappe работают поверх — этот модуль их не заменяет, а сужает.
"""

import json
from dataclasses import dataclass

# Эти поля не пишутся никогда, даже если их по ошибке перечислили в разделе:
# ими управляет жизненный цикл документа, а не владелец бизнеса.
SYSTEM_FIELDS = frozenset(
	{"name", "owner", "creation", "modified", "modified_by", "docstatus", "idx", "doctype", "parent"}
)

# Операторы фильтра, которые кабинет пропускает. Остальное — не ошибка, а мусор
# с фронта, и он молча отбрасывается.
OPERATORS = frozenset({"=", "!=", "<", ">", "<=", ">=", "like", "not like", "in", "not in", "is"})


@dataclass(frozen=True)
class FieldSpec:
	fieldname: str
	label: str | None
	adapter: bool


def parse_fields(text):
	"""Строки раздела: `fieldname`, `fieldname:Подпись`, `@adapter:Подпись`."""
	specs, seen = [], set()
	for raw in (text or "").splitlines():
		line = raw.strip()
		if not line:
			continue
		name, _, label = line.partition(":")
		name = name.strip()
		adapter = name.startswith("@")
		name = name.lstrip("@")
		if not name or name in seen:
			continue
		seen.add(name)
		specs.append(FieldSpec(name, label.strip() or None, adapter))
	return specs


def split_values(values, specs):
	"""Разделить присланное на поля документа и адаптеры; остальное выбросить."""
	plain_names = {s.fieldname for s in specs if not s.adapter} - SYSTEM_FIELDS
	adapter_names = {s.fieldname for s in specs if s.adapter}
	plain = {k: v for k, v in (values or {}).items() if k in plain_names}
	adapters = {k: v for k, v in (values or {}).items() if k in adapter_names}
	return plain, adapters


def merge_filters(base, user, allowed):
	"""Базовый фильтр раздела AND пользовательский.

	Пользовательский фильтр по полю из базового отбрасывается целиком: иначе
	`disabled = 1` рядом с базовым `disabled = 0` дал бы пустой список, а
	`!=` — обход. Базовый фильтр задаёт супер-админ; битый JSON — ошибка
	настройки, и она должна быть видна, а не превращаться в «без фильтра».
	"""
	result = []
	if base:
		parsed = json.loads(base)
		if isinstance(parsed, dict):
			result = [[k, "=", v] for k, v in parsed.items()]
		else:
			result = [list(f) for f in parsed]
	locked = {f[0] for f in result}
	for f in user or []:
		if not isinstance(f, list | tuple) or len(f) != 3:
			continue
		field, op, value = f
		if field in allowed and field not in locked and str(op).lower() in OPERATORS:
			result.append([field, str(op).lower(), value])
	return result
```

`json.loads` бросает `json.JSONDecodeError` — это подкласс `ValueError`, тест проходит.

- [ ] **Step 4: Тесты проходят**

Run: та же команда. Expected: PASS, 13 тестов.

- [ ] **Step 5: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ui && git add habibi_ui/cabinet habibi_ui/tests/test_cabinet_fields.py && git commit -m "feat(cabinet): фильтр полей и фильтров раздела без frappe"
```

---

### Task 3: Настройки кабинета и методы `cabinet.*`

**Files:**
- Create: `habibi_ui/habibi_ui/habibi_ui/doctype/__init__.py` (пустой, если нет)
- Create: `habibi_ui/habibi_ui/habibi_ui/doctype/cabinet_section/{__init__.py,cabinet_section.json,cabinet_section.py}`
- Create: `habibi_ui/habibi_ui/habibi_ui/doctype/cabinet_settings/{__init__.py,cabinet_settings.json,cabinet_settings.py}`
- Create: `habibi_ui/habibi_ui/cabinet/registry.py`
- Create: `habibi_ui/habibi_ui/api/v1/cabinet.py`
- Test: `habibi_ui/habibi_ui/tests/test_cabinet_api.py`

**Interfaces:**
- Consumes: `parse_fields`, `split_values`, `merge_filters` (задача 2).
- Produces:
  - хук `habibi_cabinet_adapters = {"<name>": "dotted.path.to.object"}`; объект имеет `label: str`, `fieldtype: str`, `doctype: str`, `read(names: list[str]) -> dict[str, Any]`, `write(doc, value) -> None`, `editable() -> bool`;
  - хук `habibi_cabinet_features = ["dotted.path.fn"]`; `fn() -> set[str]` — включённые флаги;
  - `habibi_ui.cabinet.registry.adapter(name) -> object | None`, `enabled_features() -> set[str]`;
  - датаклассы `CabinetField(fieldname, label, fieldtype, options, reqd, read_only)`, `CabinetSection(key, label, icon, kind, screen, doctype, can_create, can_edit, can_delete, list_fields: list[CabinetField], form_fields: list[CabinetField])`;
  - методы `habibi_ui.api.v1.cabinet.config() -> list[dict]`, `list(section, filters=None, start=0, page_length=20) -> {"rows": list[dict], "has_more": bool}`, `get(section, name) -> dict`, `save(section, values, name=None) -> dict`, `delete(section, name) -> None`.

- [ ] **Step 1: Доктайпы**

`cabinet_section.json` (child, `istable: 1`, module `Habibi UI`, `"modified": "2026-09-23 12:00:00.000000"`), поля по порядку:

| fieldname | fieldtype | options / свойства |
|---|---|---|
| `key` | Data | reqd, in_list_view |
| `label` | Data | reqd, in_list_view |
| `icon` | Data | |
| `kind` | Select | `generic\ncustom`, default `generic`, reqd, in_list_view |
| `screen` | Data | depends_on `eval:doc.kind=='custom'` |
| `ref_doctype` | Link | `DocType`, depends_on `eval:doc.kind=='generic'` |
| `list_fields` | Small Text | depends_on generic |
| `form_fields` | Small Text | depends_on generic |
| `base_filters` | Code | options `JSON`, depends_on generic |
| `can_create` | Check | |
| `can_edit` | Check | |
| `can_delete` | Check | |
| `roles` | Small Text | «роль на строку; пусто — все роли кабинета» |
| `feature` | Data | |

`cabinet_settings.json` (single, `issingle: 1`, module `Habibi UI`, тот же `modified`): одно поле `sections` — Table, options `Cabinet Section`. Права: `System Manager` — read/write/create.

`cabinet_section.py` / `cabinet_settings.py` — пустые классы `Document`. В `CabinetSettings.validate` проверить уникальность `key` и корректность JSON `base_filters`:

```python
import json

import frappe
from frappe import _
from frappe.model.document import Document


class CabinetSettings(Document):
	def validate(self):
		seen = set()
		for row in self.sections:
			if row.key in seen:
				frappe.throw(_("Раздел с ключом {0} уже есть").format(row.key))
			seen.add(row.key)
			if row.base_filters:
				try:
					json.loads(row.base_filters)
				except ValueError:
					frappe.throw(_("Раздел {0}: базовый фильтр — не JSON").format(row.key))
```

Run: `bench --site dev.localhost migrate`. Expected: без ошибок, `Cabinet Settings` открывается в Desk.

- [ ] **Step 2: Тест методов**

Тестовый раздел строится на `ToDo` — он есть на любом сайте, в том числе без `habibi_ai`.

```python
from unittest.mock import patch

import frappe
from frappe.tests import IntegrationTestCase

from habibi_ui.api.v1 import cabinet

SECTION = {
	"key": "todo",
	"label": "Дела",
	"kind": "generic",
	"ref_doctype": "ToDo",
	"list_fields": "description:Что сделать\nstatus",
	"form_fields": "description\npriority",
	"base_filters": '{"status": "Open"}',
	"can_create": 1,
	"can_edit": 1,
}


class TestCabinetApi(IntegrationTestCase):
	def setUp(self):
		frappe.set_user("Administrator")
		settings = frappe.get_single("Cabinet Settings")
		settings.sections = []
		settings.append("sections", SECTION)
		settings.save()

	def tearDown(self):
		frappe.set_user("Administrator")
		frappe.db.rollback()

	def test_config_отдаёт_раздел_с_метой_полей(self):
		(section,) = [s for s in cabinet.config() if s["key"] == "todo"]
		self.assertEqual([f["fieldname"] for f in section["list_fields"]], ["description", "status"])
		self.assertEqual(section["list_fields"][0]["label"], "Что сделать")
		self.assertEqual(section["form_fields"][1]["fieldtype"], "Select")

	def test_раздел_с_несуществующим_полем_выпадает(self):
		settings = frappe.get_single("Cabinet Settings")
		settings.append("sections", {**SECTION, "key": "broken", "form_fields": "no_such_field"})
		settings.save()
		keys = [s["key"] for s in cabinet.config()]
		self.assertIn("todo", keys)
		self.assertNotIn("broken", keys)

	def test_раздел_с_несуществующим_доктайпом_выпадает(self):
		settings = frappe.get_single("Cabinet Settings")
		settings.append("sections", {**SECTION, "key": "ghost"})
		settings.save()
		# Link не даст сохранить несуществующий DocType — так и бывает на сайте,
		# где DocType удалили после настройки. Имитируем прямой записью.
		frappe.db.set_value("Cabinet Section", settings.sections[-1].name, "ref_doctype", "Delivery Zone Ghost")
		self.assertNotIn("ghost", [s["key"] for s in cabinet.config()])

	def test_list_только_поля_списка_и_базовый_фильтр(self):
		open_ = frappe.get_doc({"doctype": "ToDo", "description": "открытое"}).insert()
		frappe.get_doc({"doctype": "ToDo", "description": "закрытое", "status": "Closed"}).insert()
		rows = cabinet.list("todo", filters=[["status", "=", "Closed"]])["rows"]
		names = [r["name"] for r in rows]
		self.assertIn(open_.name, names)
		self.assertTrue(all(set(r) <= {"name", "description", "status"} for r in rows))
		self.assertFalse(any(r["status"] == "Closed" for r in rows))

	def test_save_пишет_только_поля_формы(self):
		result = cabinet.save("todo", {"description": "новое", "priority": "High", "allocated_to": "x@y.z"})
		doc = frappe.get_doc("ToDo", result["name"])
		self.assertEqual(doc.priority, "High")
		self.assertFalse(doc.allocated_to)

	def test_save_без_права_создавать_запрещён(self):
		settings = frappe.get_single("Cabinet Settings")
		settings.sections[0].can_create = 0
		settings.save()
		with self.assertRaises(frappe.PermissionError):
			cabinet.save("todo", {"description": "нельзя"})

	def test_delete_без_права_запрещён(self):
		todo = frappe.get_doc({"doctype": "ToDo", "description": "x"}).insert()
		with self.assertRaises(frappe.PermissionError):
			cabinet.delete("todo", todo.name)

	def test_get_чужого_раздела_по_базовому_фильтру_не_отдаётся(self):
		closed = frappe.get_doc({"doctype": "ToDo", "description": "закрытое", "status": "Closed"}).insert()
		with self.assertRaises(frappe.DoesNotExistError):
			cabinet.get("todo", closed.name)

	def test_раздел_скрыт_без_флага(self):
		settings = frappe.get_single("Cabinet Settings")
		settings.sections[0].feature = "delivery"
		settings.save()
		with patch("habibi_ui.cabinet.registry.enabled_features", return_value=set()):
			self.assertNotIn("todo", [s["key"] for s in cabinet.config()])
		with patch("habibi_ui.cabinet.registry.enabled_features", return_value={"delivery"}):
			self.assertIn("todo", [s["key"] for s in cabinet.config()])

	def test_раздел_скрыт_от_чужой_роли(self):
		settings = frappe.get_single("Cabinet Settings")
		settings.sections[0].roles = "Habibi Owner"
		settings.save()
		with patch("frappe.get_roles", return_value=["Habibi Staff"]):
			self.assertNotIn("todo", [s["key"] for s in cabinet.config()])

	def test_неизвестный_раздел(self):
		with self.assertRaises(frappe.DoesNotExistError):
			cabinet.list("nope")
```

- [ ] **Step 3: Запустить — падает**

Run: `bench --site dev.localhost run-tests --module habibi_ui.tests.test_cabinet_api`
Expected: FAIL — `ImportError: cannot import name 'cabinet'`.

- [ ] **Step 4: Реестр**

```python
"""Адаптеры полей и флаги возможностей — из хуков приложений.

habibi_ui не знает, какие приложения стоят на сайте: адаптер цены живёт в
habibi_ai, и прямой импорт отсюда создал бы цикл зависимостей.
"""

import frappe


def adapter(name):
	paths = frappe.get_hooks("habibi_cabinet_adapters") or {}
	# get_hooks для словаря отдаёт списки значений: последнее приложение побеждает
	path = paths.get(name)
	if not path:
		return None
	if isinstance(path, list):
		path = path[-1]
	return frappe.get_attr(path)


def enabled_features():
	result = set()
	for path in frappe.get_hooks("habibi_cabinet_features") or []:
		result |= set(frappe.get_attr(path)())
	return result
```

- [ ] **Step 5: Методы**

```python
"""Кабинет владельца: разделы из Cabinet Settings и их данные.

Методы работают с правами пользователя — поверх них здесь режутся поля:
ни одно поле вне конфигурации раздела не читается и не пишется. Граница
безопасности — набор DocType, на которые у ролей кабинета есть права; фильтр
полей держит экран простым и служебные поля нетронутыми.
"""

from dataclasses import asdict, dataclass

import frappe
from frappe import _

from habibi_ui.cabinet import registry
from habibi_ui.cabinet.fields import merge_filters, parse_fields, split_values

CABINET_ROLES = ("Habibi Owner", "Habibi Staff")
PAGE_LIMIT = 100


@dataclass
class CabinetField:
	fieldname: str
	label: str
	fieldtype: str
	options: str
	reqd: bool
	read_only: bool


@dataclass
class CabinetSection:
	key: str
	label: str
	icon: str
	kind: str
	screen: str
	doctype: str
	can_create: bool
	can_edit: bool
	can_delete: bool
	list_fields: list[CabinetField]
	form_fields: list[CabinetField]


def _visible(row, roles, features):
	if row.feature and row.feature not in features:
		return False
	wanted = {r.strip() for r in (row.roles or "").splitlines() if r.strip()}
	if wanted:
		return bool(wanted & roles) or "System Manager" in roles
	return bool(set(CABINET_ROLES) & roles) or "System Manager" in roles


def _describe(meta, specs):
	"""Мета полей; None — если хоть одного поля на сайте нет."""
	result = []
	for spec in specs:
		if spec.adapter:
			a = registry.adapter(spec.fieldname)
			if a is None or a.doctype != meta.name:
				return None
			result.append(
				CabinetField(spec.fieldname, spec.label or a.label, a.fieldtype, "", False, not a.editable())
			)
			continue
		df = meta.get_field(spec.fieldname)
		if df is None and spec.fieldname != "name":
			return None
		result.append(
			CabinetField(
				spec.fieldname,
				spec.label or (_(df.label) if df else _("Номер")),
				df.fieldtype if df else "Data",
				(df.options or "") if df else "",
				bool(df and df.reqd),
				bool(not df or df.read_only),
			)
		)
	return result


def _sections():
	roles = set(frappe.get_roles())
	features = registry.enabled_features()
	result = {}
	for row in frappe.get_single("Cabinet Settings").sections:
		if not _visible(row, roles, features):
			continue
		if row.kind == "custom":
			result[row.key] = (row, CabinetSection(row.key, row.label, row.icon or "", "custom", row.screen or "", "", False, False, False, [], []))
			continue
		if not row.ref_doctype or not frappe.db.exists("DocType", row.ref_doctype):
			frappe.logger("habibi_ui").warning(f"Раздел {row.key}: нет DocType {row.ref_doctype}")
			continue
		meta = frappe.get_meta(row.ref_doctype)
		list_fields = _describe(meta, parse_fields(row.list_fields))
		form_fields = _describe(meta, parse_fields(row.form_fields))
		if list_fields is None or form_fields is None:
			frappe.logger("habibi_ui").warning(f"Раздел {row.key}: поле из конфигурации отсутствует на сайте")
			continue
		result[row.key] = (
			row,
			CabinetSection(
				row.key, row.label, row.icon or "", "generic", "", row.ref_doctype,
				bool(row.can_create), bool(row.can_edit), bool(row.can_delete), list_fields, form_fields,
			),
		)
	return result


def _section(key):
	found = _sections().get(key)
	if not found or found[1].kind != "generic":
		frappe.throw(_("Раздел не найден"), frappe.DoesNotExistError)
	return found


def _require_login():
	if frappe.session.user == "Guest":
		frappe.throw(_("Требуется вход"), frappe.PermissionError)


def _with_adapters(rows, specs):
	for spec in specs:
		if spec.adapter:
			values = registry.adapter(spec.fieldname).read([r["name"] for r in rows])
			for r in rows:
				r[spec.fieldname] = values.get(r["name"])
	return rows


@frappe.whitelist()
def config():
	_require_login()
	return [asdict(s) for _row, s in _sections().values()]


@frappe.whitelist()
def list(section, filters=None, start=0, page_length=20):
	_require_login()
	row, s = _section(section)
	specs = parse_fields(row.list_fields)
	plain = [f.fieldname for f in specs if not f.adapter]
	page_length = min(int(page_length), PAGE_LIMIT)
	rows = frappe.get_list(
		s.doctype,
		fields=sorted({"name", *plain}),
		filters=merge_filters(row.base_filters, frappe.parse_json(filters) if filters else None, set(plain)),
		order_by="modified desc",
		start=int(start),
		page_length=page_length + 1,
	)
	has_more = len(rows) > page_length
	rows = _with_adapters(rows[:page_length], specs)
	return {"rows": rows, "has_more": has_more}


def _doc_in_section(row, s, name):
	filters = merge_filters(row.base_filters, None, set()) + [["name", "=", name]]
	if not frappe.get_list(s.doctype, filters=filters, pluck="name", limit=1):
		frappe.throw(_("Документ не найден"), frappe.DoesNotExistError)
	return frappe.get_doc(s.doctype, name)


@frappe.whitelist()
def get(section, name):
	_require_login()
	row, s = _section(section)
	doc = _doc_in_section(row, s, name)
	specs = parse_fields(row.form_fields)
	result = {"name": doc.name}
	for spec in specs:
		if not spec.adapter:
			result[spec.fieldname] = doc.get(spec.fieldname)
	return _with_adapters([result], specs)[0]


@frappe.whitelist(methods=["POST"])
def save(section, values, name=None):
	_require_login()
	row, s = _section(section)
	specs = parse_fields(row.form_fields)
	plain, adapters = split_values(frappe.parse_json(values), specs)
	if name:
		if not s.can_edit:
			frappe.throw(_("Изменение в этом разделе запрещено"), frappe.PermissionError)
		doc = _doc_in_section(row, s, name)
		doc.update(plain)
		doc.save()
	else:
		if not s.can_create:
			frappe.throw(_("Создание в этом разделе запрещено"), frappe.PermissionError)
		doc = frappe.get_doc({"doctype": s.doctype, **plain})
		doc.insert()
	for fieldname, value in adapters.items():
		a = registry.adapter(fieldname)
		if a.editable():
			a.write(doc, value)
	return get(section, doc.name)


@frappe.whitelist(methods=["POST"])
def delete(section, name):
	_require_login()
	row, s = _section(section)
	if not s.can_delete:
		frappe.throw(_("Удаление в этом разделе запрещено"), frappe.PermissionError)
	_doc_in_section(row, s, name)
	frappe.delete_doc(s.doctype, name)
```

Метод называется `list` — это публичный URL `habibi_ui.api.v1.cabinet.list`. Он затеняет встроенный `list` внутри модуля, поэтому встроенный здесь не вызывается нигде: только литералы `[...]` и `sorted(...)`.

- [ ] **Step 6: Тесты проходят**

Run: `bench --site dev.localhost run-tests --module habibi_ui.tests.test_cabinet_api`
Expected: PASS, 11 тестов.

- [ ] **Step 7: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ui && git add habibi_ui && git commit -m "feat(cabinet): разделы из Cabinet Settings и методы cabinet.*, режущие поля"
```

---

### Task 4: Роли кабинета, домашняя страница, типы

**Files:**
- Modify: `habibi_ui/habibi_ui/fixtures/role.json`
- Modify: `habibi_ui/habibi_ui/hooks.py` (`fixtures`, `role_home_page`)
- Modify: `habibi_ui/habibi_ui/api/v1/session.py`
- Modify: `habibi_ui/habibi_ui/typegen.py`
- Modify: `habibi_ui/frontend/src/shared/types/api.ts` (генерируется)
- Test: `habibi_ui/habibi_ui/tests/test_session.py`, `test_typegen.py`

**Interfaces:**
- Consumes: `CabinetField`, `CabinetSection`, `CABINET_ROLES` (задача 3).
- Produces: `Me.home: str` — `"cabinet"` или `"launcher"`; TS-интерфейсы `CabinetField`, `CabinetSection` в `shared/types/api.ts`.

- [ ] **Step 1: Тесты**

В `test_session.py`:

```python
	def test_владелец_попадает_в_кабинет(self):
		with patch("habibi_ui.api.v1.session.frappe.get_roles", return_value=["Habibi Owner"]):
			self.assertEqual(me()["home"], "cabinet")

	def test_администратор_попадает_в_лаунчер(self):
		# System Manager с ролью владельца — всё равно лаунчер: ему нужна «кухня»,
		# а кабинет открывается руками по /ui/c.
		with patch("habibi_ui.api.v1.session.frappe.get_roles", return_value=["Habibi Owner", "System Manager"]):
			self.assertEqual(me()["home"], "launcher")
```

В `test_typegen.py`:

```python
	def test_типы_кабинета_экспортируются(self):
		out = render_types()
		self.assertIn("export interface CabinetSection {", out)
		self.assertIn("  form_fields: CabinetField[];", out)
		self.assertIn("  home: string;", out)
```

- [ ] **Step 2: Запустить — падает**

Run: `bench --site dev.localhost run-tests --module habibi_ui.tests.test_session` и `--module habibi_ui.tests.test_typegen`
Expected: FAIL — `KeyError: 'home'`, нет `CabinetSection`.

- [ ] **Step 3: Реализация**

`fixtures/role.json` — добавить две роли рядом с `Habibi UI`, по образцу существующей записи:

```json
{"doctype": "Role", "name": "Habibi Owner", "role_name": "Habibi Owner", "desk_access": 1, "home_page": "ui"},
{"doctype": "Role", "name": "Habibi Staff", "role_name": "Habibi Staff", "desk_access": 1, "home_page": "ui"}
```

`hooks.py`:

```python
fixtures = [
	{"dt": "Role", "filters": [["name", "in", ["Habibi UI", "Habibi Owner", "Habibi Staff"]]]},
]

role_home_page = {
	"Habibi UI": "ui",
	"Habibi Owner": "ui",
	"Habibi Staff": "ui",
}
```

`session.py`:

```python
from habibi_ui.api.v1.cabinet import CABINET_ROLES


@dataclass
class Me:
	user: str
	full_name: str
	roles: list[str]
	modules: list[Module]
	home: str


def _home(roles) -> str:
	"""Кабинет — для ролей кабинета без System Manager.

	Решает сервер: фронт только перенаправляет. Администратор с ролью
	владельца остаётся в лаунчере — ему нужна вся система, кабинет он
	откроет по /ui/c.
	"""
	if "System Manager" in roles:
		return "launcher"
	return "cabinet" if set(CABINET_ROLES) & set(roles) else "launcher"
```

и в `me()`: `roles = frappe.get_roles()` один раз, `Me(..., roles=roles, modules=_modules(), home=_home(roles))`.

`typegen.py`: импорт `from habibi_ui.api.v1.cabinet import CabinetField, CabinetSection`, `EXPORTED = [Module, Me, CabinetField, CabinetSection, WorkspaceRef, ...]`.

Сгенерировать типы: `bench --site dev.localhost habibi-ui generate-types`, затем `bench --site dev.localhost migrate` (фикстуры ролей).

- [ ] **Step 4: Тесты проходят**

Run: обе команды шага 2. Expected: PASS.

- [ ] **Step 5: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ui && git add habibi_ui frontend/src/shared/types/api.ts && git commit -m "feat(cabinet): роли Habibi Owner/Staff и домашняя страница по роли"
```

---

### Task 5: Бизнес-профиль, флаги возможностей, профиль в промпте

**Files:**
- Create: `habibi_ai/habibi_ai/features.py`, `habibi_ai/habibi_ai/profile.py`
- Create: `habibi_ai/habibi_ai/habibi_ai/doctype/business_profile/{__init__.py,business_profile.json,business_profile.py}`
- Create: `habibi_ai/habibi_ai/habibi_ai/doctype/business_profile_rule/{__init__.py,business_profile_rule.json,business_profile_rule.py}`
- Modify: `habibi_ai/habibi_ai/habibi_ai/doctype/habibi_ai_settings/habibi_ai_settings.json`
- Modify: `habibi_ai/habibi_ai/engine.py:343-368` (`step`)
- Modify: `habibi_ai/habibi_ai/api.py:148-195` (`run_turn`, `_tool_names`)
- Test: `habibi_ai/habibi_ai/tests/test_features.py`, `test_profile.py`; правка `test_api.py`

**Interfaces:**
- Produces:
  - `features.FEATURES = {"delivery": ("feature_delivery", ("get_delivery_zones",)), "orders": ("feature_orders", ("quote_order", "create_order"))}`;
  - `features.enabled(values: dict) -> set[str]` — `values` = `{fieldname: 0|1|None}`, `None` = включено;
  - `features.offered(names: list[str], enabled: set[str]) -> list[str]`;
  - `profile.render(profile: dict, rules: list[dict]) -> str` — пусто, если нечего сказать;
  - `habibi_ai.features_hook() -> set[str]` — для хука кабинета (читает `Habibi AI Settings`);
  - `EngineClient.step(..., tenant_context=None)`.

- [ ] **Step 1: Тесты без frappe**

```python
# tests/test_features.py
import unittest

from habibi_ai import features


class TestFeatures(unittest.TestCase):
	def test_несохранённые_настройки_значит_всё_включено(self):
		# erp.habibi-erp.com после миграции: полей ещё нет в tabSingles,
		# и бот не должен потерять quote_order.
		self.assertEqual(features.enabled({"feature_delivery": None, "feature_orders": None}), {"delivery", "orders"})

	def test_выключенная_доставка(self):
		self.assertEqual(features.enabled({"feature_delivery": 0, "feature_orders": 1}), {"orders"})

	def test_инструменты_выключенной_возможности_не_предлагаются(self):
		names = ["create_order", "get_delivery_zones", "get_menu", "quote_order"]
		self.assertEqual(features.offered(names, {"orders"}), ["create_order", "get_menu", "quote_order"])

	def test_инструмент_без_возможности_предлагается_всегда(self):
		self.assertEqual(features.offered(["get_menu", "get_working_hours"], set()), ["get_menu", "get_working_hours"])
```

```python
# tests/test_profile.py
import unittest

from habibi_ai.profile import render


class TestProfile(unittest.TestCase):
	def test_ядро_и_правила_по_порядку(self):
		text = render(
			{"business_name": "Habibi Burger", "business_kind": "бургерная", "address": "Абая 1",
			 "phone": "+77010000000", "description": "Жарим на углях.", "tone": "friendly"},
			[{"title": "Доставка", "text": "40–60 минут."}, {"title": "Оплата", "text": "Kaspi, наличные."}],
		)
		self.assertEqual(
			text,
			"О компании (данные владельца, отвечай по ним):\n"
			"Название: Habibi Burger\n"
			"Вид деятельности: бургерная\n"
			"Адрес: Абая 1\n"
			"Телефон: +77010000000\n"
			"Жарим на углях.\n"
			"Тон общения: дружелюбный, на «ты» не переходить без повода клиента.\n\n"
			"Доставка:\n40–60 минут.\n\n"
			"Оплата:\nKaspi, наличные.",
		)

	def test_пустое_правило_не_попадает(self):
		text = render({"business_name": "X"}, [{"title": "Залог", "text": "  "}])
		self.assertNotIn("Залог", text)

	def test_пустой_профиль_пустой_текст(self):
		self.assertEqual(render({}, []), "")
```

Run: `$DC exec -T frappe bash -lc "cd /workspace/repos/habibi_ai && $PY -m unittest habibi_ai.tests.test_features habibi_ai.tests.test_profile -v"`
Expected: FAIL — нет модулей.

- [ ] **Step 2: Реализация без frappe**

```python
"""Возможности бизнеса: какие инструменты бота включены.

Без frappe. Флаг отвечает сразу за раздел кабинета и за инструмент: у
автопроката нет доставки — нет ни раздела, ни get_delivery_zones, и бот о
доставке не заговорит.
"""

FEATURES = {
	"delivery": ("feature_delivery", ("get_delivery_zones",)),
	"orders": ("feature_orders", ("quote_order", "create_order")),
}


def enabled(values):
	"""None — поле ни разу не сохраняли: считаем включённым.

	Иначе сайт, где бот уже принимал заказы, после миграции молча потерял бы
	инструменты заказа — флаги появились позже, чем заказы.
	"""
	return {key for key, (field, _tools) in FEATURES.items() if values.get(field) is None or int(values[field])}


def offered(names, enabled_keys):
	blocked = {t for key, (_f, tools) in FEATURES.items() if key not in enabled_keys for t in tools}
	return [n for n in names if n not in blocked]
```

```python
"""Бизнес-профиль → текст для system prompt. Без frappe.

Промпт бота общий и живёт в Directus; здесь — только то, что владелец написал
о своей компании. Пустое не попадает: «Залог:» без текста модель восприняла
бы как «залога нет».
"""

TONES = {
	"friendly": "дружелюбный, на «ты» не переходить без повода клиента",
	"neutral": "нейтральный, вежливый",
	"formal": "официальный, на «вы»",
}

CORE = (("business_name", "Название"), ("business_kind", "Вид деятельности"), ("address", "Адрес"), ("phone", "Телефон"))


def render(profile, rules):
	lines = [f"{label}: {profile[key].strip()}" for key, label in CORE if (profile.get(key) or "").strip()]
	if (profile.get("description") or "").strip():
		lines.append(profile["description"].strip())
	if profile.get("tone") in TONES:
		lines.append(f"Тон общения: {TONES[profile['tone']]}.")
	blocks = [f"{r['title'].strip()}:\n{r['text'].strip()}" for r in rules if (r.get("text") or "").strip()]
	if not lines and not blocks:
		return ""
	head = "О компании (данные владельца, отвечай по ним):\n" + "\n".join(lines)
	return "\n\n".join([head, *blocks])
```

Run: команда шага 1. Expected: PASS, 7 тестов.

- [ ] **Step 3: Доктайпы**

`business_profile_rule.json` — child (`istable: 1`, module `Habibi AI`): `title` Data reqd in_list_view; `hint` Small Text read_only; `text` Text in_list_view.

`business_profile.json` — single (module `Habibi AI`): `business_name` Data; `business_kind` Data; `address` Data; `phone` Data; `description` Small Text; `tone` Select `friendly\nneutral\nformal` default `friendly`; `rules` Table `Business Profile Rule`. Права: `System Manager` — read/write; `Habibi Owner` — read/write.

`habibi_ai_settings.json` — добавить `feature_delivery` Check default `1` label «Доставка»; `feature_orders` Check default `1` label «Заказы»; обновить `modified`.

Run: `bench --site dev.localhost migrate`. Expected: без ошибок.

- [ ] **Step 4: Тест `run_turn` (правка `test_api.py`)**

Найти существующий тест `run_turn` с подменённым клиентом (в нём `client.step` — `MagicMock`) и добавить рядом:

```python
	def test_профиль_уходит_в_движок(self):
		profile = frappe.get_single("Business Profile")
		profile.business_name = "Habibi Burger"
		profile.save()
		client = self._client_answering("ok")  # хелпер файла: step возвращает финальный ответ
		api.run_turn(client, 5, "привет")
		self.assertIn("Название: Habibi Burger", client.step.call_args.kwargs["tenant_context"])

	def test_выключенная_доставка_не_предлагается(self):
		settings = frappe.get_single("Habibi AI Settings")
		settings.feature_delivery = 0
		settings.save()
		client = self._client_answering("ok")
		api.run_turn(client, 5, "привет")
		offered = [t["name"] for t in client.step.call_args.kwargs["tools"]]
		self.assertNotIn("get_delivery_zones", offered)
		self.assertIn("quote_order", offered)
```

Если хелпера `_client_answering` в файле нет — завести его в классе по образцу существующих тестов: `MagicMock()`, `get_max_loop.return_value = None`, `step.return_value = {"type": "final", "response": text}` (формат взять из соседних тестов, он уже там).

Run: `bench --site dev.localhost run-tests --module habibi_ai.tests.test_api`
Expected: FAIL — `KeyError: 'tenant_context'`.

- [ ] **Step 5: Реализация во frappe-части**

`engine.py`, `step`:

```python
	def step(self, chat_id, message, bot_id=None, turn=None, tools=None, debug=False, tenant_context=None):
		...
		payload = {"chat_id": chat_id, "user_message": message, "turn": turn or [], "tools": tools or []}
		if bot_id:
			payload["bot_id"] = bot_id
		if debug:
			payload["debug"] = True
		# Данные компании из кабинета. Старый движок поле игнорирует — поэтому
		# выкатка habibi_ai и движка не обязана быть одновременной.
		if tenant_context:
			payload["tenant_context"] = tenant_context
		return self._post("ai-process-message", payload)
```

`api.py`:

```python
from habibi_ai import features, profile as business_profile


def feature_values():
	return {
		field: frappe.db.get_single_value("Habibi AI Settings", field, cache=False)
		if frappe.db.exists("Singles", {"doctype": "Habibi AI Settings", "field": field})
		else None
		for field, _tools in features.FEATURES.values()
	}


def features_hook():
	"""Хук habibi_cabinet_features: какие возможности включены на сайте."""
	return features.enabled(feature_values())


def tenant_context():
	doc = frappe.get_single("Business Profile")
	return business_profile.render(doc.as_dict(), [r.as_dict() for r in doc.rules])
```

В `run_turn`: `offered = features.offered(_tool_names(), features_hook())`, а лямбда шага — `client.step(chat_id, text, bot_id, tenant_context=context_text, **kwargs)`, где `context_text = tenant_context()` вычисляется один раз до `loop.run`.

`frappe.db.exists("Singles", ...)` — именно проверка строки, а не `get_single_value`: у `get_single_value` для Check отсутствие строки и `0` неотличимы, а это ровно Review Focus 5.

- [ ] **Step 6: Тесты проходят**

Run: `bench --site dev.localhost run-tests --app habibi_ai`
Expected: PASS, включая старые тесты `test_api`, `test_telegram_bridge`.

- [ ] **Step 7: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai && git add habibi_ai && git commit -m "feat(profile): бизнес-профиль в промпте и флаги возможностей бота"
```

---

### Task 6: Адаптер цены и хуки кабинета в `habibi_ai`

**Files:**
- Create: `habibi_ai/habibi_ai/cabinet/__init__.py` (пустой), `habibi_ai/habibi_ai/cabinet/adapters.py`
- Modify: `habibi_ai/habibi_ai/hooks.py`
- Test: `habibi_ai/habibi_ai/tests/test_cabinet_adapters.py`

**Interfaces:**
- Consumes: `valid_prices(rows, today)` из `habibi_ai.tools.menu`; интерфейс адаптера из задачи 3.
- Produces: `habibi_ai.cabinet.adapters.selling_price` — объект адаптера; хуки `habibi_cabinet_adapters`, `habibi_cabinet_features`.

- [ ] **Step 1: Тест**

```python
import frappe
from frappe.tests import IntegrationTestCase

from habibi_ai.cabinet.adapters import selling_price

PRICE_LIST = "Cabinet Test Selling"


class TestSellingPrice(IntegrationTestCase):
	def setUp(self):
		frappe.set_user("Administrator")
		if not frappe.db.exists("Price List", PRICE_LIST):
			frappe.get_doc({"doctype": "Price List", "price_list_name": PRICE_LIST, "selling": 1, "currency": "KZT"}).insert()
		frappe.db.set_single_value("Selling Settings", "selling_price_list", PRICE_LIST)
		self.item = frappe.get_doc({
			"doctype": "Item", "item_code": "CAB-TEST-BURGER", "item_name": "Бургер",
			"item_group": frappe.db.get_value("Item Group", {"is_group": 0}), "stock_uom": "Nos",
		}).insert(ignore_if_duplicate=True)

	def tearDown(self):
		frappe.db.rollback()

	def test_читает_действующую_цену(self):
		frappe.get_doc({"doctype": "Item Price", "item_code": self.item.name, "price_list": PRICE_LIST,
			"price_list_rate": 100, "valid_upto": "2020-01-01"}).insert()
		frappe.get_doc({"doctype": "Item Price", "item_code": self.item.name, "price_list": PRICE_LIST,
			"price_list_rate": 2490}).insert()
		self.assertEqual(selling_price.read([self.item.name]), {self.item.name: 2490.0})

	def test_запись_создаёт_цену(self):
		selling_price.write(self.item, 1990)
		self.assertEqual(selling_price.read([self.item.name]), {self.item.name: 1990.0})

	def test_запись_обновляет_цену_без_дубля(self):
		selling_price.write(self.item, 1990)
		selling_price.write(self.item, 2090)
		count = frappe.db.count("Item Price", {"item_code": self.item.name, "price_list": PRICE_LIST})
		self.assertEqual(count, 1)
		self.assertEqual(selling_price.read([self.item.name])[self.item.name], 2090.0)

	def test_без_прайс_листа_не_редактируется(self):
		frappe.db.set_single_value("Selling Settings", "selling_price_list", None)
		self.assertFalse(selling_price.editable())
		self.assertEqual(selling_price.read([self.item.name]), {})
```

- [ ] **Step 2: Запустить — падает**

Run: `bench --site dev.localhost run-tests --module habibi_ai.tests.test_cabinet_adapters`
Expected: FAIL — нет модуля.

- [ ] **Step 3: Реализация**

```python
"""Поля кабинета, которых нет в самом DocType.

Цена позиции живёт не в Item, а в Item Price по прайс-листу продаж. Правила
действующей цены — те же, что у бота (valid_prices): иначе владелец видел бы
в кабинете одну цену, а бот называл бы клиенту другую.
"""

import frappe

from habibi_ai.tools.menu import valid_prices


class SellingPrice:
	doctype = "Item"
	label = "Цена"
	fieldtype = "Currency"

	def _price_list(self):
		return frappe.db.get_single_value("Selling Settings", "selling_price_list")

	def editable(self):
		return bool(self._price_list())

	def read(self, names):
		price_list = self._price_list()
		if not price_list or not names:
			return {}
		rows = frappe.get_all(
			"Item Price",
			filters={"price_list": price_list, "selling": 1, "item_code": ["in", names]},
			fields=["item_code", "price_list_rate", "valid_from", "valid_upto"],
			order_by="valid_from desc",
		)
		result = {}
		for r in valid_prices(rows, frappe.utils.nowdate()):
			result.setdefault(r["item_code"], float(r["price_list_rate"]))
		return result

	def write(self, doc, value):
		"""Обновить действующую бессрочную цену или завести новую.

		Историю цен с датами владелец в кабинете не ведёт: ему нужна «цена
		сейчас». Цены с датами из Desk не трогаем — их правят там же.
		"""
		price_list = self._price_list()
		existing = frappe.db.get_value(
			"Item Price",
			{"item_code": doc.name, "price_list": price_list, "valid_upto": ["is", "not set"]},
			"name",
		)
		if existing:
			price = frappe.get_doc("Item Price", existing)
			price.price_list_rate = value
			price.save()
			return
		frappe.get_doc(
			{"doctype": "Item Price", "item_code": doc.name, "price_list": price_list, "price_list_rate": value}
		).insert()


selling_price = SellingPrice()
```

`hooks.py`:

```python
habibi_cabinet_adapters = {"selling_price": "habibi_ai.cabinet.adapters.selling_price"}
habibi_cabinet_features = ["habibi_ai.api.features_hook"]
```

- [ ] **Step 4: Тесты проходят**

Run: команда шага 2 и `bench --site dev.localhost run-tests --module habibi_ui.tests.test_cabinet_api`. Expected: PASS.

- [ ] **Step 5: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai && git add habibi_ai && git commit -m "feat(cabinet): адаптер цены позиции по правилам бота"
```

---

### Task 7: Правила уведомления (без frappe)

**Files:**
- Create: `habibi_ai/habibi_ai/notify_rules.py`
- Test: `habibi_ai/habibi_ai/tests/test_notify_rules.py`

**Interfaces:**
- Produces:
  - `render(template: str, values: dict) -> str` — `{order}`, `{customer}`, `{total}`, `{reason}`, `{time}`; неизвестная подстановка остаётся как есть;
  - `kind_of(action: str, accept: str, reject: str) -> str` — `"accept" | "reject" | "other"`;
  - `NO_WORKFLOW_ACCEPT = "submit"`, `NO_WORKFLOW_REJECT = "discard"`.

- [ ] **Step 1: Тест**

```python
import unittest

from habibi_ai import notify_rules as n


class TestRender(unittest.TestCase):
	def test_подстановки(self):
		self.assertEqual(
			n.render("Заказ {order} принят, {customer}! Итого {total}.", {"order": "SO-1", "customer": "Руслан", "total": "4670 KZT"}),
			"Заказ SO-1 принят, Руслан! Итого 4670 KZT.",
		)

	def test_неизвестная_подстановка_не_роняет(self):
		# Шаблон правит владелец: опечатка в скобках — не повод не уведомить клиента.
		self.assertEqual(n.render("Привет {name}", {}), "Привет {name}")

	def test_пустое_значение(self):
		self.assertEqual(n.render("Причина: {reason}", {"reason": None}), "Причина: ")


class TestKind(unittest.TestCase):
	def test_виды(self):
		self.assertEqual(n.kind_of("Confirm", "Confirm", "Cancel"), "accept")
		self.assertEqual(n.kind_of("Cancel", "Confirm", "Cancel"), "reject")
		self.assertEqual(n.kind_of("Send to Kitchen", "Confirm", "Cancel"), "other")
```

Run: `$DC exec -T frappe bash -lc "cd /workspace/repos/habibi_ai && $PY -m unittest habibi_ai.tests.test_notify_rules -v"` — FAIL.

- [ ] **Step 2: Реализация**

```python
"""Уведомление клиента о решении по заказу. Без frappe."""

NO_WORKFLOW_ACCEPT = "submit"
NO_WORKFLOW_REJECT = "discard"


class _Keep(dict):
	def __missing__(self, key):
		return "{" + key + "}"


def render(template, values):
	return (template or "").format_map(_Keep({k: "" if v is None else v for k, v in values.items()}))


def kind_of(action, accept, reject):
	if action == accept:
		return "accept"
	if action == reject:
		return "reject"
	return "other"
```

Run: команда шага 1 — PASS, 4 теста.

- [ ] **Step 3: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai && git add habibi_ai/notify_rules.py habibi_ai/tests/test_notify_rules.py && git commit -m "feat(orders): шаблон уведомления клиента без frappe"
```

---

### Task 8: Действия с заказом и уведомление

**Files:**
- Create: `habibi_ai/habibi_ai/cabinet/orders.py`
- Modify: `habibi_ai/habibi_ai/habibi_ai/doctype/habibi_ai_settings/habibi_ai_settings.json` — поля `accept_action` Data, `reject_action` Data, `modified`
- Test: `habibi_ai/habibi_ai/tests/test_cabinet_orders.py`

**Interfaces:**
- Consumes: `notify_rules.render/kind_of`, `channels.telegram.send(channel, chat, text)`, `AI Order Quote` (`channel_doctype`, `channel_name`, `sales_order`), `AI Channel Chat` (`channel_doctype`, `channel_name`, `telegram_chat`).
- Produces (все `@frappe.whitelist()`):
  - `habibi_ai.cabinet.orders.actions(name) -> {"state": str, "actions": [{"action": str, "kind": str}], "can_notify": bool}`;
  - `habibi_ai.cabinet.orders.apply(name, action, reason=None) -> {"state": str, "notify": {"kind": str, "text": str, "chat": str} | None}`;
  - `habibi_ai.cabinet.orders.notify(name, text, chat=None) -> {"sent": bool, "error": str | None}`.
- Шаблоны: `Telegram Message Template` с `template_name` `order_accepted` / `order_rejected` (поле текста — `default_template`).

- [ ] **Step 1: Тест**

```python
from unittest.mock import patch

import frappe
from frappe.tests import IntegrationTestCase

from habibi_ai.cabinet import orders

# Хелперы готового заказа — те же, что в test_orders.py (там уже есть
# сборка тестовой компании, прайс-листа и позиций). Импортируем, а не копируем.
from habibi_ai.tests.test_orders import OrderFixtures


class TestCabinetOrders(OrderFixtures, IntegrationTestCase):
	def setUp(self):
		super().setUp()
		self.so = self.make_bot_order()  # черновик SO + AI Order Quote с channel_doctype="Telegram Chat"
		for key, text in (("order_accepted", "Заказ {order} принят"), ("order_rejected", "Не сможем: {reason}")):
			if not frappe.db.exists("Telegram Message Template", key):
				frappe.get_doc({"doctype": "Telegram Message Template", "template_name": key, "default_template": text}).insert()

	def test_без_воркфлоу_принять_проводит(self):
		with patch("habibi_ai.cabinet.orders._workflow", return_value=None):
			self.assertEqual([a["kind"] for a in orders.actions(self.so.name)["actions"]], ["accept", "reject"])
			result = orders.apply(self.so.name, "submit")
		self.assertEqual(frappe.db.get_value("Sales Order", self.so.name, "docstatus"), 1)
		self.assertEqual(result["notify"]["text"], f"Заказ {self.so.name} принят")

	def test_без_воркфлоу_отклонить_удаляет_черновик(self):
		with patch("habibi_ai.cabinet.orders._workflow", return_value=None):
			result = orders.apply(self.so.name, "discard")
		self.assertFalse(frappe.db.exists("Sales Order", self.so.name))
		self.assertEqual(result["notify"]["kind"], "reject")

	def test_уведомление_уходит_в_чат_заказа(self):
		with patch("habibi_ai.cabinet.orders.telegram.send") as send:
			result = orders.notify(self.so.name, "Заказ принят")
		self.assertEqual(result, {"sent": True, "error": None})
		_channel, chat, text = send.call_args.args
		self.assertEqual(chat, self.quote_chat)
		self.assertEqual(text, "Заказ принят")

	def test_сорвавшаяся_отправка_не_откатывает_заказ(self):
		with patch("habibi_ai.cabinet.orders._workflow", return_value=None):
			orders.apply(self.so.name, "submit")
		with patch("habibi_ai.cabinet.orders.telegram.send", side_effect=Exception("403 Forbidden")):
			result = orders.notify(self.so.name, "Заказ принят")
		self.assertEqual(result["sent"], False)
		self.assertIn("403", result["error"])
		self.assertEqual(frappe.db.get_value("Sales Order", self.so.name, "docstatus"), 1)
		comments = frappe.get_all("Comment", filters={"reference_name": self.so.name}, pluck="content")
		self.assertTrue(any("не уведомлён" in c for c in comments))

	def test_заказ_без_чата_не_предлагает_уведомление(self):
		frappe.db.set_value("AI Order Quote", {"sales_order": self.so.name}, "sales_order", None)
		self.assertFalse(orders.actions(self.so.name)["can_notify"])
		with patch("habibi_ai.cabinet.orders._workflow", return_value=None):
			self.assertIsNone(orders.apply(self.so.name, "submit")["notify"])

	def test_уведомление_после_удаления_черновика(self):
		with patch("habibi_ai.cabinet.orders._workflow", return_value=None):
			result = orders.apply(self.so.name, "discard", reason="закончилась булка")
		self.assertIn("закончилась булка", result["notify"]["text"])
		with patch("habibi_ai.cabinet.orders.telegram.send") as send:
			sent = orders.notify(self.so.name, result["notify"]["text"], chat=result["notify"]["chat"])
		self.assertTrue(sent["sent"])
		self.assertEqual(send.call_args.args[1], self.quote_chat)

	def test_недоступное_действие_отклоняется(self):
		with patch("habibi_ai.cabinet.orders._workflow", return_value=None):
			with self.assertRaises(frappe.ValidationError):
				orders.apply(self.so.name, "launch_rocket")
```

Перед шагом 2 открыть `habibi_ai/tests/test_orders.py`: если сборка заказа там сделана методами тест-класса, а не миксином, вынести её в класс `OrderFixtures(unittest.TestCase-миксин)` с методом `make_bot_order()` (создаёт `Telegram Chat`, `AI Channel Chat` с каналом `("Telegram Bot", <бот>)`, расчёт и черновик SO через `create_order`) и атрибутом `self.quote_chat` — имя `Telegram Chat`. Старые тесты `test_orders.py` после выноса должны пройти без изменений — это часть шага.

- [ ] **Step 2: Запустить — падает**

Run: `bench --site dev.localhost run-tests --module habibi_ai.tests.test_cabinet_orders`
Expected: FAIL — нет модуля `habibi_ai.cabinet.orders`.

- [ ] **Step 3: Реализация**

```python
"""Заказы в кабинете: решение владельца и уведомление клиента.

Порядок жёсткий: сначала переход заказа, потом сообщение. Не прошёл переход —
клиенту нечего сообщать. Не ушло сообщение — заказ всё равно принят: кухня
уже работает, а клиенту можно написать повторно.
"""

import frappe
from frappe import _
from frappe.model.workflow import apply_workflow, get_transitions, get_workflow_name

from habibi_ai import notify_rules
from habibi_ai.channels import telegram

TEMPLATES = {"accept": "order_accepted", "reject": "order_rejected"}


def _workflow(doc):
	return get_workflow_name("Sales Order")


def _names():
	s = frappe.get_cached_doc("Habibi AI Settings")
	return s.accept_action or "Confirm", s.reject_action or "Cancel"


def _quote(name):
	return frappe.db.get_value(
		"AI Order Quote", {"sales_order": name}, ["channel_doctype", "channel_name", "customer_name"], as_dict=True
	)


def _pair(telegram_chat):
	"""Канал бота, которым писать в этот чат; None — чат не подключён к боту."""
	pair = frappe.db.get_value(
		"AI Channel Chat", {"telegram_chat": telegram_chat}, ["channel_doctype", "channel_name"],
		as_dict=True, order_by="modified desc",
	)
	return (pair.channel_doctype, pair.channel_name) if pair else None


def _chat(name):
	"""Канальный чат заказа; None — заказ не из канала или чат не подключён."""
	quote = _quote(name)
	if not quote or quote.channel_doctype != "Telegram Chat" or not quote.channel_name:
		return None
	return quote.channel_name if _pair(quote.channel_name) else None


def _state(doc):
	if _workflow(doc):
		return doc.get("workflow_state") or ""
	return {0: _("Черновик"), 1: _("Принят"), 2: _("Отменён")}[doc.docstatus]


def _available(doc):
	if _workflow(doc):
		accept, reject = _names()
		return [
			{"action": t["action"], "kind": notify_rules.kind_of(t["action"], accept, reject)}
			for t in get_transitions(doc)
		]
	if doc.docstatus == 0:
		return [
			{"action": notify_rules.NO_WORKFLOW_ACCEPT, "kind": "accept"},
			{"action": notify_rules.NO_WORKFLOW_REJECT, "kind": "reject"},
		]
	return []


@frappe.whitelist()
def actions(name):
	doc = frappe.get_doc("Sales Order", name)
	doc.check_permission("read")
	return {"state": _state(doc), "actions": _available(doc), "can_notify": _chat(name) is not None}


def _draft_text(kind, doc, reason=None):
	template = frappe.db.get_value("Telegram Message Template", TEMPLATES[kind], "default_template")
	if not template:
		return ""
	return notify_rules.render(
		template,
		{
			"order": doc.name,
			"customer": doc.customer_name,
			"total": frappe.utils.fmt_money(doc.grand_total, currency=doc.currency),
			"time": doc.get("custom_requested_time") or "",
			"reason": reason,
		},
	)


@frappe.whitelist(methods=["POST"])
def apply(name, action, reason=None):
	"""Переход заказа. Чат вычисляется до перехода: «отклонить» без воркфлоу
	удаляет черновик, и ссылка расчёта на заказ после этого обнулится."""
	doc = frappe.get_doc("Sales Order", name)
	allowed = {a["action"]: a["kind"] for a in _available(doc)}
	if action not in allowed:
		frappe.throw(_("Действие «{0}» сейчас недоступно").format(action))
	kind = allowed[action]
	chat = _chat(name)
	snapshot = frappe._dict(
		name=doc.name, customer_name=doc.customer_name, grand_total=doc.grand_total,
		currency=doc.currency, custom_requested_time=doc.get("custom_requested_time"),
	)

	if _workflow(doc):
		doc = apply_workflow(doc, action)
		state = _state(doc)
	elif action == notify_rules.NO_WORKFLOW_ACCEPT:
		doc.submit()
		state = _state(doc)
	else:
		doc.check_permission("delete")
		frappe.delete_doc("Sales Order", name)
		state = _("Отклонён")

	notify = None
	if chat and kind in TEMPLATES:
		notify = {"kind": kind, "text": _draft_text(kind, snapshot, reason), "chat": chat}
	return {"state": state, "notify": notify}


@frappe.whitelist(methods=["POST"])
def notify(name, text, chat=None):
	"""Отправить клиенту; результат — в таймлайн заказа, если заказ ещё есть.

	chat приходит из ответа apply: после отклонения черновика заказа уже нет,
	и найти чат по нему нельзя.
	"""
	chat = chat or _chat(name)
	channel = _pair(chat) if chat else None
	if not channel:
		frappe.throw(_("У заказа нет чата с клиентом"))
	try:
		telegram.send(channel, chat, text)
		result = {"sent": True, "error": None}
		note = _("Клиент уведомлён: {0}").format(text)
	except Exception as e:
		result = {"sent": False, "error": str(e)}
		note = _("Клиент не уведомлён: {0}").format(e)
	if frappe.db.exists("Sales Order", name):
		frappe.get_doc("Sales Order", name).add_comment("Comment", note)
	return result
```

- [ ] **Step 4: Тесты проходят**

Run: `bench --site dev.localhost run-tests --module habibi_ai.tests.test_cabinet_orders` и `--module habibi_ai.tests.test_orders`
Expected: PASS.

- [ ] **Step 5: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai && git add habibi_ai && git commit -m "feat(cabinet): принять/отклонить заказ и уведомить клиента"
```

---

### Task 9: Переписки

**Files:**
- Create: `habibi_ai/habibi_ai/cabinet/chats.py`
- Test: `habibi_ai/habibi_ai/tests/test_cabinet_chats.py`

**Interfaces:**
- Consumes: `channels.telegram.send`, `channels.telegram.pause`, `channels.telegram.get_or_create_pair`; причины паузы — опции `AI Channel Chat.paused_reason`: `Оператор ответил вручную`, `Выключено вручную`.
- Produces (`@frappe.whitelist()`):
  - `list() -> [{"chat": str, "title": str, "preview": str, "last_at": str, "paused": bool, "customer": str | None}]`, сортировка по `last_message_on desc`, до 100;
  - `messages(chat, before=None) -> [{"name", "text", "at", "author": "client" | "bot" | "staff"}]`, 50 штук, по возрастанию;
  - `send(chat, text) -> None` — ставит паузу и отправляет;
  - `pause(chat) -> None`, `resume(chat) -> None`.
- Автор: `Incoming` → `client`; `Outgoing` и `is_automated` → `bot`; `Outgoing` без `is_automated` → `staff`.

- [ ] **Step 1: Тест**

```python
from unittest.mock import patch

import frappe
from frappe.tests import IntegrationTestCase

from habibi_ai.cabinet import chats


class TestCabinetChats(IntegrationTestCase):
	def setUp(self):
		frappe.set_user("Administrator")
		self.bot = frappe.get_all("Telegram Bot", pluck="name", limit=1)[0]
		self.chat = frappe.get_doc({"doctype": "Telegram Chat", "chat_id": "990001", "title": "Руслан", "type": "private"}).insert(ignore_if_duplicate=True)
		for direction, automated, text in (("Incoming", 0, "Привет"), ("Outgoing", 1, "Здравствуйте!"), ("Outgoing", 0, "Это Аня")):
			frappe.get_doc({"doctype": "Telegram Message", "chat": self.chat.name, "direction": direction,
				"is_automated": automated, "content": text, "telegram_bot": self.bot}).db_insert()
		frappe.get_doc({"doctype": "AI Channel Chat", "channel_doctype": "Telegram Bot", "channel_name": self.bot,
			"telegram_chat": self.chat.name}).insert(ignore_if_duplicate=True)

	def tearDown(self):
		frappe.db.rollback()

	def test_авторы_различаются(self):
		authors = [m["author"] for m in chats.messages(self.chat.name)]
		self.assertEqual(authors[-3:], ["client", "bot", "staff"])

	def test_взять_на_себя_и_вернуть(self):
		chats.pause(self.chat.name)
		self.assertTrue(next(c for c in chats.list() if c["chat"] == self.chat.name)["paused"])
		chats.resume(self.chat.name)
		self.assertFalse(next(c for c in chats.list() if c["chat"] == self.chat.name)["paused"])

	def test_ответ_сотрудника_ставит_паузу_и_уходит(self):
		with patch("habibi_ai.cabinet.chats.telegram.send") as send:
			chats.send(self.chat.name, "Сейчас уточню")
		self.assertEqual(send.call_args.args[1:], (self.chat.name, "Сейчас уточню"))
		self.assertTrue(next(c for c in chats.list() if c["chat"] == self.chat.name)["paused"])

	def test_ответ_сотрудника_в_ленте_от_сотрудника(self):
		def fake_send(channel, chat, text):
			# как настоящий client.send_message: вставляет исходящее с automated=1
			frappe.get_doc({"doctype": "Telegram Message", "chat": chat, "direction": "Outgoing",
				"is_automated": 1, "content": text, "telegram_bot": self.bot}).db_insert()
		with patch("habibi_ai.cabinet.chats.telegram.send", side_effect=fake_send):
			chats.send(self.chat.name, "Сейчас уточню")
		self.assertEqual(chats.messages(self.chat.name)[-1]["author"], "staff")

	def test_пустой_ответ_не_отправляется(self):
		with self.assertRaises(frappe.ValidationError):
			chats.send(self.chat.name, "   ")
```

Если на `dev.localhost` нет ни одного `Telegram Bot`, тест создаёт его в `setUp` с фиктивным токеном через `db_insert()` (валидацию токена `insert` пройти не даст — сеть).

- [ ] **Step 2: Запустить — падает.** Run: `bench --site dev.localhost run-tests --module habibi_ai.tests.test_cabinet_chats`

- [ ] **Step 3: Реализация**

```python
"""Переписки в кабинете: кто что написал и кто сейчас отвечает — бот или человек.

Экран не знает про Telegram: канал — деталь сервера. WhatsApp ляжет рядом
вторым адаптером, форма ответа не изменится.
"""

import frappe
from frappe import _

from habibi_ai.channels import telegram

PAIR = "AI Channel Chat"
PAUSED_BY_STAFF = "Выключено вручную"
LIST_LIMIT = 100
PAGE = 50


def _check():
	if not frappe.has_permission("Telegram Chat", "read"):
		frappe.throw(_("Нет доступа к перепискам"), frappe.PermissionError)


def _pair(chat):
	pair = frappe.db.get_value(PAIR, {"telegram_chat": chat}, ["name", "channel_doctype", "channel_name", "ai_paused"], as_dict=True, order_by="modified desc")
	if not pair:
		frappe.throw(_("Чат не подключён к боту"), frappe.DoesNotExistError)
	return pair


@frappe.whitelist()
def list():
	_check()
	rows = frappe.get_list(
		"Telegram Chat",
		fields=["name", "title", "last_message_content", "last_message_on"],
		filters={"type": "private"},
		order_by="last_message_on desc",
		page_length=LIST_LIMIT,
	)
	paused = dict(frappe.get_all(PAIR, filters={"telegram_chat": ["in", [r.name for r in rows]]}, fields=["telegram_chat", "ai_paused"], as_list=True))
	customers = dict(frappe.get_all("Dynamic Link", filters={"parenttype": "Telegram Chat", "parent": ["in", [r.name for r in rows]], "link_doctype": "Customer"}, fields=["parent", "link_name"], as_list=True))
	return [
		{"chat": r.name, "title": r.title or r.name, "preview": (r.last_message_content or "")[:80],
		 "last_at": str(r.last_message_on or ""), "paused": bool(paused.get(r.name)), "customer": customers.get(r.name)}
		for r in rows
	]


def _author(m):
	if m.direction == "Incoming":
		return "client"
	return "bot" if m.is_automated else "staff"


@frappe.whitelist()
def messages(chat, before=None):
	_check()
	filters = {"chat": chat, "is_deleted": 0}
	if before:
		filters["creation"] = ["<", before]
	rows = frappe.get_list("Telegram Message", fields=["name", "content", "creation", "direction", "is_automated"], filters=filters, order_by="creation desc", page_length=PAGE)
	return [{"name": m.name, "text": m.content or "", "at": str(m.creation), "author": _author(m)} for m in reversed(rows)]


@frappe.whitelist(methods=["POST"])
def pause(chat):
	_check()
	p = _pair(chat)
	telegram.pause((p.channel_doctype, p.channel_name), chat, PAUSED_BY_STAFF)


@frappe.whitelist(methods=["POST"])
def resume(chat):
	_check()
	p = _pair(chat)
	frappe.db.set_value(PAIR, p.name, {"ai_paused": 0, "paused_reason": None, "paused_on": None})


@frappe.whitelist(methods=["POST"])
def send(chat, text):
	"""Ответ сотрудника. Пауза — до отправки: иначе бот мог бы ответить поверх."""
	_check()
	if not (text or "").strip():
		frappe.throw(_("Пустое сообщение"))
	p = _pair(chat)
	telegram.pause((p.channel_doctype, p.channel_name), chat, PAUSED_BY_STAFF)
	telegram.send((p.channel_doctype, p.channel_name), chat, text.strip())
	# send помечает сообщение automated=True — это защита от самопаузы для
	# ответов бота. Здесь писал человек, и лента должна это показать.
	last = frappe.get_all(
		"Telegram Message", filters={"chat": chat, "direction": "Outgoing"},
		order_by="creation desc", pluck="name", limit=1,
	)
	if last:
		frappe.db.set_value("Telegram Message", last[0], "is_automated", 0, update_modified=False)
```

- [ ] **Step 4: Тесты проходят.** Run: команда шага 2 — PASS.

- [ ] **Step 5: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai && git add habibi_ai && git commit -m "feat(cabinet): переписки — лента, пауза бота, ответ сотрудника"
```

---

### Task 10: Режим работы, профиль и Telegram для кабинета

**Files:**
- Create: `habibi_ai/habibi_ai/cabinet/settings.py`
- Test: `habibi_ai/habibi_ai/tests/test_cabinet_settings.py`

**Interfaces:**
- Produces (`@frappe.whitelist()`):
  - `get_hours() -> {"time_zone": str, "schedule": [{"weekday", "kind", "opens", "closes"}], "exceptions": [{"date", "closed", "opens", "closes", "note"}]}`;
  - `save_hours(schedule, exceptions) -> dict` — заменяет таблицы целиком, возвращает `get_hours()`;
  - `get_profile() -> {"business_name", "business_kind", "address", "phone", "description", "tone", "rules": [{"title", "hint", "text"}]}`;
  - `save_profile(values) -> dict`;
  - `telegram_status() -> {"connected": bool, "username": str | None, "last_message_at": str | None}`;
  - `connect_telegram(token) -> dict` — создаёт или обновляет бота по умолчанию и ставит webhook; возвращает `telegram_status()`.
- `Working Hours` — одна запись на компанию из `Habibi AI Settings.company`; нет записи — создаётся при первом сохранении.

- [ ] **Step 1: Тест**

```python
from unittest.mock import patch

import frappe
from frappe.tests import IntegrationTestCase

from habibi_ai.cabinet import settings


class TestCabinetSettings(IntegrationTestCase):
	def tearDown(self):
		frappe.db.rollback()

	def test_режим_работы_заменяется_целиком(self):
		settings.save_hours([{"weekday": "Monday", "kind": "Работа", "opens": "10:00:00", "closes": "22:00:00"}], [])
		settings.save_hours([{"weekday": "Tuesday", "kind": "Работа", "opens": "11:00:00", "closes": "23:00:00"}], [])
		self.assertEqual([r["weekday"] for r in settings.get_hours()["schedule"]], ["Tuesday"])

	def test_профиль_не_трогает_подсказки(self):
		doc = frappe.get_single("Business Profile")
		doc.rules = []
		doc.append("rules", {"title": "Доставка", "hint": "Сколько стоит?", "text": ""})
		doc.save()
		settings.save_profile({"business_name": "Habibi", "rules": [{"title": "Доставка", "hint": "подмена", "text": "40 минут"}]})
		rule = settings.get_profile()["rules"][0]
		self.assertEqual((rule["hint"], rule["text"]), ("Сколько стоит?", "40 минут"))

	def test_лишние_поля_профиля_отбрасываются(self):
		settings.save_profile({"business_name": "Habibi", "owner": "evil@x"})
		self.assertNotEqual(frappe.db.get_value("Business Profile", "Business Profile", "owner"), "evil@x")

	def test_подключение_telegram(self):
		with patch("habibi_telegram.habibi_telegram.doctype.telegram_bot.telegram_bot.TelegramBot.validate_api_token"), \
			patch("habibi_telegram.habibi_telegram.doctype.telegram_bot.telegram_bot.TelegramBot.set_webhook") as hook:
			status = settings.connect_telegram("123:ABC")
		self.assertTrue(status["connected"])
		hook.assert_called_once()
```

Опции `kind` и значения `weekday` у `Working Hours Slot` взять из JSON доктайпа (`habibi_ai/habibi_ai/doctype/working_hours_slot/working_hours_slot.json`) и подставить в тест фактические — выше примерные.

- [ ] **Step 2: Запустить — падает.** Run: `bench --site dev.localhost run-tests --module habibi_ai.tests.test_cabinet_settings`

- [ ] **Step 3: Реализация**

```python
"""Настройки кабинета, которые не укладываются в «список + форма».

Каждый метод — один экран: читает и пишет документ целиком, чтобы экран не
собирал его из кусков и не мог сохранить половину.
"""

import frappe
from frappe import _

PROFILE_FIELDS = ("business_name", "business_kind", "address", "phone", "description", "tone")
SLOT_FIELDS = ("weekday", "kind", "opens", "closes")
EXCEPTION_FIELDS = ("date", "closed", "opens", "closes", "note")


def _hours_doc():
	company = frappe.db.get_single_value("Habibi AI Settings", "company")
	if not company:
		frappe.throw(_("Не выбрана компания в настройках ИИ"))
	name = frappe.db.get_value("Working Hours", {"company": company})
	if name:
		return frappe.get_doc("Working Hours", name)
	return frappe.get_doc({"doctype": "Working Hours", "company": company})


@frappe.whitelist()
def get_hours():
	doc = _hours_doc()
	return {
		"time_zone": doc.time_zone or "",
		"schedule": [{f: str(r.get(f) or "") for f in SLOT_FIELDS} for r in doc.schedule],
		"exceptions": [{f: (r.get(f) if f == "closed" else str(r.get(f) or "")) for f in EXCEPTION_FIELDS} for r in doc.exceptions],
	}


@frappe.whitelist(methods=["POST"])
def save_hours(schedule, exceptions):
	doc = _hours_doc()
	doc.schedule, doc.exceptions = [], []
	for row in frappe.parse_json(schedule) or []:
		doc.append("schedule", {f: row.get(f) or None for f in SLOT_FIELDS})
	for row in frappe.parse_json(exceptions) or []:
		doc.append("exceptions", {f: row.get(f) or None for f in EXCEPTION_FIELDS})
	doc.save() if not doc.is_new() else doc.insert()
	return get_hours()


@frappe.whitelist()
def get_profile():
	doc = frappe.get_single("Business Profile")
	return {
		**{f: doc.get(f) or "" for f in PROFILE_FIELDS},
		"rules": [{"title": r.title, "hint": r.hint or "", "text": r.text or ""} for r in doc.rules],
	}


@frappe.whitelist(methods=["POST"])
def save_profile(values):
	"""Подсказки правил — из пресета, владелец их не правит: сохраняем свои."""
	values = frappe.parse_json(values)
	doc = frappe.get_single("Business Profile")
	for f in PROFILE_FIELDS:
		if f in values:
			doc.set(f, values[f])
	if "rules" in values:
		hints = {r.title: r.hint for r in doc.rules}
		doc.rules = []
		for r in values["rules"]:
			if (r.get("title") or "").strip():
				doc.append("rules", {"title": r["title"].strip(), "hint": hints.get(r["title"].strip()), "text": r.get("text") or ""})
	doc.save()
	return get_profile()


def _bot():
	return frappe.db.get_value("Telegram Bot", {"is_default": 1}) or frappe.db.get_value("Telegram Bot", {})


@frappe.whitelist()
def telegram_status():
	name = _bot()
	if not name:
		return {"connected": False, "username": None, "last_message_at": None}
	bot = frappe.db.get_value("Telegram Bot", name, ["username", "webhook_enabled"], as_dict=True)
	last = frappe.db.get_value("Telegram Message", {"telegram_bot": name}, "creation", order_by="creation desc")
	return {"connected": bool(bot.webhook_enabled), "username": bot.username, "last_message_at": str(last) if last else None}


@frappe.whitelist(methods=["POST"])
def connect_telegram(token):
	if not frappe.has_permission("Telegram Bot", "write"):
		frappe.throw(_("Нет прав на подключение бота"), frappe.PermissionError)
	name = _bot()
	bot = frappe.get_doc("Telegram Bot", name) if name else frappe.new_doc("Telegram Bot")
	bot.api_token = (token or "").strip()
	bot.is_default = 1
	bot.webhook_enabled = 1
	bot.save() if name else bot.insert()
	bot.set_webhook()
	return telegram_status()
```

Поле `title` у `Telegram Bot` обязательно? Проверить в JSON доктайпа; если да — при создании ставить `bot.title = "Бот компании"`.

- [ ] **Step 4: Тесты проходят.** Run: команда шага 2 — PASS.

- [ ] **Step 5: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai && git add habibi_ai && git commit -m "feat(cabinet): режим работы, профиль и подключение Telegram"
```

---

### Task 11: Живое обновление

**Files:**
- Create: `habibi_ai/habibi_ai/cabinet/realtime.py`
- Modify: `habibi_ai/habibi_ai/hooks.py` (`doc_events`)
- Test: `habibi_ai/habibi_ai/tests/test_cabinet_realtime.py`

**Interfaces:**
- Produces: событие `habibi_cabinet` в комнату сайта с `{"topic": "chats" | "orders", "chat": str | None}`. Фронт по `orders` инвалидирует `["cabinet", "orders"]` и `["cabinet", "list", "orders"]`, по `chats` — `["cabinet", "chats"]` и `["cabinet", "messages", chat]`.

- [ ] **Step 1: Тест**

```python
from unittest.mock import patch

import frappe
from frappe.tests import IntegrationTestCase

from habibi_ai.cabinet import realtime


class TestRealtime(IntegrationTestCase):
	def test_сообщение_шлёт_событие_чатов(self):
		doc = frappe._dict(doctype="Telegram Message", chat="C1")
		with patch("habibi_ai.cabinet.realtime.frappe.publish_realtime") as pub:
			realtime.on_change(doc)
		pub.assert_called_once_with("habibi_cabinet", {"topic": "chats", "chat": "C1"}, after_commit=True)

	def test_заказ_не_от_бота_не_шумит(self):
		doc = frappe._dict(doctype="Sales Order", name="SO-X")
		with patch("habibi_ai.cabinet.realtime.frappe.publish_realtime") as pub:
			realtime.on_change(doc)
		pub.assert_not_called()
```

- [ ] **Step 2: Запустить — падает.**

- [ ] **Step 3: Реализация**

```python
"""События для кабинета: новое сообщение, новый или изменённый заказ от бота.

after_commit — иначе фронт перечитал бы данные раньше, чем они записаны, и
показал бы старое состояние до следующего события.
"""

import frappe

EVENT = "habibi_cabinet"


def on_change(doc, method=None):
	if doc.doctype == "Sales Order":
		if not frappe.db.exists("AI Order Quote", {"sales_order": doc.name}):
			return
		payload = {"topic": "orders", "chat": None}
	elif doc.doctype == "AI Channel Chat":
		payload = {"topic": "chats", "chat": doc.telegram_chat}
	else:
		payload = {"topic": "chats", "chat": doc.chat}
	frappe.publish_realtime(EVENT, payload, after_commit=True)
```

`hooks.py`, в существующий `doc_events`:

```python
doc_events = {
	"Telegram Message": {
		"after_insert": [
			"habibi_ai.channels.telegram.on_message_insert",
			"habibi_ai.cabinet.realtime.on_change",
		],
	},
	"Telegram Bot": {"validate": "habibi_ai.channels.telegram.validate_channel"},
	"Telegram Account": {"validate": "habibi_ai.channels.telegram.validate_channel"},
	"Sales Order": {"on_update": "habibi_ai.cabinet.realtime.on_change", "on_submit": "habibi_ai.cabinet.realtime.on_change"},
	"AI Channel Chat": {"on_update": "habibi_ai.cabinet.realtime.on_change"},
}
```

`frappe.db.set_value` в `pause`/`resume` не вызывает `on_update`. Поэтому в `chats.pause/resume/send` (задача 9) после записи вызвать `realtime.on_change(frappe._dict(doctype="AI Channel Chat", telegram_chat=chat))` — дописать туда и проверить в тестах задачи 9, что `publish_realtime` вызван.

- [ ] **Step 4: Тесты проходят.** Run: `--module habibi_ai.tests.test_cabinet_realtime` и `--module habibi_ai.tests.test_cabinet_chats` — PASS.

- [ ] **Step 5: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai && git add habibi_ai && git commit -m "feat(cabinet): события realtime для переписок и заказов"
```

---

### Task 12: Пресет «общепит» и команда `apply-preset`

**Files:**
- Create: `habibi_ai/habibi_ai/preset_rules.py`
- Create: `habibi_ai/habibi_ai/presets/food.json`
- Create: `habibi_ai/habibi_ai/presets.py`
- Create: `habibi_ai/habibi_ai/commands/__init__.py`
- Test: `habibi_ai/habibi_ai/tests/test_preset_rules.py`, `test_presets.py`

**Interfaces:**
- Consumes: `Cabinet Settings` (задача 3), `Business Profile` (задача 5), `Habibi AI Settings.feature_*`, `accept_action`, `reject_action` (задачи 5, 8), `Telegram Message Template`.
- Produces:
  - `preset_rules.merge_sections(current: list[dict], preset: list[dict]) -> list[dict]` — по `key`: пресет обновляет, чужие остаются, порядок — пресет, затем чужие;
  - `preset_rules.merge_rules(current: list[dict], preset: list[dict]) -> list[dict]` — по `title`: `text` текущего сохраняется, `hint` из пресета; свои правила владельца остаются в конце;
  - `presets.apply(name: str) -> dict` — сводка `{"sections": int, "rules": int, "templates_created": int}`;
  - `bench --site <site> habibi-ai apply-preset <name>`.

- [ ] **Step 1: Тест без frappe**

```python
import unittest

from habibi_ai import preset_rules as p


class TestMergeSections(unittest.TestCase):
	def test_обновляет_свои_и_оставляет_чужие(self):
		current = [{"key": "menu", "label": "Старое"}, {"key": "custom_x", "label": "Своё"}]
		preset = [{"key": "orders", "label": "Заказы"}, {"key": "menu", "label": "Меню"}]
		self.assertEqual(
			p.merge_sections(current, preset),
			[{"key": "orders", "label": "Заказы"}, {"key": "menu", "label": "Меню"}, {"key": "custom_x", "label": "Своё"}],
		)

	def test_повтор_ничего_не_меняет(self):
		preset = [{"key": "menu", "label": "Меню"}]
		once = p.merge_sections([], preset)
		self.assertEqual(p.merge_sections(once, preset), once)


class TestMergeRules(unittest.TestCase):
	def test_заполненный_текст_не_перетирается(self):
		current = [{"title": "Доставка", "hint": "старая", "text": "40 минут"}]
		preset = [{"title": "Доставка", "hint": "Сколько стоит?"}, {"title": "Оплата", "hint": "Как платить?"}]
		self.assertEqual(
			p.merge_rules(current, preset),
			[{"title": "Доставка", "hint": "Сколько стоит?", "text": "40 минут"}, {"title": "Оплата", "hint": "Как платить?", "text": ""}],
		)

	def test_свои_правила_владельца_остаются(self):
		current = [{"title": "Парковка", "hint": "", "text": "Есть"}]
		self.assertEqual(p.merge_rules(current, [])[0]["title"], "Парковка")
```

Run: `$DC exec -T frappe bash -lc "cd /workspace/repos/habibi_ai && $PY -m unittest habibi_ai.tests.test_preset_rules -v"` — FAIL.

- [ ] **Step 2: Реализация без frappe**

```python
"""Слияние пресета вертикали с тем, что уже настроено на сайте. Без frappe.

Пресет можно применять повторно — после обновления кода или по ошибке.
Поэтому он ничего не удаляет и не перетирает то, что написал владелец.
"""


def merge_sections(current, preset):
	by_key = {s["key"]: s for s in current}
	result = [{**by_key.get(s["key"], {}), **s} for s in preset]
	keys = {s["key"] for s in preset}
	return result + [s for s in current if s["key"] not in keys]


def merge_rules(current, preset):
	by_title = {r["title"]: r for r in current}
	result = [{"title": r["title"], "hint": r.get("hint", ""), "text": (by_title.get(r["title"]) or {}).get("text", "")} for r in preset]
	titles = {r["title"] for r in preset}
	return result + [r for r in current if r["title"] not in titles]
```

Run — PASS, 4 теста.

- [ ] **Step 3: Пресет**

`presets/food.json` (действия воркфлоу — из шага 3 задачи 0):

```json
{
  "features": {"feature_delivery": 1, "feature_orders": 1},
  "workflow": {"accept_action": "Confirm", "reject_action": "Cancel"},
  "sections": [
    {"key": "home", "label": "Главная", "icon": "home", "kind": "custom", "screen": "home"},
    {"key": "orders", "label": "Заказы", "icon": "receipt", "kind": "generic", "ref_doctype": "Sales Order",
     "list_fields": "name:Номер\ncustomer_name:Клиент\ngrand_total:Сумма\ncustom_fulfilment_type:Получение\ntransaction_date:Дата\nworkflow_state:Статус\ndocstatus:Проведён",
     "form_fields": "name:Номер\ncustomer_name:Клиент\ncustom_whatsapp_number:Телефон\ncustom_fulfilment_type:Получение\ncustom_delivery_zone:Зона\ncustom_kitchen_notes:Комментарий\ngrand_total:Сумма",
     "base_filters": "{\"custom_agent_handled\": 1}", "feature": "orders"},
    {"key": "chats", "label": "Переписки", "icon": "message-circle", "kind": "custom", "screen": "chats"},
    {"key": "customers", "label": "Клиенты", "icon": "users", "kind": "generic", "ref_doctype": "Customer",
     "list_fields": "customer_name:Имя\nmobile_no:Телефон", "form_fields": "customer_name:Имя\nmobile_no:Телефон"},
    {"key": "menu", "label": "Меню", "icon": "utensils", "kind": "generic", "ref_doctype": "Item",
     "list_fields": "item_name:Название\nitem_group:Группа\n@selling_price:Цена\ndisabled:Снято с продажи",
     "form_fields": "item_name:Название\nitem_group:Группа\n@selling_price:Цена\ndescription:Описание\nimage:Фото\ndisabled:Снято с продажи",
     "base_filters": "{\"is_sales_item\": 1}", "can_create": 1, "can_edit": 1, "roles": "Habibi Owner"},
    {"key": "zones", "label": "Зоны доставки", "icon": "map", "kind": "generic", "ref_doctype": "Delivery Zone",
     "list_fields": "name:Зона\ndelivery_fee:Стоимость", "form_fields": "delivery_fee:Стоимость\nfree_above:Бесплатно от",
     "can_edit": 1, "roles": "Habibi Owner", "feature": "delivery"},
    {"key": "hours", "label": "Режим работы", "icon": "clock", "kind": "custom", "screen": "hours", "roles": "Habibi Owner"},
    {"key": "profile", "label": "О компании", "icon": "building", "kind": "custom", "screen": "profile", "roles": "Habibi Owner"},
    {"key": "telegram", "label": "Telegram", "icon": "send", "kind": "custom", "screen": "telegram", "roles": "Habibi Owner"}
  ],
  "rules": [
    {"title": "Доставка", "hint": "Сколько идёт доставка? Сколько стоит? Куда не возите?"},
    {"title": "Самовывоз", "hint": "Откуда забирать, сколько ждать?"},
    {"title": "Оплата", "hint": "Какие способы оплаты принимаете?"}
  ],
  "templates": {
    "order_accepted": "Заказ {order} принят! Сумма {total}. Спасибо, {customer}!",
    "order_rejected": "К сожалению, не сможем выполнить заказ {order}: {reason}"
  },
  "permissions": {
    "Habibi Owner": {"Sales Order": ["read", "write", "submit", "cancel", "delete"], "Customer": ["read"], "Item": ["read", "write", "create"],
      "Item Price": ["read", "write", "create"], "Item Group": ["read"], "Delivery Zone": ["read", "write"], "Working Hours": ["read", "write", "create"],
      "Telegram Chat": ["read"], "Telegram Message": ["read"], "Telegram Bot": ["read", "write", "create"], "AI Channel Chat": ["read", "write"], "AI Order Quote": ["read"],
      "Business Profile": ["read", "write"], "Habibi AI Settings": ["read"], "Price List": ["read"], "Company": ["read"]},
    "Habibi Staff": {"Sales Order": ["read", "write", "submit", "cancel"], "Customer": ["read"], "Item": ["read"], "Telegram Chat": ["read"],
      "Telegram Message": ["read"], "AI Channel Chat": ["read", "write"], "AI Order Quote": ["read"], "Habibi AI Settings": ["read"], "Company": ["read"]}
  }
}
```

Поля `custom_*` есть не везде (Review Focus 1): раздел «Заказы» на `dev.localhost` выпадет из `config()` целиком. Поэтому `presets.apply` перед записью убирает из строк раздела поля, которых нет в мете DocType, и базовые фильтры по отсутствующим полям, а в сводку пишет, что убрано. Раздел, у которого не осталось ни одного поля списка или нет самого DocType, пропускается.

- [ ] **Step 4: Тест на сайте**

```python
import frappe
from frappe.tests import IntegrationTestCase

from habibi_ai import presets


class TestPresets(IntegrationTestCase):
	def tearDown(self):
		frappe.db.rollback()

	def test_повторное_применение_ничего_не_ломает(self):
		presets.apply("food")
		profile = frappe.get_single("Business Profile")
		profile.rules[0].text = "40 минут"
		profile.save()
		frappe.db.set_value("Telegram Message Template", "order_accepted", "default_template", "Свой текст")
		presets.apply("food")
		self.assertEqual(frappe.get_single("Business Profile").rules[0].text, "40 минут")
		self.assertEqual(frappe.db.get_value("Telegram Message Template", "order_accepted", "default_template"), "Свой текст")

	def test_отсутствующие_поля_вычищаются(self):
		summary = presets.apply("food")
		keys = [s.key for s in frappe.get_single("Cabinet Settings").sections]
		self.assertIn("menu", keys)
		if not frappe.db.exists("DocType", "Delivery Zone"):
			self.assertNotIn("zones", keys)
			self.assertIn("zones", summary["skipped"])

	def test_права_ролей_выданы(self):
		presets.apply("food")
		self.assertTrue(frappe.db.exists("Custom DocPerm", {"parent": "Item", "role": "Habibi Owner", "write": 1}))
```

- [ ] **Step 5: Реализация `presets.py` и команды**

```python
"""Применение пресета вертикали к сайту: разделы, правила, флаги, шаблоны, права.

Идемпотентно — см. preset_rules. Поля пресета, которых нет на сайте,
вычищаются здесь, а не в кабинете: иначе раздел целиком выпадал бы из-за
одного своего поля, заведённого руками только на проде.
"""

import json
import os

import frappe
from frappe.permissions import add_permission, update_permission_property

from habibi_ai import preset_rules
from habibi_ui.cabinet.fields import parse_fields


def _load(name):
	path = os.path.join(frappe.get_app_path("habibi_ai"), "presets", f"{name}.json")
	with open(path) as f:
		return json.load(f)


def _fit(section, skipped):
	if section["kind"] != "generic":
		return section
	if not frappe.db.exists("DocType", section["ref_doctype"]):
		skipped.append(section["key"])
		return None
	meta = frappe.get_meta(section["ref_doctype"])
	fitted = {**section, "list_fields": _keep_existing(section.get("list_fields"), meta), "form_fields": _keep_existing(section.get("form_fields"), meta)}
	if section.get("base_filters"):
		base = json.loads(section["base_filters"])
		fitted["base_filters"] = json.dumps({k: v for k, v in base.items() if meta.get_field(k)}) if isinstance(base, dict) else section["base_filters"]
	if not fitted["list_fields"]:
		skipped.append(section["key"])
		return None
	return fitted
```

```python
def _keep_existing(lines, meta):
	return "\n".join(
		("@" if s.adapter else "") + s.fieldname + (f":{s.label}" if s.label else "")
		for s in parse_fields(lines)
		if s.adapter or s.fieldname == "name" or meta.get_field(s.fieldname)
	)


def apply(name):
	preset = _load(name)
	skipped = []

	cabinet = frappe.get_single("Cabinet Settings")
	current = [r.as_dict(no_default_fields=True) for r in cabinet.sections]
	fitted = [s for s in (_fit(s, skipped) for s in preset["sections"]) if s]
	cabinet.sections = []
	for s in preset_rules.merge_sections(current, fitted):
		cabinet.append("sections", s)
	cabinet.save()

	profile = frappe.get_single("Business Profile")
	rules = preset_rules.merge_rules([r.as_dict(no_default_fields=True) for r in profile.rules], preset["rules"])
	profile.rules = []
	for r in rules:
		profile.append("rules", r)
	profile.save()

	settings = frappe.get_single("Habibi AI Settings")
	settings.update({**preset["features"], **preset["workflow"]})
	settings.save()

	created = 0
	for key, text in preset["templates"].items():
		if not frappe.db.exists("Telegram Message Template", key):
			frappe.get_doc({"doctype": "Telegram Message Template", "template_name": key, "default_template": text}).insert()
			created += 1

	for role, doctypes in preset["permissions"].items():
		for doctype, rights in doctypes.items():
			if not frappe.db.exists("DocType", doctype):
				continue
			add_permission(doctype, role, 0)
			for right in rights:
				update_permission_property(doctype, role, 0, right, 1)

	return {"sections": len(fitted), "rules": len(rules), "templates_created": created, "skipped": skipped}
```

`habibi_ai` и так зависит от `habibi_ui` (`required_apps`), поэтому импорт `habibi_ui.cabinet.fields` отсюда законен.

`commands/__init__.py`:

```python
"""Команды bench: `bench --site <site> habibi-ai <команда>`."""

import click
import frappe
from frappe.commands import get_site, pass_context


@click.group("habibi-ai")
def habibi_ai():
	"""Habibi AI"""


@click.command("apply-preset")
@click.argument("name")
@pass_context
def apply_preset(context, name):
	"""Применить пресет вертикали (например, food)"""
	site = get_site(context)
	frappe.init(site=site)
	frappe.connect()
	try:
		from habibi_ai.presets import apply

		summary = apply(name)
		frappe.db.commit()
		click.echo(f"Пресет {name}: {summary}")
	finally:
		frappe.destroy()


habibi_ai.add_command(apply_preset)
commands = [habibi_ai]
```

- [ ] **Step 6: Тесты проходят, команда работает**

Run: `--module habibi_ai.tests.test_presets`, затем `bench --site dev.localhost habibi-ai apply-preset food` дважды.
Expected: PASS; второй запуск печатает ту же сводку с `templates_created: 0`.

- [ ] **Step 7: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai && git add habibi_ai && git commit -m "feat(cabinet): пресет «общепит» и команда apply-preset"
```

---

### Task 13: Фронт — оболочка кабинета и универсальные разделы

**Files:**
- Modify: `habibi_ui/package.json` — скрипт `typecheck`
- Create: `habibi_ui/frontend/src/features/cabinet/api.ts`
- Create: `habibi_ui/frontend/src/features/cabinet/CabinetShell.tsx`
- Create: `habibi_ui/frontend/src/features/cabinet/GenericList.tsx`
- Create: `habibi_ui/frontend/src/features/cabinet/GenericForm.tsx`
- Create: `habibi_ui/frontend/src/features/cabinet/FieldInput.tsx`
- Create: `habibi_ui/frontend/src/features/cabinet/screens.tsx` — реестр `custom`-экранов
- Create: `habibi_ui/frontend/src/features/cabinet/useRealtime.ts`
- Modify: `habibi_ui/frontend/src/App.tsx`, `habibi_ui/frontend/src/shared/ui/Launcher.tsx` (редирект по `home`)

**Interfaces:**
- Consumes: `CabinetSection`, `CabinetField`, `Me` из `shared/types/api.ts`; `call()` из `shared/api/client.ts`; методы задачи 3; событие `habibi_cabinet` (задача 11).
- Produces: маршруты `/c` → первый раздел, `/c/:key`, `/c/:key/new`, `/c/:key/:name`; `SCREENS: Record<string, ComponentType<{ section: CabinetSection }>>` — задачи 14–15 регистрируют там свои экраны; хуки `useCabinetConfig()`, `useSectionList(key, filters)`, `useSectionDoc(key, name)`, `useSaveSectionDoc(key)`.

- [ ] **Step 1: Проверка типов в сборке**

`package.json`:

```json
    "typecheck": "tsc -p frontend/tsconfig.json --noEmit",
```

Run: `yarn typecheck` на текущем `main` — должно пройти. Если падает на существующем коде — остановиться и сообщить, не чинить мимоходом.

- [ ] **Step 2: API-хуки**

```ts
// features/cabinet/api.ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { call } from "../../shared/api/client";
import type { CabinetSection } from "../../shared/types/api";

export type Row = Record<string, unknown> & { name: string };
export type Filter = [string, string, unknown];

export function useCabinetConfig() {
  return useQuery({
    queryKey: ["cabinet", "config"],
    queryFn: () => call<CabinetSection[]>("habibi_ui.api.v1.cabinet.config"),
    staleTime: 5 * 60_000,
  });
}

export function useSectionList(key: string, filters: Filter[]) {
  return useQuery({
    queryKey: ["cabinet", "list", key, filters],
    queryFn: () =>
      call<{ rows: Row[]; has_more: boolean }>("habibi_ui.api.v1.cabinet.list", { section: key, filters }),
  });
}

export function useSectionDoc(key: string, name: string | null) {
  return useQuery({
    queryKey: ["cabinet", "doc", key, name],
    queryFn: () => call<Row>("habibi_ui.api.v1.cabinet.get", { section: key, name }),
    enabled: name !== null,
  });
}

export function useSaveSectionDoc(key: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ name, values }: { name: string | null; values: Record<string, unknown> }) =>
      call<Row>("habibi_ui.api.v1.cabinet.save", { section: key, name, values }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["cabinet", "list", key] }),
  });
}
```

- [ ] **Step 3: Оболочка и маршруты**

```tsx
// features/cabinet/CabinetShell.tsx
import { NavLink, Navigate, Outlet, useParams } from "react-router-dom";

import { Skeleton } from "../../shared/ui/skeleton";
import { useCabinetConfig } from "./api";
import { useRealtime } from "./useRealtime";

// Таб-бар телефона: первые разделы по порядку, остальное — в «Ещё».
// Какие разделы первые, решает пресет порядком строк, а не этот код.
const TABS = 3;

export function CabinetShell() {
  const config = useCabinetConfig();
  useRealtime();

  if (config.isPending) return <Skeleton className="m-4 h-40" />;
  if (config.error) return <p className="p-4 text-destructive">{config.error.message}</p>;

  const sections = config.data;
  const tabs = sections.slice(0, TABS);

  return (
    <div className="flex min-h-dvh flex-col md:flex-row">
      <nav className="hidden w-56 shrink-0 border-r border-border p-3 md:block">
        {sections.map((s) => (
          <NavLink
            key={s.key}
            to={`/c/${s.key}`}
            className={({ isActive }) =>
              `block rounded-lg px-3 py-2 text-sm ${isActive ? "bg-accent font-medium" : "hover:bg-accent/60"}`
            }
          >
            {s.label}
          </NavLink>
        ))}
      </nav>
      <main className="min-w-0 flex-1 p-4 pb-20 md:pb-4">
        <Outlet />
      </main>
      <nav className="fixed inset-x-0 bottom-0 flex border-t border-border bg-background md:hidden">
        {tabs.map((s) => (
          <NavLink key={s.key} to={`/c/${s.key}`} className="flex-1 py-3 text-center text-xs">
            {s.label}
          </NavLink>
        ))}
        {sections.length > TABS && (
          <NavLink to="/c/more" className="flex-1 py-3 text-center text-xs">
            Ещё
          </NavLink>
        )}
      </nav>
    </div>
  );
}

export function CabinetIndex() {
  const config = useCabinetConfig();
  if (!config.data?.length) return null;
  return <Navigate to={`/c/${config.data[0].key}`} replace />;
}

export function MorePage() {
  const config = useCabinetConfig();
  return (
    <ul className="divide-y divide-border rounded-2xl border border-border">
      {config.data?.slice(TABS).map((s) => (
        <li key={s.key}>
          <NavLink to={`/c/${s.key}`} className="block px-4 py-3">
            {s.label}
          </NavLink>
        </li>
      ))}
    </ul>
  );
}

export function SectionRoute() {
  const { key = "" } = useParams<{ key: string }>();
  const config = useCabinetConfig();
  const section = config.data?.find((s) => s.key === key);
  if (!section) return <p className="text-muted-foreground">Раздел недоступен</p>;
  if (section.kind === "custom") {
    const Screen = SCREENS[section.screen];
    return Screen ? <Screen section={section} /> : <p className="text-muted-foreground">Экран не найден</p>;
  }
  return <GenericList section={section} />;
}
```

Импорты `SCREENS` из `./screens` и `GenericList` из `./GenericList` — в шапке файла. `screens.tsx` на этом шаге:

```tsx
import type { ComponentType } from "react";

import type { CabinetSection } from "../../shared/types/api";

// Рукописные экраны по имени из Cabinet Section.screen. Имя неизвестно —
// SectionRoute показывает «Экран не найден», а не падает: пресет может
// оказаться новее фронта.
export const SCREENS: Record<string, ComponentType<{ section: CabinetSection }>> = {};
```

`App.tsx` — добавить маршруты:

```tsx
      <Route path="/c" element={<CabinetShell />}>
        <Route index element={<CabinetIndex />} />
        <Route path="more" element={<MorePage />} />
        <Route path=":key" element={<SectionRoute />} />
        <Route path=":key/new" element={<GenericFormRoute />} />
        <Route path=":key/:name" element={<GenericFormRoute />} />
      </Route>
```

`Launcher.tsx` — в начале компонента: если `me.home === "cabinet"`, `return <Navigate to="/c" replace />`. `me` уже запрашивается лаунчером через `shared/api/queries.ts`; если нет — взять хук оттуда.

- [ ] **Step 4: Список и форма**

```tsx
// features/cabinet/GenericList.tsx
import { useState } from "react";
import { Link } from "react-router-dom";

import type { CabinetSection } from "../../shared/types/api";
import { Skeleton } from "../../shared/ui/skeleton";
import { type Filter, useSectionList } from "./api";
import { formatValue } from "./FieldInput";

export function GenericList({ section }: { section: CabinetSection }) {
  const [search, setSearch] = useState("");
  const firstText = section.list_fields.find((f) => f.fieldtype === "Data");
  const filters: Filter[] = search && firstText ? [[firstText.fieldname, "like", `%${search}%`]] : [];
  const list = useSectionList(section.key, filters);

  return (
    <section className="space-y-3">
      <header className="flex items-center gap-2">
        <h1 className="flex-1 text-xl font-semibold">{section.label}</h1>
        {section.can_create && (
          <Link to={`/c/${section.key}/new`} className="rounded-lg bg-primary px-3 py-2 text-sm text-primary-foreground">
            Добавить
          </Link>
        )}
      </header>
      {firstText && (
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Поиск"
          className="w-full rounded-lg border border-border bg-background px-3 py-2"
        />
      )}
      {list.isPending && <Skeleton className="h-40" />}
      {list.error && <p className="text-destructive">{list.error.message}</p>}
      <ul className="divide-y divide-border rounded-2xl border border-border">
        {list.data?.rows.map((row) => (
          <li key={row.name}>
            <Link to={`/c/${section.key}/${encodeURIComponent(row.name)}`} className="block px-4 py-3">
              <div className="font-medium">{formatValue(section.list_fields[0], row[section.list_fields[0].fieldname])}</div>
              <div className="text-sm text-muted-foreground">
                {section.list_fields
                  .slice(1)
                  .map((f) => formatValue(f, row[f.fieldname]))
                  .filter(Boolean)
                  .join(" · ")}
              </div>
            </Link>
          </li>
        ))}
        {list.data?.rows.length === 0 && <li className="px-4 py-6 text-center text-muted-foreground">Пусто</li>}
      </ul>
    </section>
  );
}
```

```tsx
// features/cabinet/FieldInput.tsx
import type { CabinetField } from "../../shared/types/api";

export function formatValue(field: CabinetField, value: unknown): string {
  if (value === null || value === undefined || value === "") return "";
  if (field.fieldtype === "Check") return value ? field.label : "";
  if (field.fieldtype === "Currency" || field.fieldtype === "Float") return Number(value).toLocaleString("ru-RU");
  return String(value);
}

type Props = { field: CabinetField; value: unknown; disabled: boolean; onChange: (value: unknown) => void };

// ~10 типов полей, которые реально встречаются в разделах пресетов. Остальные
// показываются только чтением: полный движок форм — отдельная задача (Блок 3
// спеки habibi_ui), кабинету он не нужен.
export function FieldInput({ field, value, disabled, onChange }: Props) {
  const common = "w-full rounded-lg border border-border bg-background px-3 py-2 disabled:opacity-60";
  const readOnly = disabled || field.read_only;
  switch (field.fieldtype) {
    case "Check":
      return <input type="checkbox" checked={Boolean(value)} disabled={readOnly} onChange={(e) => onChange(e.target.checked ? 1 : 0)} />;
    case "Currency":
    case "Float":
    case "Int":
      return <input type="number" className={common} value={value === null || value === undefined ? "" : String(value)} disabled={readOnly} onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))} />;
    case "Small Text":
    case "Text":
    case "Text Editor":
      return <textarea rows={4} className={common} value={String(value ?? "")} disabled={readOnly} onChange={(e) => onChange(e.target.value)} />;
    case "Select":
      return (
        <select className={common} value={String(value ?? "")} disabled={readOnly} onChange={(e) => onChange(e.target.value)}>
          {field.options.split("\n").map((o) => (
            <option key={o} value={o}>{o}</option>
          ))}
        </select>
      );
    case "Date":
      return <input type="date" className={common} value={String(value ?? "")} disabled={readOnly} onChange={(e) => onChange(e.target.value)} />;
    case "Data":
    case "Link":
    case "Phone":
      return <input className={common} value={String(value ?? "")} disabled={readOnly} onChange={(e) => onChange(e.target.value)} />;
    default:
      return <div className="py-2">{formatValue(field, value)}</div>;
  }
}
```

`Link`-поле здесь — простой ввод текста. Выбор из справочника (группа позиции) — поле `item_group` пресета; если на ревью это окажется неудобно, это отдельная доработка, не в этой задаче.

```tsx
// features/cabinet/GenericForm.tsx
import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";

import { Skeleton } from "../../shared/ui/skeleton";
import { useCabinetConfig, useSaveSectionDoc, useSectionDoc } from "./api";
import { FieldInput } from "./FieldInput";

// Отдельные экраны действий (заказ) подменяют форму через ACTIONS — см. задачу 14.
export const ACTIONS: Record<string, React.ComponentType<{ name: string }>> = {};

export function GenericFormRoute() {
  const { key = "", name } = useParams<{ key: string; name?: string }>();
  const navigate = useNavigate();
  const section = useCabinetConfig().data?.find((s) => s.key === key);
  const doc = useSectionDoc(key, name ? decodeURIComponent(name) : null);
  const save = useSaveSectionDoc(key);
  const [values, setValues] = useState<Record<string, unknown>>({});

  useEffect(() => {
    if (doc.data) setValues(doc.data);
  }, [doc.data]);

  if (!section) return <p className="text-muted-foreground">Раздел недоступен</p>;
  if (name && doc.isPending) return <Skeleton className="h-60" />;

  const editable = name ? section.can_edit : section.can_create;
  const Actions = name ? ACTIONS[key] : undefined;

  return (
    <form
      className="max-w-xl space-y-4"
      onSubmit={(e) => {
        e.preventDefault();
        save.mutate(
          { name: name ? decodeURIComponent(name) : null, values },
          { onSuccess: (saved) => navigate(`/c/${key}/${encodeURIComponent(saved.name)}`, { replace: true }) },
        );
      }}
    >
      {section.form_fields.map((f) => (
        <label key={f.fieldname} className="block space-y-1">
          <span className="text-sm text-muted-foreground">{f.label}</span>
          <FieldInput field={f} value={values[f.fieldname]} disabled={!editable} onChange={(v) => setValues((old) => ({ ...old, [f.fieldname]: v }))} />
        </label>
      ))}
      {save.error && <p className="text-destructive">{save.error.message}</p>}
      {editable && (
        <button type="submit" disabled={save.isPending} className="rounded-lg bg-primary px-4 py-2 text-primary-foreground">
          Сохранить
        </button>
      )}
      {Actions && name && <Actions name={decodeURIComponent(name)} />}
    </form>
  );
}
```

- [ ] **Step 5: Realtime**

```ts
// features/cabinet/useRealtime.ts
import { useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";

type Event = { topic: "chats" | "orders"; chat: string | null };

/**
 * Подписка на habibi_cabinet через socket.io Frappe.
 *
 * Клиент socket.io Frappe на странице /ui не подключён: это не Desk. Поэтому
 * подключаемся сами к /socket.io того же origin — кука сессии уходит сама.
 * Нет socket.io (dev-сервер vite без прокси) — кабинет работает без живого
 * обновления, данные обновятся при переходе.
 */
export function useRealtime() {
  const queryClient = useQueryClient();
  useEffect(() => {
    let socket: { on: (e: string, cb: (d: Event) => void) => void; disconnect: () => void } | null = null;
    let cancelled = false;
    import("socket.io-client")
      .then(({ io }) => {
        if (cancelled) return;
        socket = io(`${window.location.origin}/${window.habibi.site_name ?? ""}`, { withCredentials: true });
        socket.on("habibi_cabinet", (event) => {
          if (event.topic === "orders") {
            void queryClient.invalidateQueries({ queryKey: ["cabinet", "list", "orders"] });
            void queryClient.invalidateQueries({ queryKey: ["cabinet", "home"] });
          } else {
            void queryClient.invalidateQueries({ queryKey: ["cabinet", "chats"] });
            if (event.chat) void queryClient.invalidateQueries({ queryKey: ["cabinet", "messages", event.chat] });
            void queryClient.invalidateQueries({ queryKey: ["cabinet", "home"] });
          }
        });
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
      socket?.disconnect();
    };
  }, [queryClient]);
}
```

Зависимость: `yarn add socket.io-client@^4` (версию сверить с `apps/frappe/package.json` — она должна совпадать с серверной). Frappe v16 ждёт неймспейс `/<site_name>`: добавить `site_name` в `window.habibi` — в `www/ui.py` (контекст страницы) и в `session.boot()`, плюс поле `site_name?: string` в `shared/types/global.d.ts`. Перед реализацией открыть `apps/frappe/frappe/public/js/frappe/socketio_client.js` и повторить его способ подключения (путь, неймспейс, `withCredentials`) — в плане он описан по памяти, источник истины там.

- [ ] **Step 6: Проверка**

Run: `yarn typecheck && yarn build`. Expected: без ошибок.

Ручная проверка на `dev.localhost` (`bench --site dev.localhost habibi-ai apply-preset food`, пользователь с ролью `Habibi Owner`): вход ведёт на `/ui/c`; раздел «Меню» — список, «Добавить», форма с ценой, сохранение; телефонная ширина (375px) — таб-бар снизу.

- [ ] **Step 7: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ui && git add package.json yarn.lock frontend habibi_ui/www habibi_ui/api && git commit -m "feat(cabinet): оболочка кабинета, универсальные список и форма, realtime"
```

---

### Task 14: Фронт — заказы и переписки

**Files:**
- Create: `habibi_ui/frontend/src/features/cabinet/orders/OrderActions.tsx`
- Create: `habibi_ui/frontend/src/features/cabinet/orders/api.ts`
- Create: `habibi_ui/frontend/src/features/cabinet/chats/ChatsScreen.tsx`
- Create: `habibi_ui/frontend/src/features/cabinet/chats/api.ts`
- Modify: `habibi_ui/frontend/src/features/cabinet/screens.tsx`, `GenericForm.tsx` (регистрация `ACTIONS.orders`)

**Interfaces:**
- Consumes: `habibi_ai.cabinet.orders.{actions, apply, notify}` (задача 8), `habibi_ai.cabinet.chats.{list, messages, send, pause, resume}` (задача 9).
- Produces: `SCREENS.chats`, `ACTIONS.orders`.

Раздел ИИ появляется, только если стоит `habibi_ai` — это уже так: без него пресет не применить и разделов `orders`/`chats` нет.

- [ ] **Step 1: API заказов и переписок**

```ts
// features/cabinet/orders/api.ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { call } from "../../../shared/api/client";

export type OrderAction = { action: string; kind: "accept" | "reject" | "other" };
export type Notify = { kind: "accept" | "reject"; text: string; chat: string };

export function useOrderActions(name: string) {
  return useQuery({
    queryKey: ["cabinet", "order-actions", name],
    queryFn: () => call<{ state: string; actions: OrderAction[]; can_notify: boolean }>("habibi_ai.cabinet.orders.actions", { name }),
  });
}

export function useApplyAction(name: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ action, reason }: { action: string; reason: string }) =>
      call<{ state: string; notify: Notify | null }>("habibi_ai.cabinet.orders.apply", { name, action, reason }),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["cabinet", "order-actions", name] });
      void queryClient.invalidateQueries({ queryKey: ["cabinet", "list", "orders"] });
    },
  });
}

export function useNotify(name: string) {
  return useMutation({
    mutationFn: ({ text, chat }: { text: string; chat: string }) =>
      call<{ sent: boolean; error: string | null }>("habibi_ai.cabinet.orders.notify", { name, text, chat }),
  });
}
```

```ts
// features/cabinet/chats/api.ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { call } from "../../../shared/api/client";

export type ChatItem = { chat: string; title: string; preview: string; last_at: string; paused: boolean; customer: string | null };
export type ChatMessage = { name: string; text: string; at: string; author: "client" | "bot" | "staff" };

export const useChatList = () =>
  useQuery({ queryKey: ["cabinet", "chats"], queryFn: () => call<ChatItem[]>("habibi_ai.cabinet.chats.list") });

export const useMessages = (chat: string | null) =>
  useQuery({
    queryKey: ["cabinet", "messages", chat],
    queryFn: () => call<ChatMessage[]>("habibi_ai.cabinet.chats.messages", { chat }),
    enabled: chat !== null,
  });

export function useChatCommand(method: "send" | "pause" | "resume") {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (args: { chat: string; text?: string }) => call<null>(`habibi_ai.cabinet.chats.${method}`, args),
    onSuccess: (_d, { chat }) => {
      void queryClient.invalidateQueries({ queryKey: ["cabinet", "chats"] });
      void queryClient.invalidateQueries({ queryKey: ["cabinet", "messages", chat] });
    },
  });
}
```

- [ ] **Step 2: Действия с заказом**

```tsx
// features/cabinet/orders/OrderActions.tsx
import { useState } from "react";

import { type Notify, useApplyAction, useNotify, useOrderActions } from "./api";

const LABELS = { accept: "Принять", reject: "Отклонить" } as const;

export function OrderActions({ name }: { name: string }) {
  const actions = useOrderActions(name);
  const apply = useApplyAction(name);
  const notify = useNotify(name);
  const [draft, setDraft] = useState<Notify | null>(null);
  const [reason, setReason] = useState("");

  if (!actions.data) return null;

  return (
    <div className="space-y-3 rounded-2xl border border-border p-4">
      <div className="text-sm text-muted-foreground">Статус: {actions.data.state}</div>
      <div className="flex flex-wrap gap-2">
        {actions.data.actions.map((a) => (
          <button
            key={a.action}
            type="button"
            disabled={apply.isPending}
            onClick={() => apply.mutate({ action: a.action, reason }, { onSuccess: (r) => r.notify && setDraft(r.notify) })}
            className={`rounded-lg px-3 py-2 text-sm ${a.kind === "reject" ? "border border-destructive text-destructive" : "bg-primary text-primary-foreground"}`}
          >
            {a.kind === "other" ? a.action : LABELS[a.kind]}
          </button>
        ))}
      </div>
      {actions.data.actions.some((a) => a.kind === "reject") && (
        <input
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="Причина отказа (для сообщения клиенту)"
          className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm"
        />
      )}
      {apply.error && <p className="text-destructive">{apply.error.message}</p>}
      {draft && (
        <div className="space-y-2">
          <div className="text-sm font-medium">Сообщение клиенту</div>
          <textarea rows={3} value={draft.text} onChange={(e) => setDraft({ ...draft, text: e.target.value })} className="w-full rounded-lg border border-border bg-background px-3 py-2" />
          <div className="flex gap-2">
            <button type="button" disabled={notify.isPending} onClick={() => notify.mutate({ text: draft.text, chat: draft.chat }, { onSuccess: (r) => r.sent && setDraft(null) })} className="rounded-lg bg-primary px-3 py-2 text-sm text-primary-foreground">
              {notify.data && !notify.data.sent ? "Повторить" : "Отправить"}
            </button>
            <button type="button" onClick={() => setDraft(null)} className="rounded-lg px-3 py-2 text-sm">
              Не отправлять
            </button>
          </div>
          {notify.data && !notify.data.sent && <p className="text-destructive">Клиент не уведомлён: {notify.data.error}</p>}
        </div>
      )}
    </div>
  );
}
```

Регистрация: в `GenericForm.tsx` — `import { OrderActions } from "./orders/OrderActions";` и `ACTIONS.orders = OrderActions;` рядом с объявлением `ACTIONS`. Форма заказа при этом read-only: у раздела `orders` в пресете нет `can_edit`.

- [ ] **Step 3: Переписки**

```tsx
// features/cabinet/chats/ChatsScreen.tsx
import { useState } from "react";

import { type ChatItem, useChatCommand, useChatList, useMessages } from "./api";

const AUTHOR = { client: "Клиент", bot: "Бот", staff: "Вы" } as const;

export function ChatsScreen() {
  const chats = useChatList();
  const [active, setActive] = useState<string | null>(null);
  const current = chats.data?.find((c) => c.chat === active) ?? null;

  return (
    <div className="flex h-[calc(100dvh-8rem)] gap-4">
      <ul className={`w-full divide-y divide-border overflow-y-auto rounded-2xl border border-border md:w-80 ${active ? "hidden md:block" : ""}`}>
        {chats.data?.map((c) => (
          <li key={c.chat}>
            <button type="button" onClick={() => setActive(c.chat)} className={`block w-full px-4 py-3 text-left ${c.chat === active ? "bg-accent" : ""}`}>
              <div className="flex items-center gap-2">
                <span className="flex-1 truncate font-medium">{c.title}</span>
                {c.paused && <span className="rounded bg-amber-100 px-1.5 text-xs text-amber-900">бот на паузе</span>}
              </div>
              <div className="truncate text-sm text-muted-foreground">{c.preview}</div>
            </button>
          </li>
        ))}
        {chats.data?.length === 0 && <li className="px-4 py-6 text-center text-muted-foreground">Переписок пока нет</li>}
      </ul>
      {current && <Thread chat={current} onBack={() => setActive(null)} />}
    </div>
  );
}

function Thread({ chat, onBack }: { chat: ChatItem; onBack: () => void }) {
  const messages = useMessages(chat.chat);
  const send = useChatCommand("send");
  const pause = useChatCommand("pause");
  const resume = useChatCommand("resume");
  const [text, setText] = useState("");

  return (
    <section className="flex min-w-0 flex-1 flex-col rounded-2xl border border-border">
      <header className="flex items-center gap-2 border-b border-border p-3">
        <button type="button" onClick={onBack} className="md:hidden">←</button>
        <div className="flex-1 font-medium">{chat.title}</div>
        {chat.paused ? (
          <button type="button" onClick={() => resume.mutate({ chat: chat.chat })} className="rounded-lg border border-border px-3 py-1.5 text-sm">
            Вернуть боту
          </button>
        ) : (
          <button type="button" onClick={() => pause.mutate({ chat: chat.chat })} className="rounded-lg bg-primary px-3 py-1.5 text-sm text-primary-foreground">
            Взять на себя
          </button>
        )}
      </header>
      <ol className="flex-1 space-y-2 overflow-y-auto p-3">
        {messages.data?.map((m) => (
          <li key={m.name} className={`max-w-[80%] rounded-2xl px-3 py-2 ${m.author === "client" ? "bg-muted" : "ml-auto bg-primary/10"}`}>
            <div className="text-xs text-muted-foreground">{AUTHOR[m.author]}</div>
            <div className="whitespace-pre-wrap">{m.text}</div>
          </li>
        ))}
      </ol>
      {chat.paused && (
        <form
          className="flex gap-2 border-t border-border p-3"
          onSubmit={(e) => {
            e.preventDefault();
            if (text.trim()) send.mutate({ chat: chat.chat, text }, { onSuccess: () => setText("") });
          }}
        >
          <input value={text} onChange={(e) => setText(e.target.value)} placeholder="Ответ клиенту" className="flex-1 rounded-lg border border-border bg-background px-3 py-2" />
          <button type="submit" disabled={send.isPending} className="rounded-lg bg-primary px-3 py-2 text-primary-foreground">
            Отправить
          </button>
        </form>
      )}
      {send.error && <p className="px-3 pb-3 text-destructive">{send.error.message}</p>}
    </section>
  );
}
```

`screens.tsx`: `import { ChatsScreen } from "./chats/ChatsScreen";` и `chats: ChatsScreen` в `SCREENS`.

- [ ] **Step 4: Проверка**

Run: `yarn typecheck && yarn build` — без ошибок.

Вручную на `dev.localhost`: написать боту в Telegram, пройти заказ до черновика → он появляется в «Заказах» без перезагрузки → «Принять» → текст сообщения → «Отправить» → сообщение пришло в Telegram. В «Переписках»: «Взять на себя», ответить, бот молчит; «Вернуть боту», бот снова отвечает.

- [ ] **Step 5: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ui && git add frontend && git commit -m "feat(cabinet): действия с заказом, уведомление клиента, переписки"
```

---

### Task 15: Фронт — главная, режим работы, профиль, Telegram

**Files:**
- Create: `habibi_ui/frontend/src/features/cabinet/home/HomeScreen.tsx`
- Create: `habibi_ui/frontend/src/features/cabinet/settings/HoursScreen.tsx`
- Create: `habibi_ui/frontend/src/features/cabinet/settings/ProfileScreen.tsx`
- Create: `habibi_ui/frontend/src/features/cabinet/settings/TelegramScreen.tsx`
- Create: `habibi_ui/frontend/src/features/cabinet/settings/api.ts`
- Modify: `habibi_ui/frontend/src/features/cabinet/screens.tsx`

**Interfaces:**
- Consumes: `habibi_ai.cabinet.settings.*` (задача 10), `useChatList` (задача 14), `useSectionList("orders", [])` (задача 13).
- Produces: `SCREENS.home`, `SCREENS.hours`, `SCREENS.profile`, `SCREENS.telegram`.

- [ ] **Step 1: API настроек**

```ts
// features/cabinet/settings/api.ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { call } from "../../../shared/api/client";

export type Slot = { weekday: string; kind: string; opens: string; closes: string };
export type Exception = { date: string; closed: 0 | 1; opens: string; closes: string; note: string };
export type Hours = { time_zone: string; schedule: Slot[]; exceptions: Exception[] };
export type Rule = { title: string; hint: string; text: string };
export type Profile = { business_name: string; business_kind: string; address: string; phone: string; description: string; tone: string; rules: Rule[] };
export type TelegramStatus = { connected: boolean; username: string | null; last_message_at: string | null };

function useResource<T>(key: string, getter: string, setter: string) {
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: ["cabinet", key], queryFn: () => call<T>(getter) });
  const mutation = useMutation({
    mutationFn: (args: Record<string, unknown>) => call<T>(setter, args),
    onSuccess: (data) => queryClient.setQueryData(["cabinet", key], data),
  });
  return { query, mutation };
}

export const useHours = () => useResource<Hours>("hours", "habibi_ai.cabinet.settings.get_hours", "habibi_ai.cabinet.settings.save_hours");
export const useProfile = () => useResource<Profile>("profile", "habibi_ai.cabinet.settings.get_profile", "habibi_ai.cabinet.settings.save_profile");
export const useTelegram = () => useResource<TelegramStatus>("telegram", "habibi_ai.cabinet.settings.telegram_status", "habibi_ai.cabinet.settings.connect_telegram");
```

- [ ] **Step 2: Экраны**

Режим работы:

```tsx
// features/cabinet/settings/HoursScreen.tsx
import { useEffect, useState } from "react";

import { type Exception, type Slot, useHours } from "./api";

// Значения weekday и kind — из опций Working Hours Slot (JSON доктайпа).
// Подставить фактические при реализации; ниже — порядок недели для отображения.
const WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
const DAY_LABEL: Record<string, string> = { Monday: "Пн", Tuesday: "Вт", Wednesday: "Ср", Thursday: "Чт", Friday: "Пт", Saturday: "Сб", Sunday: "Вс" };

export function HoursScreen() {
  const { query, mutation } = useHours();
  const [schedule, setSchedule] = useState<Slot[]>([]);
  const [exceptions, setExceptions] = useState<Exception[]>([]);

  useEffect(() => {
    if (query.data) {
      setSchedule(query.data.schedule);
      setExceptions(query.data.exceptions);
    }
  }, [query.data]);

  const kind = schedule[0]?.kind ?? "";
  const update = (i: number, patch: Partial<Slot>) => setSchedule((s) => s.map((row, j) => (j === i ? { ...row, ...patch } : row)));

  return (
    <section className="max-w-xl space-y-6">
      <h1 className="text-xl font-semibold">Режим работы</h1>
      {WEEKDAYS.map((day) => {
        const rows = schedule.map((r, i) => [r, i] as const).filter(([r]) => r.weekday === day);
        return (
          <div key={day} className="flex flex-wrap items-center gap-2">
            <span className="w-8 font-medium">{DAY_LABEL[day]}</span>
            {rows.length === 0 && <span className="text-muted-foreground">выходной</span>}
            {rows.map(([r, i]) => (
              <span key={i} className="flex items-center gap-1">
                <input type="time" value={r.opens.slice(0, 5)} onChange={(e) => update(i, { opens: `${e.target.value}:00` })} className="rounded border border-border bg-background px-2 py-1" />
                –
                <input type="time" value={r.closes.slice(0, 5)} onChange={(e) => update(i, { closes: `${e.target.value}:00` })} className="rounded border border-border bg-background px-2 py-1" />
                <button type="button" onClick={() => setSchedule((s) => s.filter((_, j) => j !== i))} aria-label="Убрать интервал">×</button>
              </span>
            ))}
            <button type="button" onClick={() => setSchedule((s) => [...s, { weekday: day, kind, opens: "10:00:00", closes: "22:00:00" }])} className="text-sm text-primary">
              + интервал
            </button>
          </div>
        );
      })}
      <h2 className="font-medium">Исключения</h2>
      {exceptions.map((ex, i) => (
        <div key={i} className="flex flex-wrap items-center gap-2">
          <input type="date" value={ex.date} onChange={(e) => setExceptions((s) => s.map((r, j) => (j === i ? { ...r, date: e.target.value } : r)))} className="rounded border border-border bg-background px-2 py-1" />
          <label className="flex items-center gap-1 text-sm">
            <input type="checkbox" checked={Boolean(ex.closed)} onChange={(e) => setExceptions((s) => s.map((r, j) => (j === i ? { ...r, closed: e.target.checked ? 1 : 0 } : r)))} />
            закрыто
          </label>
          <input value={ex.note} placeholder="причина" onChange={(e) => setExceptions((s) => s.map((r, j) => (j === i ? { ...r, note: e.target.value } : r)))} className="flex-1 rounded border border-border bg-background px-2 py-1" />
          <button type="button" onClick={() => setExceptions((s) => s.filter((_, j) => j !== i))}>×</button>
        </div>
      ))}
      <button type="button" onClick={() => setExceptions((s) => [...s, { date: "", closed: 1, opens: "", closes: "", note: "" }])} className="text-sm text-primary">
        + дата
      </button>
      {mutation.error && <p className="text-destructive">{mutation.error.message}</p>}
      <button type="button" disabled={mutation.isPending} onClick={() => mutation.mutate({ schedule, exceptions })} className="block rounded-lg bg-primary px-4 py-2 text-primary-foreground">
        Сохранить
      </button>
    </section>
  );
}
```

`kind` нового интервала берётся из существующей строки, а если строк нет — из первой опции `kind` в JSON доктайпа `Working Hours Slot`: при реализации заменить `schedule[0]?.kind ?? ""` на `schedule[0]?.kind ?? "<первая опция>"`.

Профиль:

```tsx
// features/cabinet/settings/ProfileScreen.tsx
import { useEffect, useState } from "react";

import { type Profile, useProfile } from "./api";

const CORE: [keyof Profile, string][] = [
  ["business_name", "Название"],
  ["business_kind", "Чем занимаетесь"],
  ["address", "Адрес"],
  ["phone", "Телефон для клиентов"],
];
const TONES = [
  ["friendly", "Дружелюбный"],
  ["neutral", "Нейтральный"],
  ["formal", "Официальный"],
];

export function ProfileScreen() {
  const { query, mutation } = useProfile();
  const [p, setP] = useState<Profile | null>(null);
  const [newTitle, setNewTitle] = useState("");
  useEffect(() => {
    if (query.data) setP(query.data);
  }, [query.data]);
  if (!p) return null;

  const input = "w-full rounded-lg border border-border bg-background px-3 py-2";
  return (
    <section className="max-w-xl space-y-4">
      <h1 className="text-xl font-semibold">О компании</h1>
      <p className="text-sm text-muted-foreground">Это знает ваш бот. Пишите так, как ответили бы клиенту сами.</p>
      {CORE.map(([key, label]) => (
        <label key={key} className="block space-y-1">
          <span className="text-sm text-muted-foreground">{label}</span>
          <input className={input} value={String(p[key] ?? "")} onChange={(e) => setP({ ...p, [key]: e.target.value })} />
        </label>
      ))}
      <label className="block space-y-1">
        <span className="text-sm text-muted-foreground">Коротко о вас</span>
        <textarea rows={3} className={input} value={p.description} onChange={(e) => setP({ ...p, description: e.target.value })} />
      </label>
      <label className="block space-y-1">
        <span className="text-sm text-muted-foreground">Как общаться с клиентами</span>
        <select className={input} value={p.tone} onChange={(e) => setP({ ...p, tone: e.target.value })}>
          {TONES.map(([v, l]) => (
            <option key={v} value={v}>{l}</option>
          ))}
        </select>
      </label>
      {p.rules.map((r, i) => (
        <label key={i} className="block space-y-1">
          <span className="font-medium">{r.title}</span>
          <textarea rows={3} placeholder={r.hint} className={input} value={r.text} onChange={(e) => setP({ ...p, rules: p.rules.map((x, j) => (j === i ? { ...x, text: e.target.value } : x)) })} />
        </label>
      ))}
      <div className="flex gap-2">
        <input value={newTitle} onChange={(e) => setNewTitle(e.target.value)} placeholder="Свой блок, например «Парковка»" className={input} />
        <button
          type="button"
          disabled={!newTitle.trim()}
          onClick={() => {
            setP({ ...p, rules: [...p.rules, { title: newTitle.trim(), hint: "", text: "" }] });
            setNewTitle("");
          }}
          className="rounded-lg border border-border px-3 text-sm"
        >
          Добавить
        </button>
      </div>
      {mutation.error && <p className="text-destructive">{mutation.error.message}</p>}
      <button type="button" disabled={mutation.isPending} onClick={() => mutation.mutate({ values: p })} className="block rounded-lg bg-primary px-4 py-2 text-primary-foreground">
        Сохранить
      </button>
    </section>
  );
}
```

Telegram:

```tsx
// features/cabinet/settings/TelegramScreen.tsx
import { useState } from "react";

import { useTelegram } from "./api";

export function TelegramScreen() {
  const { query, mutation } = useTelegram();
  const [token, setToken] = useState("");
  const status = query.data;

  return (
    <section className="max-w-xl space-y-4">
      <h1 className="text-xl font-semibold">Telegram</h1>
      {status?.connected ? (
        <div className="rounded-2xl border border-border p-4">
          <div className="font-medium">@{status.username} подключён</div>
          <div className="text-sm text-muted-foreground">
            {status.last_message_at ? `Последнее сообщение: ${new Date(status.last_message_at).toLocaleString("ru-RU")}` : "Сообщений пока не было"}
          </div>
        </div>
      ) : (
        <ol className="list-decimal space-y-2 pl-5 text-sm">
          <li>Откройте @BotFather в Telegram и отправьте /newbot.</li>
          <li>Придумайте имя и адрес бота — BotFather пришлёт токен.</li>
          <li>Вставьте токен ниже и нажмите «Подключить».</li>
        </ol>
      )}
      <form
        className="flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          mutation.mutate({ token }, { onSuccess: () => setToken("") });
        }}
      >
        <input value={token} onChange={(e) => setToken(e.target.value)} placeholder="123456:ABC..." className="flex-1 rounded-lg border border-border bg-background px-3 py-2" />
        <button type="submit" disabled={!token.trim() || mutation.isPending} className="rounded-lg bg-primary px-3 py-2 text-primary-foreground">
          {status?.connected ? "Сменить" : "Подключить"}
        </button>
      </form>
      {mutation.error && <p className="text-destructive">{mutation.error.message}</p>}
    </section>
  );
}
```

Главная:

```tsx
// features/cabinet/home/HomeScreen.tsx
import { Link } from "react-router-dom";

import { useSectionList } from "../api";
import { useChatList } from "../chats/api";
import { useTelegram } from "../settings/api";

export function HomeScreen() {
  const orders = useSectionList("orders", [["docstatus", "=", 0]]);
  const chats = useChatList();
  const telegram = useTelegram().query.data;
  const today = new Date().toISOString().slice(0, 10);
  const todayChats = chats.data?.filter((c) => c.last_at.startsWith(today)) ?? [];
  const paused = chats.data?.filter((c) => c.paused) ?? [];

  return (
    <section className="space-y-4">
      {telegram && !telegram.connected && (
        <Link to="/c/telegram" className="block rounded-2xl border border-amber-300 bg-amber-50 p-4 text-amber-900">
          Подключите Telegram — без него бот не получит сообщений клиентов.
        </Link>
      )}
      <div className="grid gap-3 sm:grid-cols-3">
        <Card to="/c/orders" label="Новые заказы" value={orders.data?.rows.length} />
        <Card to="/c/chats" label="Переписки сегодня" value={todayChats.length} />
        <Card to="/c/chats" label="Ждут человека" value={paused.length} />
      </div>
    </section>
  );
}

function Card({ to, label, value }: { to: string; label: string; value: number | undefined }) {
  return (
    <Link to={to} className="rounded-2xl border border-border p-4">
      <div className="text-sm text-muted-foreground">{label}</div>
      <div className="text-3xl font-semibold">{value ?? "—"}</div>
    </Link>
  );
}
```

`docstatus` есть в `list_fields` раздела `orders` в `food.json` (задача 12) — без этого `merge_filters` отбросил бы фильтр карточки «Новые заказы» молча.

Лента последних событий из спеки (раздел 6, «Главная») — это те же данные: последние 5 переписок по `last_at` списком под карточками. Добавить под сеткой:

```tsx
      <ul className="divide-y divide-border rounded-2xl border border-border">
        {chats.data?.slice(0, 5).map((c) => (
          <li key={c.chat} className="px-4 py-3">
            <div className="font-medium">{c.title}</div>
            <div className="truncate text-sm text-muted-foreground">{c.preview}</div>
          </li>
        ))}
      </ul>
```

`screens.tsx`:

```tsx
import { ChatsScreen } from "./chats/ChatsScreen";
import { HomeScreen } from "./home/HomeScreen";
import { HoursScreen } from "./settings/HoursScreen";
import { ProfileScreen } from "./settings/ProfileScreen";
import { TelegramScreen } from "./settings/TelegramScreen";

export const SCREENS: Record<string, ComponentType<{ section: CabinetSection }>> = {
  home: HomeScreen,
  chats: ChatsScreen,
  hours: HoursScreen,
  profile: ProfileScreen,
  telegram: TelegramScreen,
};
```

- [ ] **Step 3: Проверка**

Run: `yarn typecheck && yarn build` — без ошибок.

Вручную: главная показывает плашку, пока Telegram не подключён; режим работы сохраняется, и бот на вопрос «до скольки работаете» отвечает новым временем; профиль сохраняется, и бот на «где вы находитесь» называет адрес из профиля (движок с задачей 1 должен быть запущен локально или выкачен).

- [ ] **Step 4: Коммит**

```bash
cd /Users/fsa/Projects/habibi/habibi_ui && git add frontend && git commit -m "feat(cabinet): главная, режим работы, о компании, подключение Telegram"
```

---

### Task 16: Сквозная проверка, документация, мерж

**Files:**
- Modify: `habibi_docker/habibi/specs/2026-09-23-client-cabinet-design.md` — отклонения 1–3 из шапки плана
- Modify: `habibi_docker/habibi/docs/` — раздел о кабинете и `apply-preset` рядом с документацией агента (файл, где описан `habibi_ai`: `agent-core.md`)

- [ ] **Step 1: Все тесты**

```bash
$DC exec -T frappe bash -lc "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --app habibi_ui && bench --site dev.localhost run-tests --app habibi_ai"
$DC exec -T frappe bash -lc "cd /workspace/repos/habibi_ui && yarn typecheck && yarn build"
cd /Users/fsa/Projects/habibi/habibi_ai_engine/extensions/ai && npm test
```

Expected: всё зелёное. Вывод приложить к отчёту.

- [ ] **Step 2: Сквозной сценарий на `dev.localhost`**

1. `bench --site dev.localhost habibi-ai apply-preset food`.
2. Создать пользователя с ролью `Habibi Owner`, войти — открывается `/ui/c`.
3. «О компании»: название, адрес, блок «Доставка». «Режим работы»: неделя.
4. «Меню»: добавить позицию с ценой.
5. «Telegram»: подключить тестового бота.
6. Написать боту: спросить адрес (ответ из профиля), заказать позицию, согласиться.
7. Заказ появляется в «Заказах» без перезагрузки → «Принять» → отправить сообщение → оно пришло в Telegram.
8. «Переписки»: «Взять на себя», ответить, «Вернуть боту».
9. Пользователь с ролью `Habibi Staff`: не видит меню, режим работы, профиль, Telegram.
10. Ширина 375px: таб-бар, «Ещё», все экраны без горизонтального скролла.

Любое расхождение — баг в соответствующей задаче, чинить там, с тестом.

- [ ] **Step 3: Спека и документация**

В спеке: раздел 4.4 — флаги полями `Check`; раздел 5 — «профиль уходит в движок полем `tenant_context`»; разделы 6.1–6.4 — методы в `habibi_ai.cabinet.*`, а не в `habibi_ui.api.v1.*`, с причиной (направление зависимости). В документацию — как включить кабинет клиенту: `apply-preset`, роль `Habibi Owner`, движок не ниже коммита задачи 1.

```bash
cd /Users/fsa/Projects/habibi/habibi_docker && git add habibi && git commit -m "docs(spec): кабинет клиента — отклонения реализации и включение кабинета"
```

- [ ] **Step 4: Завершение веток**

Использовать superpowers:finishing-a-development-branch для `habibi_ui`, `habibi_ai`, `habibi_ai_engine`. Порядок мержа: `habibi_ai_engine` (обратно совместим) → `habibi_ui` → `habibi_ai` (зависит от хуков и `Cabinet Settings` из `habibi_ui`). Выкатка на прод — отдельное решение пользователя: `git tag` в `habibi_docker` по `CLAUDE.md`, после выкатки на `erp.habibi-erp.com` — `apply-preset food`.
