# Кабинет кухни и курьера — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать роли «кухня» и «курьер» собственные мобильные экраны в кабинете `/ui/c`: очередь `In Kitchen` с кнопкой «Готово» и две вкладки курьера («Мои», «Свободные») с «Взять» и «Доставлено».

**Architecture:** Расширяем существующий кабинет, а не строим новый. `habibi_ui` получает две роли и правило видимости разделов; `habibi_ai` — модуль `cabinet/fulfilment.py` (чтение очередей, «Взять») и realtime-событие `fulfilment`; переходы «Готово»/«Доставлено» идут через уже существующий `orders.apply`. Два новых экрана регистрируются в реестре `screens.tsx` и ставятся пресетом «общепит».

**Tech Stack:** Frappe v16 / ERPNext (Python, `IntegrationTestCase`), React 19 + TanStack Query + Tailwind v4 + shadcn/base-ui, socket.io.

**Spec:** `habibi/specs/2026-10-01-kitchen-courier-design.md` (в этом репозитории). Макеты: `.superpowers/brainstorm/44519-1790843719/content/kitchen-courier-screens.html` (локально).

## Три репозитория

Код лежит в соседних checkout'ах, у каждого свой git и свой `main`. Коммиты делаются в том репозитории, где лежат файлы задачи:

| Репо | Путь | Задачи |
|---|---|---|
| `habibi_ui` | `/Users/fsa/Projects/habibi/habibi_ui` | 1, 6, 7, 8 |
| `habibi_ai` | `/Users/fsa/Projects/habibi/habibi_ai` | 2, 3, 4, 5 |
| `habibi_docker` | `/Users/fsa/Projects/habibi/habibi_docker` | спека, план, релиз |

Порядок задач важен: Задача 1 (роли) должна быть выкачена на dev до Задачи 5 (пресет выдаёт права ролям, которых иначе нет).

## Как запускать тесты

Только в контейнере `devcontainer-frappe-1` (host python 3.9, проект 3.14).

- Без frappe (чистые модули `*_rules.py`):
  `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/repos/habibi_ai && python3 -m unittest habibi_ai.tests.<модуль> -v'`
- С frappe:
  `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --test-category all --module <пакет>.tests.<модуль>'`
  Без `--test-category all` `IntegrationTestCase`-классы могут молча пропускаться.
- Новые роли из фикстуры появляются на сайте после
  `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && bench --site dev.localhost migrate'`.
- Фронт (на хосте): `cd /Users/fsa/Projects/habibi/habibi_ui && yarn typecheck`.
- `ruff` на baseline не чист (~1000 замечаний): смотреть только свои строки.
- Скобки в командах `docker exec ... bash -lc '...'`: если в команде нужны одинарные кавычки, используйте двойные снаружи.

## Global Constraints

Из спеки, дословно:

- Роли кабинета: `Habibi Kitchen` и `Habibi Courier`. Роли воркфлоу `Burger Kitchen`, `Burger Courier` остаются как есть.
- Пустое `roles` у раздела означает «только `Habibi Owner` и `Habibi Staff`».
- `habibi_ui` не вправе импортировать `habibi_ai`; серверные методы кухни и курьера лежат в `habibi_ai/cabinet/fulfilment.py`.
- Кухня видит заказы в состоянии `In Kitchen` (все, не только от бота): номер, возраст, позиции с количеством, заметку. **Без цен, телефона, адреса и имени клиента.**
- Курьер, «Мои»: заказы `Out for Delivery` со своим `custom_courier`: клиент, телефон, адрес, зона, состав **без цен**.
- Курьер, «Свободные»: заказы `Ready`, доставка (`custom_fulfilment_type = Delivery`), `custom_courier` пуст: номер, возраст, клиент, адрес, зона, число позиций. **Без телефона.** Самовывоз не показывается.
- «Готово» = переход `Mark Ready`, «Доставлено» = `Mark Delivered`, через `habibi_ai.cabinet.orders.apply`. «Взять» = назначение `custom_courier` и переход `Dispatch`.
- Возраст заказа — от `modified`.
- `courier_take` блокирует строку заказа (`for update`); при гонке и при неверном состоянии отвечает «уже взят», а не ошибкой.
- Курьер сопоставляется с `Employee` по `Employee.user_id`; нет записи — «Вам не назначен профиль курьера».
- Realtime: событие `topic: "fulfilment"` на любое изменение Sales Order (без фильтра по `AI Order Quote`), получатели `Habibi Kitchen` и `Habibi Courier`; событие `orders` не меняется. Экран перечитывается раз в 30 секунд и при возврате на вкладку.
- Звук — кнопкой в шапке кухни, по умолчанию выключен, выбор в `localStorage`.
- Вне объёма: печать тикетов, наличные при получении, «Взял в работу», трекинг на карте, закрытие REST-доступа к Sales Order, правки экранов владельца.

## Review Focus

Входы, которые спека подразумевает, но явных задач под них нет; каждый закреплён тестом в задаче-владельце:

1. **Сайт без воркфлоу Sales Order или без `custom_courier`/`custom_fulfilment_type`** → пустые списки, а не 500 (Задача 3, `test_без_воркфлоу_очереди_пусты`).
2. **Курьер без `Employee`** → понятная ошибка в «Мои» и «Взять», «Свободные» при этом работают (Задача 3).
3. **Пустой или HTML-адрес** → строка адреса чистая, при пустом — `None`, на экране «Адрес не указан» (Задача 2 и 8).
4. **Заказ только из строки доставки** (`SRV-DELIVERY`) → у кухни пустой состав, строка доставки не показывается как еда (Задача 2).
5. **Часы сервера и `modified` в будущем** → возраст 0, а не отрицательное число (Задача 2).
6. **Нет телефона у клиента** → кнопка «Позвонить» скрыта, а не ведёт на `tel:` (Задача 8).

---

### Task 1: Роли `Habibi Kitchen` и `Habibi Courier` и правило видимости (habibi_ui)

**Files:**
- Modify: `habibi_ui/habibi_ui/api/v1/cabinet.py` (константы ролей, `_visible`)
- Modify: `habibi_ui/habibi_ui/hooks.py` (fixtures, `role_home_page`)
- Modify: `habibi_ui/habibi_ui/fixtures/role.json`
- Test: `habibi_ui/habibi_ui/tests/test_floor_roles.py` (новый)

**Interfaces:**
- Produces: `habibi_ui.api.v1.cabinet.STAFF_ROLES = ("Habibi Owner", "Habibi Staff")`, `FLOOR_ROLES = ("Habibi Kitchen", "Habibi Courier")`, `CABINET_ROLES = STAFF_ROLES + FLOOR_ROLES`. `access.cabinet_only` и `access.has_app_permission` продолжают использовать `CABINET_ROLES`, поэтому новые роли автоматически получают вход в кабинет и закрытый Desk.

- [ ] **Step 1: Write the failing test**

Создать `habibi_ui/habibi_ui/tests/test_floor_roles.py`:

```python
"""Роли кухни и курьера: вход в кабинет и видимость разделов."""

import frappe
from frappe.tests import IntegrationTestCase

from habibi_ui.api.v1.cabinet import CABINET_ROLES, FLOOR_ROLES, STAFF_ROLES, _visible
from habibi_ui.cabinet import access


class TestFloorRoles(IntegrationTestCase):
	def test_роли_кухни_и_курьера_входят_в_кабинет(self):
		self.assertEqual(FLOOR_ROLES, ("Habibi Kitchen", "Habibi Courier"))
		self.assertEqual(CABINET_ROLES, STAFF_ROLES + FLOOR_ROLES)

	def test_кухня_и_курьер_только_кабинет(self):
		for role in FLOOR_ROLES:
			with self.subTest(role):
				self.assertTrue(access.cabinet_only([role]))
		# System Manager решает сам, как и у владельца
		self.assertFalse(access.cabinet_only(["Habibi Courier", "System Manager"]))

	def test_пустые_roles_не_показывают_раздел_кухне_и_курьеру(self):
		row = frappe._dict(feature="", roles="")
		for role in FLOOR_ROLES:
			with self.subTest(role):
				self.assertFalse(_visible(row, {role}, set()))
		for role in STAFF_ROLES:
			with self.subTest(role):
				self.assertTrue(_visible(row, {role}, set()))
		self.assertTrue(_visible(row, {"System Manager"}, set()))

	def test_явная_роль_показывает_раздел_кухне(self):
		row = frappe._dict(feature="", roles="Habibi Kitchen")
		self.assertTrue(_visible(row, {"Habibi Kitchen"}, set()))
		self.assertFalse(_visible(row, {"Habibi Courier"}, set()))
		self.assertFalse(_visible(row, {"Habibi Staff"}, set()))

	def test_роли_приезжают_фикстурой_и_ведут_в_кабинет(self):
		hooks = frappe.get_hooks("role_home_page")
		self.assertEqual(hooks.get("Habibi Kitchen"), ["ui"])
		self.assertEqual(hooks.get("Habibi Courier"), ["ui"])
		fixture = next(f for f in frappe.get_hooks("fixtures") if f.get("dt") == "Role")
		names = fixture["filters"][0][2]
		self.assertIn("Habibi Kitchen", names)
		self.assertIn("Habibi Courier", names)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --test-category all --module habibi_ui.tests.test_floor_roles'`
Expected: FAIL (`ImportError: cannot import name 'FLOOR_ROLES'`).

- [ ] **Step 3: Write minimal implementation**

В `habibi_ui/habibi_ui/api/v1/cabinet.py` заменить строку `CABINET_ROLES = ("Habibi Owner", "Habibi Staff")`:

```python
STAFF_ROLES = ("Habibi Owner", "Habibi Staff")
FLOOR_ROLES = ("Habibi Kitchen", "Habibi Courier")
CABINET_ROLES = STAFF_ROLES + FLOOR_ROLES
```

и последнюю строку `_visible`:

```python
def _visible(row, roles, features):
	if row.feature and row.feature not in features:
		return False
	wanted = {r.strip() for r in (row.roles or "").splitlines() if r.strip()}
	if wanted:
		return bool(wanted & roles) or "System Manager" in roles
	# Пустое roles — владелец и сотрудник, но не кухня и курьер: у тех
	# разделы заводятся явно, иначе они увидели бы заказы, чаты и клиентов.
	return bool(set(STAFF_ROLES) & roles) or "System Manager" in roles
```

В `habibi_ui/habibi_ui/hooks.py`:

```python
fixtures = [
	{
		"dt": "Role",
		"filters": [
			["name", "in", ["Habibi UI", "Habibi Owner", "Habibi Staff", "Habibi Kitchen", "Habibi Courier"]]
		],
	},
]

role_home_page = {
	"Habibi UI": "ui",
	"Habibi Owner": "ui",
	"Habibi Staff": "ui",
	"Habibi Kitchen": "ui",
	"Habibi Courier": "ui",
}
```

(Комментарий над `fixtures` дополнить: «Habibi Kitchen и Habibi Courier — роли смены, у них свои разделы в кабинете».)

В `habibi_ui/habibi_ui/fixtures/role.json` добавить два объекта в конец массива:

```json
 {
  "doctype": "Role",
  "name": "Habibi Kitchen",
  "role_name": "Habibi Kitchen",
  "desk_access": 1,
  "is_custom": 1,
  "disabled": 0,
  "home_page": "ui"
 },
 {
  "doctype": "Role",
  "name": "Habibi Courier",
  "role_name": "Habibi Courier",
  "desk_access": 1,
  "is_custom": 1,
  "disabled": 0,
  "home_page": "ui"
 }
```

(Не забыть запятую после предыдущего `}`.)

- [ ] **Step 4: Run test to verify it passes, then migrate and run neighbours**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && bench --site dev.localhost migrate && bench --site dev.localhost run-tests --test-category all --module habibi_ui.tests.test_floor_roles && bench --site dev.localhost run-tests --test-category all --module habibi_ui.tests.test_access && bench --site dev.localhost run-tests --test-category all --module habibi_ui.tests.test_cabinet_api && bench --site dev.localhost run-tests --test-category all --module habibi_ui.tests.test_session'`
Expected: PASS во всех четырёх (старые тесты видимости не ломаются: у них раздел без `roles` проверяется под `Habibi Staff`/System Manager).

- [ ] **Step 5: Commit (habibi_ui)**

```bash
cd /Users/fsa/Projects/habibi/habibi_ui
git add habibi_ui/api/v1/cabinet.py habibi_ui/hooks.py habibi_ui/fixtures/role.json habibi_ui/tests/test_floor_roles.py
git commit -m "feat(cabinet): роли кухни и курьера; пустое roles — только владелец и сотрудник

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Чистые правила карточек (habibi_ai, без frappe)

**Files:**
- Create: `habibi_ai/habibi_ai/fulfilment_rules.py`
- Test: `habibi_ai/habibi_ai/tests/test_fulfilment_rules.py`

**Interfaces:**
- Consumes: `habibi_ai.order_rules.DELIVERY_ITEM` (`"SRV-DELIVERY"`).
- Produces (все чистые, без frappe):
  - `age_minutes(modified: datetime, now: datetime) -> int` (не меньше 0)
  - `plain_address(html: str | None) -> str | None`
  - `lines(rows: list[dict]) -> list[{"item_name": str, "qty": float}]` (без строки доставки; строки несут `item_code`, `item_name`, `qty`)
  - `kitchen_card(order: dict, rows: list[dict], now: datetime) -> {"name", "age", "notes", "items"}`
  - `courier_card(order: dict, rows: list[dict], now: datetime, own: bool) -> {"name", "age", "customer_name", "address", "zone", "items_count"}` плюс `"phone"` и `"items"`, **только если** `own=True`.
  - `order` — словарь с ключами `name`, `modified`, `customer_name`, `shipping_address`, `address_display`, `contact_mobile`, `custom_kitchen_notes`, `custom_delivery_zone`, `custom_whatsapp_number` (отсутствующие ключи допустимы).

- [ ] **Step 1: Write the failing test**

Создать `habibi_ai/habibi_ai/tests/test_fulfilment_rules.py`:

```python
import unittest
from datetime import datetime

from habibi_ai import fulfilment_rules as r

NOW = datetime(2026, 10, 1, 12, 30)
ORDER = {
	"name": "SAL-ORD-2026-00015",
	"modified": datetime(2026, 10, 1, 12, 18),
	"customer_name": "Динара",
	"shipping_address": None,
	"address_display": "мкр. Самал-2, д. 33<br>кв. 41<br>",
	"contact_mobile": "+77010001122",
	"custom_kitchen_notes": "  аллергия на кунжут ",
	"custom_delivery_zone": "Центр",
	"custom_whatsapp_number": "+77019990011",
}
ROWS = [
	{"item_code": "BURGER", "item_name": "Чизбургер", "qty": 2.0},
	{"item_code": "SRV-DELIVERY", "item_name": "Доставка", "qty": 1.0},
	{"item_code": "COLA", "item_name": "Кола", "qty": 1.0},
]


class TestAge(unittest.TestCase):
	def test_минуты(self):
		self.assertEqual(r.age_minutes(ORDER["modified"], NOW), 12)

	def test_меньше_минуты_это_ноль(self):
		self.assertEqual(r.age_minutes(datetime(2026, 10, 1, 12, 29, 30), NOW), 0)

	def test_modified_в_будущем_не_уходит_в_минус(self):
		# Часы сервера БД и приложения могут расходиться
		self.assertEqual(r.age_minutes(datetime(2026, 10, 1, 12, 45), NOW), 0)


class TestAddress(unittest.TestCase):
	def test_html_в_строку(self):
		self.assertEqual(r.plain_address("мкр. Самал-2, д. 33<br>кв. 41<br>"), "мкр. Самал-2, д. 33, кв. 41")

	def test_переводы_строк(self):
		self.assertEqual(r.plain_address("ул. Абая, 12\nАлматы\n"), "ул. Абая, 12, Алматы")

	def test_пусто_это_none(self):
		for value in (None, "", "  <br> ", "\n"):
			with self.subTest(value):
				self.assertIsNone(r.plain_address(value))


class TestLines(unittest.TestCase):
	def test_доставка_не_еда(self):
		self.assertEqual(
			r.lines(ROWS),
			[{"item_name": "Чизбургер", "qty": 2.0}, {"item_name": "Кола", "qty": 1.0}],
		)

	def test_только_доставка_даёт_пустой_состав(self):
		self.assertEqual(r.lines([ROWS[1]]), [])


class TestKitchenCard(unittest.TestCase):
	def test_карточка(self):
		card = r.kitchen_card(ORDER, ROWS, NOW)
		self.assertEqual(
			card,
			{
				"name": "SAL-ORD-2026-00015",
				"age": 12,
				"notes": "аллергия на кунжут",
				"items": [{"item_name": "Чизбургер", "qty": 2.0}, {"item_name": "Кола", "qty": 1.0}],
			},
		)

	def test_кухне_не_уходит_лишнее(self):
		card = r.kitchen_card(ORDER, ROWS, NOW)
		for forbidden in ("phone", "address", "customer_name", "zone", "total", "rate", "amount"):
			self.assertNotIn(forbidden, card)
		for item in card["items"]:
			self.assertEqual(set(item), {"item_name", "qty"})

	def test_пустая_заметка_это_none(self):
		order = {**ORDER, "custom_kitchen_notes": "   "}
		self.assertIsNone(r.kitchen_card(order, ROWS, NOW)["notes"])
		order = {k: v for k, v in ORDER.items() if k != "custom_kitchen_notes"}
		self.assertIsNone(r.kitchen_card(order, ROWS, NOW)["notes"])


class TestCourierCard(unittest.TestCase):
	def test_чужой_заказ_без_телефона_и_состава(self):
		card = r.courier_card(ORDER, ROWS, NOW, own=False)
		self.assertEqual(
			card,
			{
				"name": "SAL-ORD-2026-00015",
				"age": 12,
				"customer_name": "Динара",
				"address": "мкр. Самал-2, д. 33, кв. 41",
				"zone": "Центр",
				"items_count": 2,
			},
		)

	def test_свой_заказ_с_телефоном_и_составом(self):
		card = r.courier_card(ORDER, ROWS, NOW, own=True)
		self.assertEqual(card["phone"], "+77019990011")
		self.assertEqual([i["item_name"] for i in card["items"]], ["Чизбургер", "Кола"])

	def test_телефон_запасной_и_отсутствующий(self):
		order = {**ORDER, "custom_whatsapp_number": None}
		self.assertEqual(r.courier_card(order, ROWS, NOW, own=True)["phone"], "+77010001122")
		order = {**order, "contact_mobile": None}
		self.assertIsNone(r.courier_card(order, ROWS, NOW, own=True)["phone"])

	def test_адрес_из_ссылки_если_текста_нет(self):
		order = {**ORDER, "address_display": None, "shipping_address": "Динара-Доставка"}
		self.assertEqual(r.courier_card(order, ROWS, NOW, own=False)["address"], "Динара-Доставка")

	def test_адреса_нет(self):
		order = {**ORDER, "address_display": None, "shipping_address": None}
		self.assertIsNone(r.courier_card(order, ROWS, NOW, own=False)["address"])

	def test_деньги_не_уходят_никогда(self):
		for own in (True, False):
			card = r.courier_card(ORDER, ROWS, NOW, own=own)
			for forbidden in ("total", "rate", "amount", "grand_total"):
				self.assertNotIn(forbidden, card)


if __name__ == "__main__":
	unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/repos/habibi_ai && python3 -m unittest habibi_ai.tests.test_fulfilment_rules -v'`
Expected: FAIL (`ImportError: cannot import name 'fulfilment_rules'`).

- [ ] **Step 3: Write minimal implementation**

Создать `habibi_ai/habibi_ai/fulfilment_rules.py`:

```python
"""Карточки кухни и курьера, не зависящие от frappe.

Решают, что именно уходит на экран: кухне — состав и заметка, курьеру — адрес
и состав, телефон клиента — только тому, чей заказ. Цен нет нигде: поля
режутся здесь, чтобы лишнее не попало на экран, даже если запрос завтра
вытащит больше. ERP-связка — в cabinet/fulfilment.py.
"""

import re

from habibi_ai.order_rules import DELIVERY_ITEM


def age_minutes(modified, now):
	# Часы БД и приложения могут расходиться: не показываем «−3 мин»
	return max(0, int((now - modified).total_seconds() // 60))


def _text(value):
	value = (value or "").strip()
	return value or None


def plain_address(html):
	"""Адрес Frappe хранит HTML («улица<br>город<br>»): курьеру нужна строка."""
	text = re.sub(r"<br\s*/?>|\n", ",", html or "", flags=re.IGNORECASE)
	text = re.sub(r"<[^>]+>", "", text)
	return ", ".join(part.strip() for part in text.split(",") if part.strip()) or None


def lines(rows):
	"""Состав без строки доставки: она не еда, кухня и курьер её не готовят и не несут."""
	return [{"item_name": r["item_name"], "qty": r["qty"]} for r in rows if r["item_code"] != DELIVERY_ITEM]


def kitchen_card(order, rows, now):
	return {
		"name": order["name"],
		"age": age_minutes(order["modified"], now),
		"notes": _text(order.get("custom_kitchen_notes")),
		"items": lines(rows),
	}


def _address(order):
	return plain_address(order.get("address_display")) or _text(order.get("shipping_address"))


def courier_card(order, rows, now, own):
	"""own — заказ уже у этого курьера: только тогда телефон и состав."""
	items = lines(rows)
	card = {
		"name": order["name"],
		"age": age_minutes(order["modified"], now),
		"customer_name": _text(order.get("customer_name")),
		"address": _address(order),
		"zone": _text(order.get("custom_delivery_zone")),
		"items_count": len(items),
	}
	if own:
		card["phone"] = _text(order.get("custom_whatsapp_number")) or _text(order.get("contact_mobile"))
		card["items"] = items
	return card
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/repos/habibi_ai && python3 -m unittest habibi_ai.tests.test_fulfilment_rules -v'`
Expected: PASS (все тесты зелёные).

- [ ] **Step 5: Commit (habibi_ai)**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai
git add habibi_ai/fulfilment_rules.py habibi_ai/tests/test_fulfilment_rules.py
git commit -m "feat(cabinet): правила карточек кухни и курьера без frappe

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Серверные методы кухни и курьера (habibi_ai)

**Files:**
- Create: `habibi_ai/habibi_ai/cabinet/fulfilment.py`
- Test: `habibi_ai/habibi_ai/tests/test_cabinet_fulfilment.py`

**Interfaces:**
- Consumes: `habibi_ai.fulfilment_rules.kitchen_card/courier_card` (Задача 2); `habibi_ai.cabinet.orders._state_field(workflow)`.
- Produces (whitelisted, вызываются фронтом как `habibi_ai.cabinet.fulfilment.<имя>`):
  - `kitchen_queue() -> list[KitchenCard]`
  - `courier_mine() -> list[CourierCard]` (с `phone`, `items`)
  - `courier_free() -> list[CourierCard]` (без `phone`, `items`)
  - `courier_take(name: str) -> {"taken": bool}` (POST; `taken: True` — заказ уже не доступен, ничего не изменено)
  - внутренние точки подмены в тестах: `_state_field()`, `_has(fieldname)`, `_my_employee()`, `_orders(state, *, courier=None, unassigned=False, delivery_only=False)`, `_items(names)`, `now_datetime`, `apply_workflow`.

- [ ] **Step 1: Write the failing test**

Создать `habibi_ai/habibi_ai/tests/test_cabinet_fulfilment.py`:

```python
"""Очереди кухни и курьера: кто что вызывает и что получает.

Данные подменены: на dev-сайте нет прод-воркфлоу и custom-полей заказа, а
проверяются права, срез полей и логика «Взять» — не ERP.
"""

from datetime import datetime
from unittest.mock import MagicMock, patch

import frappe
from frappe.tests import IntegrationTestCase

from habibi_ai.cabinet import fulfilment

ORDER = frappe._dict(
	name="SAL-ORD-2026-00015",
	modified=datetime(2026, 10, 1, 12, 18),
	customer_name="Динара",
	shipping_address=None,
	address_display="ул. Абая, 12<br>Алматы",
	contact_mobile="+77010001122",
	custom_kitchen_notes="без кунжута",
	custom_delivery_zone="Центр",
	custom_whatsapp_number="+77019990011",
)
ITEMS = {
	ORDER.name: [
		frappe._dict(item_code="BURGER", item_name="Бургер", qty=2.0),
		frappe._dict(item_code="SRV-DELIVERY", item_name="Доставка", qty=1.0),
	]
}
NOW = datetime(2026, 10, 1, 12, 30)


def _as(*roles):
	return patch("frappe.get_roles", return_value=list(roles))


class TestFulfilmentApi(IntegrationTestCase):
	def setUp(self):
		for target, kwargs in (
			("habibi_ai.cabinet.fulfilment._orders", {"return_value": [ORDER]}),
			("habibi_ai.cabinet.fulfilment._items", {"return_value": ITEMS}),
			("habibi_ai.cabinet.fulfilment.now_datetime", {"return_value": NOW}),
		):
			patcher = patch(target, **kwargs)
			setattr(self, target.rsplit(".", 1)[1].strip("_") + "_mock", patcher.start())
			self.addCleanup(patcher.stop)

	def test_кухня_получает_очередь_без_лишнего(self):
		with _as("Habibi Kitchen"):
			(card,) = fulfilment.kitchen_queue()
		self.assertEqual(card["age"], 12)
		self.assertEqual(card["notes"], "без кунжута")
		self.assertEqual(card["items"], [{"item_name": "Бургер", "qty": 2.0}])
		for forbidden in ("phone", "address", "customer_name", "zone"):
			self.assertNotIn(forbidden, card)
		self.orders_mock.assert_called_once_with(fulfilment.IN_KITCHEN)

	def test_курьер_не_вызывает_кухню_и_наоборот(self):
		with _as("Habibi Courier"), self.assertRaises(frappe.PermissionError):
			fulfilment.kitchen_queue()
		for method in (fulfilment.courier_mine, fulfilment.courier_free):
			with _as("Habibi Kitchen"), self.assertRaises(frappe.PermissionError):
				method()
		with _as("Habibi Kitchen"), self.assertRaises(frappe.PermissionError):
			fulfilment.courier_take("SAL-ORD-2026-00015")

	def test_владелец_с_system_manager_проходит(self):
		with _as("System Manager"):
			self.assertEqual(len(fulfilment.kitchen_queue()), 1)

	def test_свободные_без_телефона_и_состава(self):
		with _as("Habibi Courier"):
			(card,) = fulfilment.courier_free()
		self.assertNotIn("phone", card)
		self.assertNotIn("items", card)
		self.assertEqual(card["items_count"], 1)
		self.assertEqual(card["address"], "ул. Абая, 12, Алматы")
		self.orders_mock.assert_called_once_with(fulfilment.READY, unassigned=True, delivery_only=True)

	def test_мои_с_телефоном_и_только_свои(self):
		with _as("Habibi Courier"), patch.object(fulfilment, "_my_employee", return_value="HR-EMP-00001"):
			(card,) = fulfilment.courier_mine()
		self.assertEqual(card["phone"], "+77019990011")
		self.assertEqual(card["items"], [{"item_name": "Бургер", "qty": 2.0}])
		self.orders_mock.assert_called_once_with(fulfilment.OUT, courier="HR-EMP-00001")

	def test_курьер_без_employee_видит_ошибку_в_мои_но_свободные_работают(self):
		with _as("Habibi Courier"), patch.object(fulfilment, "_my_employee", return_value=None):
			with self.assertRaises(frappe.ValidationError):
				fulfilment.courier_mine()
			self.assertEqual(len(fulfilment.courier_free()), 1)


class TestWithoutWorkflow(IntegrationTestCase):
	def test_без_воркфлоу_очереди_пусты(self):
		"""Сайт без воркфлоу заказа (или без custom-полей) — это пустая
		очередь, а не 500 на экране кухни."""
		with (
			_as("Habibi Kitchen", "Habibi Courier"),
			patch.object(fulfilment, "_state_field", return_value=None),
			patch.object(fulfilment, "_my_employee", return_value="HR-EMP-00001"),
		):
			self.assertEqual(fulfilment.kitchen_queue(), [])
			self.assertEqual(fulfilment.courier_free(), [])
			self.assertEqual(fulfilment.courier_mine(), [])

	def test_без_custom_courier_очередь_курьера_пуста(self):
		with (
			_as("Habibi Courier"),
			patch.object(fulfilment, "_state_field", return_value="custom_order_status"),
			patch.object(fulfilment, "_has", return_value=False),
		):
			self.assertEqual(fulfilment._orders(fulfilment.READY, unassigned=True, delivery_only=True), [])


class TestTake(IntegrationTestCase):
	STATE = "custom_order_status"

	def _row(self, **kw):
		return frappe._dict(
			{"docstatus": 1, self.STATE: "Ready", "custom_courier": None, "custom_fulfilment_type": "Delivery", **kw}
		)

	def _take(self, row, employee="HR-EMP-00001"):
		doc = MagicMock()
		with (
			_as("Habibi Courier"),
			patch.object(fulfilment, "_state_field", return_value=self.STATE),
			patch.object(fulfilment, "_has", return_value=True),
			patch.object(fulfilment, "_my_employee", return_value=employee),
			patch("frappe.db.get_value", return_value=row) as get_value,
			patch("frappe.get_doc", return_value=doc),
			patch("habibi_ai.cabinet.fulfilment.apply_workflow") as apply,
		):
			result = fulfilment.courier_take("SAL-ORD-2026-00013")
		return result, doc, apply, get_value

	def test_успех_назначает_курьера_и_диспатчит(self):
		result, doc, apply, get_value = self._take(self._row())
		self.assertEqual(result, {"taken": False})
		self.assertEqual(doc.custom_courier, "HR-EMP-00001")
		apply.assert_called_once_with(doc, "Dispatch")
		self.assertTrue(get_value.call_args.kwargs["for_update"])

	def test_заказ_уже_взят_другим(self):
		result, _doc, apply, _ = self._take(self._row(custom_courier="HR-EMP-00002"))
		self.assertEqual(result, {"taken": True})
		apply.assert_not_called()

	def test_заказ_не_в_готово(self):
		for state in ("In Kitchen", "Out for Delivery", "Cancelled"):
			with self.subTest(state):
				result, _doc, apply, _ = self._take(self._row(**{self.STATE: state}))
				self.assertEqual(result, {"taken": True})
				apply.assert_not_called()

	def test_самовывоз_брать_нельзя(self):
		result, _doc, apply, _ = self._take(self._row(custom_fulfilment_type="Pickup"))
		self.assertEqual(result, {"taken": True})
		apply.assert_not_called()

	def test_не_проведённый_заказ_брать_нельзя(self):
		result, _doc, apply, _ = self._take(self._row(docstatus=0))
		self.assertEqual(result, {"taken": True})
		apply.assert_not_called()

	def test_без_employee_понятная_ошибка(self):
		with self.assertRaises(frappe.ValidationError):
			self._take(self._row(), employee=None)

	def test_несуществующий_заказ(self):
		with self.assertRaises(frappe.DoesNotExistError):
			self._take(None)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --test-category all --module habibi_ai.tests.test_cabinet_fulfilment'`
Expected: FAIL (`ImportError: cannot import name 'fulfilment'`).

- [ ] **Step 3: Write minimal implementation**

Создать `habibi_ai/habibi_ai/cabinet/fulfilment.py`:

```python
"""Кухня и курьер: очереди заказов для их экранов кабинета.

Методы режут поля сами (см. fulfilment_rules): кухне не нужны ни цены, ни
клиент, курьеру — ни цены, ни чужие телефоны. Переходы «Готово» и
«Доставлено» идут через orders.apply (воркфлоу проверяет роль воркфлоу), здесь
— чтение очередей и «Взять».

Имена состояний и действия — прод-воркфлоу «Habibi Burger Order» (см.
burger-workshop/BUILD-LOG.md); состояние читаем из поля, которое воркфлоу
сайта выбрал для себя, как и orders._state_field.
"""

from collections import defaultdict

import frappe
from frappe import _
from frappe.model.workflow import apply_workflow, get_workflow_name
from frappe.utils import now_datetime

from habibi_ai import fulfilment_rules as rules
from habibi_ai.cabinet import orders

KITCHEN_ROLE = "Habibi Kitchen"
COURIER_ROLE = "Habibi Courier"
IN_KITCHEN = "In Kitchen"
READY = "Ready"
OUT = "Out for Delivery"
TAKE_ACTION = "Dispatch"
DELIVERY = "Delivery"

ORDER_FIELDS = ("name", "modified", "customer_name", "shipping_address", "address_display", "contact_mobile")
# Заведены руками на конкретном сайте: нет в мете — не просим, как orders._optional
CUSTOM_FIELDS = (
	"custom_kitchen_notes",
	"custom_courier",
	"custom_fulfilment_type",
	"custom_delivery_zone",
	"custom_whatsapp_number",
)


def _require(role):
	roles = set(frappe.get_roles())
	if role not in roles and "System Manager" not in roles:
		frappe.throw(_("Нет доступа"), frappe.PermissionError)


def _state_field():
	workflow = get_workflow_name("Sales Order")
	return orders._state_field(workflow) if workflow else None


def _has(fieldname):
	return frappe.get_meta("Sales Order").has_field(fieldname)


def _my_employee():
	return frappe.db.get_value("Employee", {"user_id": frappe.session.user, "status": "Active"}, "name")


def _need_employee():
	employee = _my_employee()
	if not employee:
		frappe.throw(_("Вам не назначен профиль курьера"))
	return employee


def _orders(state, *, courier=None, unassigned=False, delivery_only=False):
	"""Проведённые заказы в состоянии, старые первыми.

	Нет воркфлоу или поля, по которому надо отбирать, — пустой список, а не
	ошибка: сайт без доставки курьерами просто не имеет такой очереди."""
	field = _state_field()
	if not field:
		return []
	filters = {field: state, "docstatus": 1}
	if courier is not None or unassigned:
		if not _has("custom_courier"):
			return []
		filters["custom_courier"] = courier if courier is not None else ["is", "not set"]
	if delivery_only:
		if not _has("custom_fulfilment_type"):
			return []
		filters["custom_fulfilment_type"] = DELIVERY
	fields = [*ORDER_FIELDS, *(f for f in CUSTOM_FIELDS if _has(f))]
	return frappe.get_all("Sales Order", filters=filters, fields=fields, order_by="modified asc")


def _items(names):
	if not names:
		return {}
	rows = frappe.get_all(
		"Sales Order Item",
		filters={"parent": ["in", names], "parenttype": "Sales Order"},
		fields=["parent", "item_code", "item_name", "qty"],
		order_by="idx asc",
	)
	grouped = defaultdict(list)
	for row in rows:
		grouped[row.parent].append(row)
	return grouped


@frappe.whitelist()
def kitchen_queue():
	_require(KITCHEN_ROLE)
	found = _orders(IN_KITCHEN)
	items = _items([o.name for o in found])
	now = now_datetime()
	return [rules.kitchen_card(o, items.get(o.name, []), now) for o in found]


@frappe.whitelist()
def courier_mine():
	_require(COURIER_ROLE)
	found = _orders(OUT, courier=_need_employee())
	items = _items([o.name for o in found])
	now = now_datetime()
	return [rules.courier_card(o, items.get(o.name, []), now, own=True) for o in found]


@frappe.whitelist()
def courier_free():
	_require(COURIER_ROLE)
	found = _orders(READY, unassigned=True, delivery_only=True)
	items = _items([o.name for o in found])
	now = now_datetime()
	return [rules.courier_card(o, items.get(o.name, []), now, own=False) for o in found]


@frappe.whitelist(methods=["POST"])
def courier_take(name):
	"""Взять свободный заказ: курьер и переход Dispatch одним сохранением.

	Строку блокируем и перечитываем: два курьера, нажавшие одновременно, не
	возьмут один заказ. «Не вышло» — это {"taken": True}, а не ошибка: экран
	скажет «уже взят» и перечитает список."""
	_require(COURIER_ROLE)
	employee = _need_employee()
	field = _state_field()
	if not field or not _has("custom_courier") or not _has("custom_fulfilment_type"):
		frappe.throw(_("Доставка курьерами на сайте не настроена"))
	row = frappe.db.get_value(
		"Sales Order",
		name,
		["docstatus", field, "custom_courier", "custom_fulfilment_type"],
		as_dict=True,
		for_update=True,
	)
	if not row:
		frappe.throw(_("Заказ не найден"), frappe.DoesNotExistError)
	if (
		row.docstatus != 1
		or row[field] != READY
		or row.custom_courier
		or row.custom_fulfilment_type != DELIVERY
	):
		return {"taken": True}
	doc = frappe.get_doc("Sales Order", name)
	doc.custom_courier = employee
	# Воркфлоу проверит роль перехода и условие «доставка и курьер заданы»
	apply_workflow(doc, TAKE_ACTION)
	return {"taken": False}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --test-category all --module habibi_ai.tests.test_cabinet_fulfilment'`
Expected: PASS. Если `test_несуществующий_заказ` падает по типу исключения, убедиться, что `frappe.throw(..., frappe.DoesNotExistError)` передаёт класс вторым позиционным аргументом (так принято в `scope.require`).

- [ ] **Step 5: Commit (habibi_ai)**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai
git add habibi_ai/cabinet/fulfilment.py habibi_ai/tests/test_cabinet_fulfilment.py
git commit -m "feat(cabinet): очереди кухни и курьера, «Взять» заказ

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Realtime-событие `fulfilment` (habibi_ai)

**Files:**
- Modify: `habibi_ai/habibi_ai/cabinet/realtime.py`
- Modify: `habibi_ai/habibi_ai/tests/test_cabinet_realtime.py`

**Interfaces:**
- Consumes: хуки `doc_events["Sales Order"]` уже вызывают `realtime.on_change` на `on_update`, `on_submit`, `on_update_after_submit`, `on_cancel` (менять `hooks.py` не нужно).
- Produces: `realtime.FLOOR_ROLES = ("Habibi Kitchen", "Habibi Courier")`; `_recipients(roles=CABINET_ROLES)`; событие `habibi_cabinet` с payload `{"topic": "fulfilment", "chat": None}` для получателей `FLOOR_ROLES` на **любое** изменение Sales Order. Событие `orders` остаётся прежним.

- [ ] **Step 1: Write the failing test**

В `habibi_ai/habibi_ai/tests/test_cabinet_realtime.py` сначала поправить два существующих теста заказа: теперь заказ шлёт два события разным ролям, а `patch(..., return_value=[...])` вернул бы владельца для обеих групп. Добавить над классом помощник:

```python
def _owner_only(roles=realtime.CABINET_ROLES):
	"""Получатели по ролям: владелец — кабинету, кухни и курьеров нет."""
	return ["owner@example.com"] if roles == realtime.CABINET_ROLES else []
```

В `test_заказ_от_бота_шлёт_событие_заказов` и в `test_смена_статуса_проведённого_заказа_шлёт_событие` заменить
`patch("habibi_ai.cabinet.realtime._recipients", return_value=["owner@example.com"])`
на
`patch("habibi_ai.cabinet.realtime._recipients", side_effect=_owner_only)`.

В `test_заказ_не_от_бота_не_шумит` добавить патч `_recipients` на пустой список (иначе тест зависит от того, есть ли на сайте пользователи с ролями кухни):

```python
	def test_заказ_не_от_бота_не_шумит(self):
		doc = frappe._dict(doctype="Sales Order", name="SO-X")
		with (
			patch("habibi_ai.cabinet.realtime._recipients", return_value=[]),
			patch("habibi_ai.cabinet.realtime.frappe.publish_realtime") as pub,
		):
			realtime.on_change(doc)
		pub.assert_not_called()
```

И добавить новые тесты в конец класса:

```python
	@staticmethod
	def _floor_only(roles=realtime.CABINET_ROLES):
		return ["kitchen@example.com"] if roles == realtime.FLOOR_ROLES else []

	def test_любой_заказ_будит_кухню_и_курьеров(self):
		"""Заказ, заведённый руками (без AI Order Quote), кухня тоже должна
		увидеть — поэтому фильтр по расчёту бота к этому событию не относится."""
		doc = frappe._dict(doctype="Sales Order", name="SO-MANUAL")
		with (
			patch("habibi_ai.cabinet.realtime._recipients", side_effect=self._floor_only),
			patch("habibi_ai.cabinet.realtime.frappe.publish_realtime") as pub,
		):
			realtime.on_change(doc)
		pub.assert_called_once_with(
			"habibi_cabinet",
			{"topic": "fulfilment", "chat": None},
			user="kitchen@example.com",
			after_commit=True,
		)

	def test_заказ_бота_шлёт_оба_события_каждому_своему(self):
		doc = frappe._dict(doctype="Sales Order", name="SO-BOT")

		def by_role(roles=realtime.CABINET_ROLES):
			return ["kitchen@example.com"] if roles == realtime.FLOOR_ROLES else ["owner@example.com"]

		with (
			patch("habibi_ai.cabinet.realtime.frappe.db.exists", return_value=True),
			patch("habibi_ai.cabinet.realtime._recipients", side_effect=by_role),
			patch("habibi_ai.cabinet.realtime.frappe.publish_realtime") as pub,
		):
			realtime.on_change(doc)
		sent = {(c.args[1]["topic"], c.kwargs["user"]) for c in pub.call_args_list}
		self.assertEqual(sent, {("fulfilment", "kitchen@example.com"), ("orders", "owner@example.com")})
		self.assertEqual(pub.call_count, 2)

	def test_сообщения_чатов_кухню_не_будят(self):
		with (
			patch("habibi_ai.cabinet.realtime._recipients", side_effect=self._floor_only),
			patch("habibi_ai.cabinet.realtime.frappe.publish_realtime") as pub,
		):
			realtime.on_change(frappe._dict(doctype="Telegram Message", chat="C1"))
		pub.assert_not_called()

	def test_получатели_кухни_это_только_её_роли(self):
		email = "cabinet-realtime-kitchen-test@example.com"
		if frappe.db.exists("User", email):
			user = frappe.get_doc("User", email)
		else:
			user = frappe.get_doc(
				{"doctype": "User", "email": email, "first_name": "Kitchen", "send_welcome_email": 0}
			).insert(ignore_permissions=True)
		user.add_roles("Habibi Kitchen")
		self.assertIn(email, realtime._recipients(realtime.FLOOR_ROLES))
		self.assertNotIn(email, realtime._recipients(realtime.CABINET_ROLES))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --test-category all --module habibi_ai.tests.test_cabinet_realtime'`
Expected: FAIL (`AttributeError: module ... has no attribute 'FLOOR_ROLES'`).

- [ ] **Step 3: Write minimal implementation**

В `habibi_ai/habibi_ai/cabinet/realtime.py`:

```python
EVENT = "habibi_cabinet"
CABINET_ROLES = ("Habibi Owner", "Habibi Staff", "System Manager")
# Кухня и курьеры слушают свой канал: любое изменение заказа, а не только
# заказов бота — кухне нужны и заказы, заведённые оператором руками
FLOOR_ROLES = ("Habibi Kitchen", "Habibi Courier")


def _recipients(roles=CABINET_ROLES):
```

В теле `_recipients` заменить `HasRole.role.isin(CABINET_ROLES)` на `HasRole.role.isin(roles)`; в докстринг добавить «roles — какие роли получают событие».

Заменить `_on_change` и добавить `_publish`:

```python
def _publish(payload, roles):
	for user in _recipients(roles):
		frappe.publish_realtime(EVENT, payload, user=user, after_commit=True)


def _on_change(doc):
	if doc.doctype == "Sales Order":
		# Сигнал «перечитай очередь» — без данных, на любой заказ
		_publish({"topic": "fulfilment", "chat": None}, FLOOR_ROLES)
		if not frappe.db.exists("AI Order Quote", {"sales_order": doc.name}):
			return
		payload = {"topic": "orders", "chat": None}
	else:
		chat = doc.telegram_chat if doc.doctype == "AI Channel Chat" else doc.chat
		# То же правило, что у списка переписок: сообщения групп, служебного
		# чата и синхронизации истории чужих диалогов кабинет не будят
		if not scope.in_scope(chat):
			return
		payload = {"topic": "chats", "chat": chat}
	_publish(payload, CABINET_ROLES)
```

В докстринге модуля добавить абзац: «Кухня и курьеры получают отдельное событие `fulfilment` на любой заказ — без данных, только сигнал перечитать очередь».

- [ ] **Step 4: Run test to verify it passes**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --test-category all --module habibi_ai.tests.test_cabinet_realtime'`
Expected: PASS (включая старые тесты после правки).

- [ ] **Step 5: Commit (habibi_ai)**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai
git add habibi_ai/cabinet/realtime.py habibi_ai/tests/test_cabinet_realtime.py
git commit -m "feat(cabinet): realtime-событие fulfilment для кухни и курьеров

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Пресет «общепит»: разделы и права (habibi_ai)

**Files:**
- Modify: `habibi_ai/habibi_ai/presets/food.json`
- Test: `habibi_ai/habibi_ai/tests/test_presets.py`

**Interfaces:**
- Consumes: роли `Habibi Kitchen`, `Habibi Courier` на сайте (Задача 1: фикстура и `migrate`); `habibi_ai.presets.apply(name)`.
- Produces: разделы Cabinet Settings `kitchen` (screen `kitchen`, `roles: "Habibi Kitchen"`, feature `orders`) и `courier` (screen `courier`, `roles: "Habibi Courier"`, feature `delivery`, icon `bike`) и права этих ролей на Sales Order и связанные доктайпы.

- [ ] **Step 1: Write the failing test**

Добавить в `habibi_ai/habibi_ai/tests/test_presets.py`:

```python
	def test_разделы_кухни_и_курьера_только_для_своих_ролей(self):
		presets.apply("food")
		sections = {s.key: s for s in frappe.get_single("Cabinet Settings").sections}
		self.assertEqual(
			(sections["kitchen"].kind, sections["kitchen"].screen, sections["kitchen"].roles),
			("custom", "kitchen", "Habibi Kitchen"),
		)
		self.assertEqual(
			(sections["courier"].kind, sections["courier"].screen, sections["courier"].roles),
			("custom", "courier", "Habibi Courier"),
		)
		self.assertEqual(sections["courier"].icon, "bike")
		# Повторное применение не плодит копий
		presets.apply("food")
		keys = [s.key for s in frappe.get_single("Cabinet Settings").sections]
		self.assertEqual(keys.count("kitchen"), 1)
		self.assertEqual(keys.count("courier"), 1)

	def test_права_кухни_и_курьера_на_заказ(self):
		"""Воркфлоу проверяет write на заказ, orders.apply — read; проведение
		и сохранение подтягивают чтение связанных доктайпов."""
		presets.apply("food")
		for role in ("Habibi Kitchen", "Habibi Courier"):
			with self.subTest(role):
				self.assertTrue(
					frappe.db.exists("Custom DocPerm", {"parent": "Sales Order", "role": role, "read": 1, "write": 1})
				)
				self.assertTrue(frappe.db.exists("Custom DocPerm", {"parent": "Account", "role": role, "read": 1}))
				# Ни удалять, ни отменять заказ они не вправе
				self.assertFalse(
					frappe.db.exists("Custom DocPerm", {"parent": "Sales Order", "role": role, "delete": 1})
				)
				self.assertFalse(
					frappe.db.exists("Custom DocPerm", {"parent": "Sales Order", "role": role, "cancel": 1})
				)
		self.assertTrue(frappe.db.exists("Custom DocPerm", {"parent": "Employee", "role": "Habibi Courier", "read": 1}))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --test-category all --module habibi_ai.tests.test_presets'`
Expected: FAIL (`KeyError: 'kitchen'`).

- [ ] **Step 3: Write minimal implementation**

В `habibi_ai/habibi_ai/presets/food.json` в массив `sections` после раздела `telegram` добавить:

```json
    {
      "key": "kitchen",
      "label": "Кухня",
      "icon": "utensils",
      "kind": "custom",
      "screen": "kitchen",
      "roles": "Habibi Kitchen",
      "feature": "orders"
    },
    {
      "key": "courier",
      "label": "Доставки",
      "icon": "bike",
      "kind": "custom",
      "screen": "courier",
      "roles": "Habibi Courier",
      "feature": "delivery"
    }
```

(Отступы и запятые — как в соседних элементах файла.) В объект `permissions` добавить, рядом с `Habibi Owner`/`Habibi Staff`:

```json
    "Habibi Kitchen": {
      "Sales Order": ["read", "write"],
      "Item": ["read"],
      "Customer": ["read"],
      "Account": ["read"]
    },
    "Habibi Courier": {
      "Sales Order": ["read", "write"],
      "Item": ["read"],
      "Customer": ["read"],
      "Account": ["read"],
      "Employee": ["read"],
      "Delivery Zone": ["read"]
    }
```

Права выдаются через `presets.apply` (`add_permission` + `update_permission_property`) — единственный безопасный путь (см. «Care needed» в `burger-workshop/BUILD-LOG.md`: прямая вставка Custom DocPerm выбивает стандартные права). Если после визуальной проверки (Задача 9) выяснится, что воркфлоу или проведение требуют чтения ещё какого-то доктайпа, его дописывают сюда же вместе с тестом выше.

- [ ] **Step 4: Run test to verify it passes**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --test-category all --module habibi_ai.tests.test_presets'`
Expected: PASS. Если `Delivery Zone`/`Employee` нет на dev-сайте, `presets.apply` их пропускает (`frappe.db.exists("DocType", ...)`), а тест для `Employee` тогда упадёт: условить эту проверку тем же `if frappe.db.exists("DocType", "Employee")`.

- [ ] **Step 5: Commit (habibi_ai)**

```bash
cd /Users/fsa/Projects/habibi/habibi_ai
git add habibi_ai/presets/food.json habibi_ai/tests/test_presets.py
git commit -m "feat(presets): разделы и права кухни и курьера в пресете «общепит»

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Фронт — основа: API, realtime, иконка, возраст (habibi_ui)

**Files:**
- Create: `habibi_ui/frontend/src/features/cabinet/fulfilment/api.ts`
- Modify: `habibi_ui/frontend/src/features/cabinet/useRealtime.ts`
- Modify: `habibi_ui/frontend/src/features/cabinet/nav.ts`
- Modify: `habibi_ui/frontend/src/features/cabinet/format.ts`

**Interfaces:**
- Consumes: серверные методы Задачи 3 и `habibi_ai.cabinet.orders.apply` (`name`, `action`, `reason`).
- Produces (для Задач 7 и 8):
  - типы `KitchenItem`, `KitchenOrder`, `CourierOrder`
  - хуки `useKitchenQueue()`, `useCourierMine()`, `useCourierFree()` — `useQuery` с `refetchInterval: 30_000` и `refetchOnWindowFocus`
  - мутации `useMarkReady()`, `useMarkDelivered()` (аргумент — имя заказа), `useTake()` (аргумент — имя, результат `{ taken: boolean }`)
  - `ageLabel(minutes: number): string` из `format.ts`
  - `useRealtime` сбрасывает `["cabinet", "fulfilment"]` на событие `fulfilment`; иконка `bike` в `ICONS`.

Тестового раннера на фронте нет (и добавлять его ради этой фичи не нужно): проверка — `yarn typecheck` и визуальный проход в Задаче 9.

- [ ] **Step 1: Write the implementation (typecheck is the failing check)**

Создать `habibi_ui/frontend/src/features/cabinet/fulfilment/api.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { call } from "../../../shared/api/client";

export type KitchenItem = { item_name: string; qty: number };

export type KitchenOrder = {
  name: string;
  age: number;
  notes: string | null;
  items: KitchenItem[];
};

// Контракт habibi_ai.cabinet.fulfilment. phone и items приходят только в
// «Мои»: у свободного заказа телефона нет, пока курьер его не взял.
export type CourierOrder = {
  name: string;
  age: number;
  customer_name: string | null;
  address: string | null;
  zone: string | null;
  items_count: number;
  phone?: string | null;
  items?: KitchenItem[];
};

// Действия воркфлоу прод-сайта (burger-workshop/BUILD-LOG.md). «Взять» — отдельный
// метод: ему нужны назначение курьера и блокировка от гонки.
export const READY_ACTION = "Mark Ready";
export const DELIVERED_ACTION = "Mark Delivered";

const KEY = ["cabinet", "fulfilment"] as const;
// Сокет может не подключиться, а кухня не должна зависеть от одного сокета
const POLL_MS = 30_000;

function useQueue<T>(name: string, method: string) {
  return useQuery({
    queryKey: [...KEY, name],
    queryFn: () => call<T>(`habibi_ai.cabinet.fulfilment.${method}`),
    refetchInterval: POLL_MS,
    refetchOnWindowFocus: true,
  });
}

export const useKitchenQueue = () => useQueue<KitchenOrder[]>("kitchen", "kitchen_queue");
export const useCourierMine = () => useQueue<CourierOrder[]>("mine", "courier_mine");
export const useCourierFree = () => useQueue<CourierOrder[]>("free", "courier_free");

function useTransition(action: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (name: string) => call("habibi_ai.cabinet.orders.apply", { name, action, reason: "" }),
    onSettled: () => void queryClient.invalidateQueries({ queryKey: KEY }),
  });
}

export const useMarkReady = () => useTransition(READY_ACTION);
export const useMarkDelivered = () => useTransition(DELIVERED_ACTION);

export function useTake() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (name: string) => call<{ taken: boolean }>("habibi_ai.cabinet.fulfilment.courier_take", { name }),
    // «Уже взят» — тоже повод перечитать списки
    onSettled: () => void queryClient.invalidateQueries({ queryKey: KEY }),
  });
}
```

В `useRealtime.ts`:

```ts
type Event = { topic: "chats" | "orders" | "fulfilment"; chat: string | null };
```

и в обработчике событий перед веткой `orders`:

```ts
        socket.on("habibi_cabinet", (event) => {
          if (event.topic === "fulfilment") {
            void queryClient.invalidateQueries({ queryKey: ["cabinet", "fulfilment"] });
          } else if (event.topic === "orders") {
```

(остальные ветки не менять).

В `nav.ts` добавить `Bike` в импорт из `lucide-react` (по алфавиту, после `Building2`? — перед ним: `Bike, Building2, ...`) и в `ICONS`: `bike: Bike,`.

В `format.ts` рядом с `plural` добавить:

```ts
/** «только что», «12 мин назад», «1 ч 5 мин назад» — возраст заказа на кухне и в доставке. */
export function ageLabel(minutes: number): string {
  if (minutes < 1) return "только что";
  if (minutes < 60) return `${minutes} мин назад`;
  const rest = minutes % 60;
  return `${Math.floor(minutes / 60)} ч${rest ? ` ${rest} мин` : ""} назад`;
}
```

- [ ] **Step 2: Run typecheck to verify it passes**

Run: `cd /Users/fsa/Projects/habibi/habibi_ui && yarn typecheck`
Expected: без ошибок (в новом коде нет неиспользуемых экспортов, которые ломали бы линт; экраны подключатся в Задачах 7–8).

- [ ] **Step 3: Commit (habibi_ui)**

```bash
cd /Users/fsa/Projects/habibi/habibi_ui
git add frontend/src/features/cabinet/fulfilment/api.ts frontend/src/features/cabinet/useRealtime.ts frontend/src/features/cabinet/nav.ts frontend/src/features/cabinet/format.ts
git commit -m "feat(cabinet): основа экранов кухни и курьера — запросы, realtime, иконка

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Экран кухни (habibi_ui)

**Files:**
- Create: `habibi_ui/frontend/src/features/cabinet/fulfilment/useChime.ts`
- Create: `habibi_ui/frontend/src/features/cabinet/fulfilment/KitchenScreen.tsx`
- Modify: `habibi_ui/frontend/src/features/cabinet/screens.tsx`

**Interfaces:**
- Consumes: `useKitchenQueue`, `useMarkReady`, `KitchenOrder` (Задача 6); `ageLabel`, `shortNo` из `format.ts`; `Page`, `surface`, `StatusBadge`, `EmptyState`, `ListSkeleton`, `ErrorNote` из `ui.tsx`.
- Produces: `KitchenScreen` под ключом `kitchen` в реестре `SCREENS`; `useChime(): { enabled: boolean; toggle(): void; play(): void }`.

- [ ] **Step 1: Write the implementation**

Создать `useChime.ts`:

```ts
import { useCallback, useRef, useState } from "react";

const STORAGE_KEY = "habibi.kitchen.sound";

function readEnabled(): boolean {
  try {
    return localStorage.getItem(STORAGE_KEY) === "1";
  } catch {
    return false;
  }
}

/**
 * Сигнал нового заказа. Браузеры не дают играть звук без жеста пользователя,
 * поэтому AudioContext создаётся и «будится» в обработчике нажатия кнопки
 * «Звук», а не при первом заказе. По умолчанию выключен; выбор помнится в
 * localStorage (его может не быть — тогда просто не помнится).
 */
export function useChime() {
  const [enabled, setEnabled] = useState(readEnabled);
  const context = useRef<AudioContext | null>(null);

  const play = useCallback(() => {
    const ctx = context.current;
    if (!ctx) return;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.frequency.value = 880;
    gain.gain.value = 0.15;
    osc.connect(gain).connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.25);
  }, []);

  const toggle = useCallback(() => {
    const next = !enabled;
    if (next) {
      try {
        context.current ??= new AudioContext();
        void context.current.resume();
      } catch {
        // Нет Web Audio — останется вибрация и подсветка
      }
    }
    setEnabled(next);
    try {
      localStorage.setItem(STORAGE_KEY, next ? "1" : "0");
    } catch {
      // приватный режим — не страшно
    }
  }, [enabled]);

  return { enabled, toggle, play: enabled ? play : () => undefined };
}
```

Создать `KitchenScreen.tsx`:

```tsx
import { Bell, BellOff, ChefHat } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";

import { cn } from "../../../shared/lib/utils";
import { Button } from "../../../shared/ui/button";
import { ageLabel, shortNo } from "../format";
import { EmptyState, ErrorNote, ListSkeleton, Page, StatusBadge, surface } from "../ui";
import { type KitchenOrder, useKitchenQueue, useMarkReady } from "./api";
import { useChime } from "./useChime";

const FRESH_MS = 8000;

/**
 * Имена заказов, появившихся в очереди после первой загрузки: их подсвечиваем
 * на несколько секунд, вибрируем (где браузер умеет) и играем сигнал. Первая
 * загрузка только запоминает очередь — иначе каждый вход «звонил» бы за все
 * заказы, что уже готовятся.
 */
function useFresh(names: string[], loaded: boolean, onNew: () => void) {
  const seen = useRef<Set<string> | null>(null);
  const [fresh, setFresh] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (!loaded) return;
    if (seen.current === null) {
      seen.current = new Set(names);
      return;
    }
    const added = names.filter((n) => !seen.current!.has(n));
    names.forEach((n) => seen.current!.add(n));
    if (!added.length) return;
    navigator.vibrate?.(200);
    onNew();
    setFresh((prev) => new Set([...prev, ...added]));
    const timer = setTimeout(() => setFresh((prev) => new Set([...prev].filter((n) => !added.includes(n)))), FRESH_MS);
    return () => clearTimeout(timer);
    // onNew меняется с флагом звука; новые имена — единственный повод сработать
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [names.join("|"), loaded]);

  return fresh;
}

export function KitchenScreen() {
  const queue = useKitchenQueue();
  const ready = useMarkReady();
  const chime = useChime();
  const orders = queue.data ?? [];
  const fresh = useFresh(
    orders.map((o) => o.name),
    queue.isSuccess,
    chime.play,
  );

  return (
    <Page
      title="Кухня"
      subtitle={queue.isSuccess ? `В работе: ${orders.length}` : undefined}
      width="wide"
      actions={
        <Button variant="outline" size="lg" onClick={chime.toggle} aria-pressed={chime.enabled}>
          {chime.enabled ? <Bell /> : <BellOff />}
          Звук
        </Button>
      }
    >
      {queue.isPending ? (
        <ListSkeleton rows={3} />
      ) : queue.error ? (
        <ErrorNote title="Очередь не загрузилась">{queue.error.message}</ErrorNote>
      ) : orders.length === 0 ? (
        <EmptyState icon={ChefHat} text="Заказов на кухне нет" />
      ) : (
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {orders.map((order) => (
            <KitchenCard
              key={order.name}
              order={order}
              isNew={fresh.has(order.name)}
              pending={ready.isPending && ready.variables === order.name}
              onReady={() =>
                ready.mutate(order.name, {
                  onSuccess: () => toast.success(`${shortNo(order.name)} готов`),
                  onError: (e) => toast.error(e.message),
                })
              }
            />
          ))}
        </div>
      )}
    </Page>
  );
}

function KitchenCard({
  order,
  isNew,
  pending,
  onReady,
}: {
  order: KitchenOrder;
  isNew: boolean;
  pending: boolean;
  onReady: () => void;
}) {
  return (
    <div className={cn(surface, "p-4 transition-shadow", isNew && "ring-2 ring-primary")}>
      <div className="flex items-center justify-between gap-2">
        <div className="text-base font-bold">
          {shortNo(order.name)}{" "}
          <span className="text-sm font-normal text-muted-foreground">· {ageLabel(order.age)}</span>
        </div>
        <StatusBadge tone="progress">Готовится</StatusBadge>
      </div>
      <ul className="mt-3 space-y-1">
        {order.items.map((item, i) => (
          <li key={i} className="flex gap-2 text-base">
            <b className="min-w-8 text-primary tabular-nums">{item.qty}×</b>
            <span>{item.item_name}</span>
          </li>
        ))}
        {order.items.length === 0 && <li className="text-sm text-muted-foreground">Состав не указан</li>}
      </ul>
      {order.notes && (
        <div className="mt-3 rounded-lg bg-amber-100 px-3 py-2 text-sm text-amber-800 dark:bg-amber-400/15 dark:text-amber-300">
          ⚠ {order.notes}
        </div>
      )}
      <Button className="mt-4 h-12 w-full text-base font-semibold" disabled={pending} onClick={onReady}>
        Готово
      </Button>
    </div>
  );
}
```

В `screens.tsx` добавить импорт и запись реестра:

```tsx
import { KitchenScreen } from "./fulfilment/KitchenScreen";
...
  telegram: TelegramScreen,
  kitchen: KitchenScreen,
};
```

(`courier` добавится в Задаче 8.)

- [ ] **Step 2: Run typecheck to verify it passes**

Run: `cd /Users/fsa/Projects/habibi/habibi_ui && yarn typecheck`
Expected: без ошибок. Если TS ругается на `qty` как `number`, показывающийся как `2`, а не `2.0` — это число, форматирование не нужно; если сервер вернёт дробное (`1.5`), оно так и покажется.

- [ ] **Step 3: Commit (habibi_ui)**

```bash
cd /Users/fsa/Projects/habibi/habibi_ui
git add frontend/src/features/cabinet/fulfilment/useChime.ts frontend/src/features/cabinet/fulfilment/KitchenScreen.tsx frontend/src/features/cabinet/screens.tsx
git commit -m "feat(cabinet): экран кухни — очередь «Готовится», «Готово», сигнал нового заказа

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Экран курьера (habibi_ui)

**Files:**
- Create: `habibi_ui/frontend/src/features/cabinet/fulfilment/CourierScreen.tsx`
- Modify: `habibi_ui/frontend/src/features/cabinet/screens.tsx`

**Interfaces:**
- Consumes: `useCourierMine`, `useCourierFree`, `useMarkDelivered`, `useTake`, `CourierOrder` (Задача 6); `ageLabel`, `plural`, `shortNo` из `format.ts`; `buttonVariants` из `shared/ui/button`.
- Produces: `CourierScreen` под ключом `courier` в `SCREENS`.

- [ ] **Step 1: Write the implementation**

Создать `CourierScreen.tsx`:

```tsx
import { Bike, MapPin, PackageCheck, Phone } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";

import { cn } from "../../../shared/lib/utils";
import { Button, buttonVariants } from "../../../shared/ui/button";
import { ageLabel, plural, shortNo } from "../format";
import { EmptyState, ErrorNote, ListSkeleton, Page, StatusBadge, surface } from "../ui";
import { type CourierOrder, useCourierFree, useCourierMine, useMarkDelivered, useTake } from "./api";

type Tab = "mine" | "free";

const mapLink = (address: string) => `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(address)}`;
const telLink = (phone: string) => `tel:${phone.replace(/[^\d+]/g, "")}`;

export function CourierScreen() {
  const [tab, setTab] = useState<Tab>("mine");
  const mine = useCourierMine();
  const free = useCourierFree();
  const delivered = useMarkDelivered();
  const take = useTake();

  function onTake(order: CourierOrder) {
    take.mutate(order.name, {
      onSuccess: ({ taken }) => {
        if (taken) {
          toast.error("Заказ уже взят или недоступен");
          return;
        }
        toast.success(`${shortNo(order.name)} — ваш`);
        setTab("mine");
      },
      onError: (e) => toast.error(e.message),
    });
  }

  function onDelivered(order: CourierOrder) {
    delivered.mutate(order.name, {
      onSuccess: () => toast.success(`${shortNo(order.name)} доставлен`),
      onError: (e) => toast.error(e.message),
    });
  }

  const query = tab === "mine" ? mine : free;
  const orders = query.data ?? [];

  return (
    <Page title="Доставки" width="narrow">
      <div role="tablist" className="mb-3 flex rounded-xl bg-muted p-1">
        <TabButton active={tab === "mine"} onClick={() => setTab("mine")}>
          Мои{mine.isSuccess ? ` · ${mine.data.length}` : ""}
        </TabButton>
        <TabButton active={tab === "free"} onClick={() => setTab("free")}>
          Свободные{free.isSuccess ? ` · ${free.data.length}` : ""}
        </TabButton>
      </div>

      {query.isPending ? (
        <ListSkeleton rows={2} />
      ) : query.error ? (
        <ErrorNote title="Список не загрузился">{query.error.message}</ErrorNote>
      ) : orders.length === 0 ? (
        <EmptyState
          icon={tab === "mine" ? PackageCheck : Bike}
          text={tab === "mine" ? "У вас нет заказов в пути" : "Свободных заказов нет"}
        />
      ) : (
        <div className="space-y-3">
          {orders.map((order) =>
            tab === "mine" ? (
              <MineCard
                key={order.name}
                order={order}
                pending={delivered.isPending && delivered.variables === order.name}
                onDelivered={() => onDelivered(order)}
              />
            ) : (
              <FreeCard
                key={order.name}
                order={order}
                pending={take.isPending && take.variables === order.name}
                onTake={() => onTake(order)}
              />
            ),
          )}
        </div>
      )}
    </Page>
  );
}

function TabButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={cn(
        "h-10 flex-1 rounded-lg text-sm font-semibold transition-colors",
        active ? "bg-background text-foreground shadow-sm" : "text-muted-foreground",
      )}
    >
      {children}
    </button>
  );
}

function Where({ order }: { order: CourierOrder }) {
  return (
    <div className="mt-2 text-sm">
      {order.customer_name && <div className="text-base font-semibold">{order.customer_name}</div>}
      <div className="text-muted-foreground">{order.address ?? "Адрес не указан"}</div>
      {order.zone && <div className="text-muted-foreground">Зона: {order.zone}</div>}
    </div>
  );
}

function MineCard({ order, pending, onDelivered }: { order: CourierOrder; pending: boolean; onDelivered: () => void }) {
  return (
    <div className={cn(surface, "p-4")}>
      <div className="flex items-center justify-between gap-2">
        <div className="text-base font-bold">{shortNo(order.name)}</div>
        <StatusBadge tone="progress">В пути</StatusBadge>
      </div>
      <Where order={order} />
      <ul className="mt-2 space-y-0.5 text-sm">
        {order.items?.map((item, i) => (
          <li key={i} className="flex gap-2">
            <b className="min-w-8 tabular-nums text-muted-foreground">{item.qty}×</b>
            <span>{item.item_name}</span>
          </li>
        ))}
      </ul>
      {(order.phone || order.address) && (
        <div className="mt-3 flex gap-2">
          {order.phone && (
            <a href={telLink(order.phone)} className={cn(buttonVariants({ variant: "outline", size: "lg" }), "h-11 flex-1")}>
              <Phone /> Позвонить
            </a>
          )}
          {order.address && (
            <a
              href={mapLink(order.address)}
              target="_blank"
              rel="noreferrer"
              className={cn(buttonVariants({ variant: "outline", size: "lg" }), "h-11 flex-1")}
            >
              <MapPin /> Карта
            </a>
          )}
        </div>
      )}
      <Button className="mt-3 h-12 w-full text-base font-semibold" disabled={pending} onClick={onDelivered}>
        Доставлено
      </Button>
    </div>
  );
}

function FreeCard({ order, pending, onTake }: { order: CourierOrder; pending: boolean; onTake: () => void }) {
  return (
    <div className={cn(surface, "p-4")}>
      <div className="flex items-center justify-between gap-2">
        <div className="text-base font-bold">
          {shortNo(order.name)}{" "}
          <span className="text-sm font-normal text-muted-foreground">· готов {ageLabel(order.age).replace(" назад", "")}</span>
        </div>
        <StatusBadge tone="ok">Готов</StatusBadge>
      </div>
      <Where order={order} />
      <div className="mt-1 text-sm text-muted-foreground">
        {order.items_count} {plural(order.items_count, ["позиция", "позиции", "позиций"])}
      </div>
      <Button className="mt-3 h-12 w-full text-base font-semibold" disabled={pending} onClick={onTake}>
        Взять заказ
      </Button>
    </div>
  );
}
```

Примечание: `ageLabel(...).replace(" назад", "")` даёт «готов 6 мин» / «готов только что». Если это покажется неуклюжим при визуальной проверке, вынести в `format.ts` вариант без «назад» отдельным аргументом.

В `screens.tsx`:

```tsx
import { CourierScreen } from "./fulfilment/CourierScreen";
...
  kitchen: KitchenScreen,
  courier: CourierScreen,
};
```

- [ ] **Step 2: Run typecheck and build to verify they pass**

Run: `cd /Users/fsa/Projects/habibi/habibi_ui && yarn typecheck && yarn build`
Expected: без ошибок. (Сборка `public/frontend` в git не входит: её делает CI — в репозитории она не отслеживается; убедиться, что `git status` после `yarn build` не показывает новых файлов, а если показывает — не добавлять их в коммит.)

- [ ] **Step 3: Commit (habibi_ui)**

```bash
cd /Users/fsa/Projects/habibi/habibi_ui
git add frontend/src/features/cabinet/fulfilment/CourierScreen.tsx frontend/src/features/cabinet/screens.tsx
git commit -m "feat(cabinet): экран курьера — «Мои» и «Свободные», «Взять» и «Доставлено»

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Сквозная и визуальная проверка (без нового кода)

**Files:** нет (правки по итогам проверки идут отдельными коммитами в соответствующий репозиторий).

Требование проекта: любой новый экран принимается только после визуальной проверки на 375 и 1280 px.

- [ ] **Step 1: Найти сайт с прод-воркфлоу и данными**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && bench --site dev.localhost execute frappe.db.exists --args "[\"Workflow\", \"Habibi Burger Order\"]"'`
Expected: имя воркфлоу. Если `None`, на dev нет прод-воркфлоу и демо-заказов: **остановиться и спросить пользователя, на каком сайте проверять** (копия прод-сайта или стенд). На прод-сайте без явного разрешения ничего не создавать и не менять.

- [ ] **Step 2: Подготовить сайт для проверки**

На выбранном сайте: применить пресет (`bench --site <site> execute habibi_ai.presets.apply --args '["food"]'`), добавить `Burger Courier` в переход `Dispatch` воркфлоу, убедиться, что у `courier@habibi-burger.example` есть `Employee` с `user_id`, выдать `kitchen@…` роли `Habibi Kitchen` и `Burger Kitchen`, `courier@…` — `Habibi Courier` и `Burger Courier`. Нужны заказы в состояниях `In Kitchen` (с заметкой про кунжут), `Ready` с доставкой (минимум два, один — самовывоз), `Out for Delivery` с этим курьером.

- [ ] **Step 3: Пройти экраны браузером**

Через Playwright MCP, под `kitchen@…`, затем под `courier@…`; размеры 375×812 и 1280×800; светлая и тёмная тема. Проверить и приложить скриншоты:

1. Вход ведёт в `/ui/c`, Desk (`/app`) уводит назад в кабинет.
2. Кухня видит только свой раздел; в карточках нет цен, телефона, адреса, имени клиента; заметка выделена; строки доставки (`SRV-DELIVERY`) в составе нет.
3. «Готово» убирает карточку из очереди; у кухни не видно заказов `Ready`.
4. Новый заказ (перевести заказ в `In Kitchen` из Desk в другой вкладке) появляется на экране кухни за секунды, карточка подсвечена.
5. Курьер: «Мои» с телефоном, «Позвонить», «Карта», «Доставлено»; «Свободные» без телефона, самовывоза в списке нет.
6. «Взять» переносит заказ в «Мои» и открывает телефон; второй курьер (или повторный вызов `courier_take` из консоли) получает «Заказ уже взят или недоступен».
7. Раздел владельца (`/c/orders`, `/c/chats`) недоступен кухне и курьеру (прямой URL → «Раздел недоступен»).
8. Сверить с макетами `.superpowers/brainstorm/44519-1790843719/content/kitchen-courier-screens.html`: отличия исправить, если они не обоснованы.

- [ ] **Step 4: Добавить недостающие права, если проверка их выявила**

Если какое-то действие падает с `PermissionError` на чтении связанного доктайпа, дописать его в `permissions` пресета (Задача 5) вместе с проверкой в `test_presets.py` и повторить Step 3 для этого действия.

- [ ] **Step 5: Прогнать все затронутые тесты**

Run: `docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/development/frappe-bench && for m in habibi_ai.tests.test_cabinet_fulfilment habibi_ai.tests.test_cabinet_realtime habibi_ai.tests.test_presets habibi_ai.tests.test_cabinet_orders habibi_ui.tests.test_floor_roles habibi_ui.tests.test_access habibi_ui.tests.test_cabinet_api habibi_ui.tests.test_session; do bench --site dev.localhost run-tests --test-category all --module $m || exit 1; done' && docker exec devcontainer-frappe-1 bash -lc 'cd /workspace/repos/habibi_ai && python3 -m unittest habibi_ai.tests.test_fulfilment_rules'`
Expected: всё PASS.

---

### Task 10: Выкатка (только после явного «да» пользователя на каждый шаг)

Эти шаги затрагивают прод и выкладывают код наружу; план их описывает, но исполнитель не делает ни одного без подтверждения.

- [ ] **Step 1: Запушить приложения и тегнуть сборку (по `CLAUDE.md`)**

```bash
cd /Users/fsa/Projects/habibi/habibi_ui && git push
cd /Users/fsa/Projects/habibi/habibi_ai && git push
cd /Users/fsa/Projects/habibi/habibi_docker && git push && git tag v1.5.0 && git push --tags
```

Теги в `habibi_docker` запускают GitHub Actions, которые собирают код в проде. Номер тега уточнить у пользователя (последний — `v1.4.9`).

- [ ] **Step 2: После сборки на проде — применить пресет и права воркфлоу**

На сайте Habibi Burger: `habibi_ai.presets.apply("food")`; добавить `Burger Courier` в переход `Dispatch`.

- [ ] **Step 3: Выдать роли и проверить профиль курьера**

`kitchen@…`: `Habibi Kitchen` + `Burger Kitchen`. `courier@…`: `Habibi Courier` + `Burger Courier`; проверить, что у курьера есть `Employee` с заполненным `user_id`.

- [ ] **Step 4: Быстрая проверка на проде**

Войти под обоими, пройти пункты 1–3 и 5–6 Задачи 9, Step 3 на одном тестовом заказе.
