# План: фронт ИИ-модуля, трассировка движка, локальная среда

> **Для агентов:** ОБЯЗАТЕЛЬНАЯ ПОД-СКИЛЛА: `superpowers:subagent-driven-development`
> (рекомендуется) или `superpowers:executing-plans`. Шаги отмечаются чекбоксами.

**Цель:** сделать ИИ-модуль отлаживаемым: движок отдаёт трассировку обработки,
локальная среда поднимается одной командой, чат живёт разделом в `habibi_ui`.

**Архитектура:** движок остаётся мозгом и получает необязательную трассировку в
ответе; `habibi_ai` остаётся питон-прокси и решает, кому трассировка положена;
`habibi_ui` получает раздел «ИИ», используя свою готовую оболочку; `habibi_docker`
получает скрипт, поднимающий все пять процессов.

**Стек:** Directus 12 + TypeScript (`@directus/extensions-sdk` 18, vitest),
Frappe/ERPNext version-16 (Python 3.14, unittest), React 19 + Vite 7 + Tailwind 4,
bash.

**Спек:** `habibi/specs/2026-09-07-habibi-ai-frontend-design.md`

## Глобальные ограничения

* Образ движка локально закреплён на `directus/directus:12.3.1` — как на проде.
  Более новый прогнал бы миграции на общей базе, и прод не поднялся бы.
* База движка — **продовая**, через SSH-туннель `127.0.0.1:15432`. Экспериментируй
  на тестовом боте и тестовом чате, не на чужой переписке.
* `tenant` берётся только из `frappe.local.site`, никогда из параметров запроса.
  Единственная точка построения фильтра — `habibi_ai.engine.scoped_filter`.
* Трассировка содержит system prompt. Флаг `debug` ставит прокси, не браузер.
* Тесты `habibi_ai/tests/test_engine.py` не импортируют frappe и гоняются
  без поднятия сайта. Имена тестов — по-русски, отступы — табы.
* `frontend/src/shared/types/api.ts` генерируется (`bench --site <site>
  habibi-ui generate-types`). Руками не править.
* Каждая задача заканчивается коммитом в своём репозитории.

---

# Фаза A. Трассировка в движке

Репозиторий: `habibi_ai_engine`. Среда: `./dev.sh up` + `cd extensions/ai && npm run dev`.
Локальный бенч для этой фазы не нужен, проверка идёт `curl`.

### Задача A1: Накопитель трассировки

**Файлы:**
- Создать: `extensions/ai/src/process-message/utils/trace.ts`
- Создать: `extensions/ai/src/process-message/utils/trace.test.ts`
- Изменить: `extensions/ai/package.json` (devDependency `vitest`, скрипт `test`)

**Интерфейсы:**
- Отдаёт: `class Trace` с `constructor(enabled: boolean)`, методами
  `add(step: string, data: Record<string, unknown>): void` и
  `result(): TraceStep[] | undefined`; тип `TraceStep = { step: string; data: Record<string, unknown> }`.

- [ ] **Шаг 1: Поставить vitest**

```bash
cd extensions/ai && npm install -D vitest
```

Дописать в `package.json` в `scripts`:

```json
"test": "vitest run"
```

- [ ] **Шаг 2: Написать падающий тест**

Создать `src/process-message/utils/trace.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest";
import { Trace } from "./trace";

describe("Trace", () => {
  it("выключенная не копит шаги", () => {
    const trace = new Trace(false);
    trace.add("router", { key: "greeting" });
    expect(trace.result()).toBeUndefined();
  });

  it("включённая возвращает шаги в порядке добавления", () => {
    const trace = new Trace(true);
    trace.add("router", { key: "greeting" });
    trace.add("stack", { before: [], after: ["greeting"] });
    expect(trace.result()).toEqual([
      { step: "router", data: { key: "greeting" } },
      { step: "stack", data: { before: [], after: ["greeting"] } },
    ]);
  });

  it("пишет в консоль независимо от флага", () => {
    // Логи остаются единственным источником, когда запрос упал до ответа,
    // поэтому флаг на них влиять не должен.
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    new Trace(false).add("router", { key: "greeting" });
    expect(spy).toHaveBeenCalledOnce();
    spy.mockRestore();
  });
});
```

- [ ] **Шаг 3: Убедиться, что тест падает**

Запустить: `npm test`
Ожидается: FAIL, `Failed to resolve import "./trace"`.

- [ ] **Шаг 4: Написать минимальную реализацию**

Создать `src/process-message/utils/trace.ts`:

```ts
export interface TraceStep {
  step: string;
  data: Record<string, unknown>;
}

/**
 * Накопитель шагов обработки.
 *
 * Пишет в консоль всегда, копит — только когда включён. Логи нужны сами по
 * себе: если запрос упал до формирования ответа, трассировки в ответе не будет
 * вовсе, а причина нужна.
 */
export class Trace {
  private steps: TraceStep[] = [];

  constructor(private readonly enabled: boolean) {}

  add(step: string, data: Record<string, unknown>): void {
    console.log(`[AI Process] ${step}`, JSON.stringify(data));
    if (this.enabled) {
      this.steps.push({ step, data });
    }
  }

  /** undefined, а не пустой массив: поле debug не должно появляться в ответе. */
  result(): TraceStep[] | undefined {
    return this.enabled ? this.steps : undefined;
  }
}
```

- [ ] **Шаг 5: Убедиться, что тесты проходят**

Запустить: `npm test`
Ожидается: PASS, 3 теста.

- [ ] **Шаг 6: Коммит**

```bash
git add extensions/ai/package.json extensions/ai/package-lock.json \
        extensions/ai/src/process-message/utils/trace.ts \
        extensions/ai/src/process-message/utils/trace.test.ts
git commit -m "feat(trace): накопитель шагов обработки и vitest"
```

---

### Задача A2: Трассировка в ответе эндпоинта

**Файлы:**
- Изменить: `extensions/ai/src/process-message/types.ts` (поле `debug` в `ProcessMessageRequest`)
- Изменить: `extensions/ai/src/process-message/index.ts` (весь обработчик)

**Интерфейсы:**
- Потребляет: `Trace`, `TraceStep` из `utils/trace`.
- Отдаёт: тело ответа `POST /ai-process-message/` получает необязательное поле
  `debug?: TraceStep[]`. Присутствует только когда в запросе было `debug: true`.

- [ ] **Шаг 1: Добавить поле в тип запроса**

В `src/process-message/types.ts` заменить:

```ts
export interface ProcessMessageRequest {
  chat_id: number;
  user_message: string;
  bot_id?: number;
}
```

на:

```ts
export interface ProcessMessageRequest {
  chat_id: number;
  user_message: string;
  bot_id?: number;
  /**
   * Вернуть трассировку обработки.
   *
   * Ставит прокси habibi_ai, а не браузер: трассировка содержит system prompt.
   * Движок наружу не публикуется, снаружи достижим только админкой, поэтому
   * флагу здесь можно доверять.
   */
  debug?: boolean;
}
```

- [ ] **Шаг 2: Завести Trace в обработчике**

В `src/process-message/index.ts` после разбора тела запроса заменить:

```ts
      const { chat_id, user_message, bot_id }: ProcessMessageRequest = req.body;
```

на:

```ts
      const { chat_id, user_message, bot_id, debug }: ProcessMessageRequest =
        req.body;
      const trace = new Trace(debug === true);
```

и добавить импорт рядом с остальными:

```ts
import { Trace } from "./utils/trace";
```

- [ ] **Шаг 3: Заменить логи обработчика на шаги трассировки**

Каждый `console.log("[AI Process] ...")` в `index.ts` заменить вызовом
`trace.add`. Соответствие — по спеку, раздел 3.1:

```ts
      // вместо console.log("[AI Process] Loaded chat state:", {...})
      trace.add("chat", {
        created: !chatExisted,
        bot_id: targetBotId,
        current_scenario: chat.current_scenario,
        scenario_stack: chat.scenario_stack || [],
        metadata: currentMetadata,
      });

      // вместо console.log("[AI Process] routerPrompt / Intent Router returned")
      trace.add("router", {
        prompt: routerPrompt + metadataString,
        raw: intentKey,
      });

      trace.add("stack", {
        before: chat.scenario_stack || [],
        after: updatedStack,
        key: newScenarioKey,
        max_stack: maxStack,
      });

      trace.add("scenario", {
        key: newScenarioKey,
        prompt_id: scenario.initial_prompt ?? null,
        scenario_metadata: scenarioMetadata,
        merged_metadata: mergedMetadata,
      });

      trace.add("completion", {
        system_prompt: finalSystemPrompt,
        sent: chatHistoryForAI.length,
        total: fullChatHistory.length,
        max_history_messages: maxHistoryMessages,
      });

      trace.add("auto_return", {
        triggered: assistantResponse.content !== finalContent,
        key: finalScenarioKey,
        stack: finalStack,
      });
```

Флаг `chatExisted` завести рядом с загрузкой чата:

```ts
      let chat = await chatService.getChatById(chat_id);
      const chatExisted = chat !== null;
```

- [ ] **Шаг 4: Отдать трассировку в ответе**

Заменить финальный `return res.json({...})` на:

```ts
      const steps = trace.result();
      return res.json({
        success: true,
        response: finalContent,
        scenario_key: finalScenarioKey,
        scenario_stack: finalStack,
        // Ключа debug нет вовсе, когда трассировка выключена: пустой массив
        // фронт принял бы за «шагов не было».
        ...(steps ? { debug: steps } : {}),
      });
```

- [ ] **Шаг 5: Проверить сборку и типы**

Запустить: `npm run build`
Ожидается: сборка проходит без ошибок TypeScript.

- [ ] **Шаг 6: Проверить эндпоинт вживую**

Среда: `./dev.sh up` в корне репозитория. Токен — сервисной роли, из админки
`http://localhost:8055`. `<chat>` — номер **тестового** чата.

```bash
curl -s -X POST http://localhost:8055/ai-process-message/ \
  -H "Authorization: Bearer <токен>" -H "Content-Type: application/json" \
  -d '{"chat_id": <chat>, "user_message": "привет", "debug": true}' | jq '.debug[].step'
```

Ожидается: `"chat"`, `"router"`, `"stack"`, `"scenario"`, `"completion"`, `"auto_return"`.

Тот же запрос без `"debug": true` — поля `debug` в ответе нет:

```bash
curl -s -X POST http://localhost:8055/ai-process-message/ \
  -H "Authorization: Bearer <токен>" -H "Content-Type: application/json" \
  -d '{"chat_id": <chat>, "user_message": "привет"}' | jq 'has("debug")'
```

Ожидается: `false`.

- [ ] **Шаг 8: Коммит**

```bash
git add extensions/ai/src/process-message/types.ts \
        extensions/ai/src/process-message/index.ts
git commit -m "feat(trace): трассировка обработки в ответе эндпоинта"
```

---

### Задача A3: Документация движка

**Файлы:**
- Изменить: `README.md` (раздел про проверку кейса)
- Изменить: `extensions/ai/README.md` (раздел Response)

- [ ] **Шаг 1: Описать трассировку в README расширения**

В `extensions/ai/README.md` после блока `### Response` дописать:

```markdown
### Трассировка

`"debug": true` в теле запроса добавляет в ответ массив `debug` с шагами
обработки: `chat`, `router`, `stack`, `scenario`, `completion`, `auto_return`.
В `completion` лежит финальный system prompt целиком.

Флаг ставит прокси `habibi_ai`, а не браузер: system prompt — интеллектуальная
собственность владельца инсталляции, тенант не должен уметь его запросить.
```

- [ ] **Шаг 2: Дописать пример в корневой README**

В `README.md`, в блоке «Проверка кейса», после существующего `curl` добавить:

```markdown
С трассировкой — видно, что решил роутер и какой промпт собрался:

```bash
curl -s -X POST http://localhost:8055/ai-process-message/ \
  -H "Authorization: Bearer <токен>" -H "Content-Type: application/json" \
  -d '{"chat_id": 1, "user_message": "привет", "debug": true}' | jq .debug
```
```

- [ ] **Шаг 3: Коммит**

```bash
git add README.md extensions/ai/README.md
git commit -m "docs: трассировка обработки"
```

---

# Фаза B. Локальная среда

Репозитории: `habibi_docker` (задачи B1–B3), `habibi_ui` (задача B4).

### Задача B1: Контейнер бенча видит соседние репозитории

Эта задача содержит **проверку риска**: работает ли bench с приложением,
подключённым симлинком. Если нет — весь `dev.sh init` строился бы на неверном
допущении, поэтому проверка идёт первой.

**Файлы:**
- Изменить: `devcontainer-example/docker-compose.yml`

- [ ] **Шаг 1: Добавить монты соседних репозиториев**

В `devcontainer-example/docker-compose.yml`, сервис `frappe`, заменить:

```yaml
    volumes:
      - ..:/workspace:cached
```

на:

```yaml
    volumes:
      - ..:/workspace:cached
      # Соседние репозитории лежат рядом с habibi_docker на хосте, а внутрь
      # смонтирован только он сам. Без этих строк bench их не видит и ставить
      # приложения не из чего. Монт идёт в repos/, а не в apps/: bench init
      # создаёт frappe-bench с нуля и непустой apps/ его смущает — симлинки
      # навешиваются после, в habibi/dev.sh init.
      - ../../habibi_ui:/workspace/repos/habibi_ui:cached
      - ../../habibi_ai:/workspace/repos/habibi_ai:cached
```

- [ ] **Шаг 2: Пересоздать девконтейнер и убедиться, что репозитории видны**

```bash
cd /Users/fsa/Projects/habibi/habibi_docker
rm -rf .devcontainer && cp -R devcontainer-example .devcontainer
docker compose -f .devcontainer/docker-compose.yml up -d
docker compose -f .devcontainer/docker-compose.yml exec frappe ls /workspace/repos
```

Ожидается: `habibi_ai` и `habibi_ui`.

- [ ] **Шаг 3: Проверить риск — bench и симлинк**

Одноразовая проверка на выброс, до написания `dev.sh init`:

```bash
docker compose -f .devcontainer/docker-compose.yml exec frappe bash -lc '
  cd /workspace/development &&
  bench init --skip-redis-config-generation --frappe-branch version-16 risk-check &&
  cd risk-check &&
  ln -s /workspace/repos/habibi_ui apps/habibi_ui &&
  echo habibi_ui >> sites/apps.txt &&
  bench pip install -e apps/habibi_ui &&
  python -c "import frappe; print(frappe.get_app_path(\"habibi_ui\"))"
'
```

Ожидается: путь вида `/workspace/development/risk-check/apps/habibi_ui/habibi_ui`.

**Если шаг упал** — симлинк не годится. Запасной вариант: монтировать
репозитории прямо в `apps/`, а `bench init` запускать с уже существующим
непустым `apps/` через `bench init --ignore-exist`. Зафиксируй, что именно
упало, в этой задаче и правь `dev.sh init` под запасной вариант.

> **Результат проверки (2026-09-07): симлинк работает.** `get_app_path`,
> импорт пакета и чтение `hooks` — все три разрешаются в хостовый путь
> `/workspace/repos/habibi_ui/habibi_ui`. Запасной вариант не понадобился.
>
> Побочно выяснилось, что `sites/apps.txt` после `bench init` не имеет
> завершающего перевода строки, и наивный `echo >>` склеивает записи. Учтено
> в задаче B2.

Убрать проверочный бенч:

```bash
docker compose -f .devcontainer/docker-compose.yml exec frappe rm -rf /workspace/development/risk-check
```

- [ ] **Шаг 4: Коммит**

```bash
git add devcontainer-example/docker-compose.yml
git commit -m "feat(dev): девконтейнер видит соседние репозитории"
```

---

### Задача B2: habibi/dev.sh init

**Файлы:**
- Создать: `habibi/dev.sh`

**Интерфейсы:**
- Отдаёт: `./habibi/dev.sh init` — идемпотентная разовая подготовка среды.
  Переменные `SITE=dev.localhost`, `BENCH=development/frappe-bench`,
  `DC="docker compose -f .devcontainer/docker-compose.yml"` — задача B3
  использует те же.

- [ ] **Шаг 1: Создать скрипт с командой init**

Создать `habibi/dev.sh`:

```bash
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

  # Существование site_config.json говорит, что new-site стартовал, но не что
  # он доехал: конфиг пишется ДО установки приложений, и они ставятся по
  # одному. Упавшая установка оставила бы сайт без приложения навсегда —
  # проверка выше пропускала бы его молча. Поэтому доустанавливаем
  # недостающее на каждом прогоне.
  #
  # Здесь разбирается вывод команды, хотя выше мы от этого ушли: у списка
  # приложений САЙТА файлового источника истины нет, он живёт в его БД.
  for app in erpnext "${APPS[@]}"; do
    in_bench "cd /workspace/$BENCH &&
      bench --site $SITE list-apps | grep -q \"^$app \" ||
      bench --site $SITE install-app $app"
  done

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
```

- [ ] **Шаг 2: Сделать исполняемым**

```bash
chmod +x habibi/dev.sh
```

- [ ] **Шаг 3: Прогнать init начисто**

```bash
./habibi/dev.sh init
```

Ожидается: подсказка в конце, без ошибок. Первый прогон долгий — `bench init`
и `new-site`.

- [ ] **Шаг 4: Проверить идемпотентность**

```bash
./habibi/dev.sh init
```

Ожидается: тот же вывод, ничего не пересоздаётся, ошибок нет.

- [ ] **Шаг 5: Проверить, что приложения на сайте**

```bash
docker compose -f .devcontainer/docker-compose.yml exec -T frappe bash -lc \
  "cd /workspace/development/frappe-bench && bench --site dev.localhost list-apps"
```

Ожидается: `frappe`, `erpnext`, `habibi_ui`, `habibi_ai`.

- [ ] **Шаг 6: Коммит**

```bash
git add habibi/dev.sh
git commit -m "feat(dev): habibi/dev.sh init — разовая подготовка среды"
```

---

### Задача B3: habibi/dev.sh up, down, logs

**Файлы:**
- Изменить: `habibi/dev.sh`
- Изменить: `.gitignore` (каталог логов)

**Интерфейсы:**
- Потребляет: переменные `SITE`, `BENCH`, `DC`, `LOGS`, функцию `in_bench` из задачи B2.
- Отдаёт: `up`, `down`, `logs <движок|вотчер|бенч|vite>`.

- [ ] **Шаг 1: Добавить команды в скрипт**

В `habibi/dev.sh` перед блоком `case` вставить:

```bash
ENGINE=../habibi_ai_engine
UI=../habibi_ui

# Фоновый процесс с логом и pid-файлом. Вотчер расширения и vite держат
# терминал занятым, а процессов здесь пять — пять окон это ровно то, от чего
# скрипт должен избавлять.
background() {
  local name=$1 dir=$2 cmd=$3
  if [ -f "$LOGS/$name.pid" ] && kill -0 "$(cat "$LOGS/$name.pid")" 2>/dev/null; then
    echo "==> $name уже запущен (pid $(cat "$LOGS/$name.pid"))"
    return
  fi
  mkdir -p "$LOGS"
  (cd "$dir" && exec bash -lc "$cmd") > "$LOGS/$name.log" 2>&1 &
  echo $! > "$LOGS/$name.pid"
  echo "==> $name запущен (pid $!), лог $LOGS/$name.log"
}

stop_background() {
  local name=$1
  [ -f "$LOGS/$name.pid" ] || return 0
  kill "$(cat "$LOGS/$name.pid")" 2>/dev/null || true
  rm -f "$LOGS/$name.pid"
  echo "==> $name остановлен"
}

cmd_up() {
  need_siblings
  [ -d "$BENCH" ] || { echo "бенча нет — сначала ./habibi/dev.sh init" >&2; exit 1; }

  # Движок поднимает свой скрипт: у него своя логика туннеля и сборки .env.dev
  # с сервера, второй копии ей не нужно.
  (cd "$ENGINE" && ./dev.sh up)

  $DC up -d
  background вотчер "$ENGINE/extensions/ai" "npm run dev"
  background бенч "." "$DC exec -T frappe bash -lc 'cd /workspace/$BENCH && bench start'"
  background vite "$UI" "yarn dev"

  cat <<'READY'

==> готово:
    фронт с HMR   http://localhost:5173/ui
    бенч          http://localhost:8000
    админка движка http://localhost:8055
READY
}

cmd_down() {
  stop_background vite
  stop_background бенч
  stop_background вотчер
  $DC down
  (cd "$ENGINE" && ./dev.sh down)
}

cmd_logs() {
  local name=${1:-}
  case "$name" in
    движок) (cd "$ENGINE" && ./dev.sh logs) ;;
    вотчер|бенч|vite) tail -f "$LOGS/$name.log" ;;
    *) echo "usage: $0 logs {движок|вотчер|бенч|vite}" >&2; exit 1 ;;
  esac
}
```

и заменить блок `case` на:

```bash
case "${1:-up}" in
  init)   cmd_init ;;
  up)     cmd_up ;;
  down)   cmd_down ;;
  logs)   shift; cmd_logs "$@" ;;
  *)      echo "usage: $0 {init|up|down|logs}" >&2; exit 1 ;;
esac
```

- [ ] **Шаг 2: Не коммитить логи**

Дописать в `.gitignore`:

```
# Логи фоновых процессов локальной среды (habibi/dev.sh)
.dev-logs/
```

- [ ] **Шаг 3: Бенч должен отвечать на любой Host**

Frappe мультиарендный: сайт он выбирает по заголовку `Host`. Браузер на
`http://localhost:8000` и прокси vite шлют `Host: localhost`, сайта с таким
именем нет, и бенч отвечает `404 "localhost does not exist"` — даже когда порт
опубликован и соединение проходит.

Лечится не заголовком в прокси, а конфигурацией бенча: с заголовком починился бы
только vite, а браузер, открывающий `localhost:8000` напрямую, продолжал бы
получать 404.

В `habibi/dev.sh`, в `cmd_init`, внутрь блока создания сайта — сразу после
`developer_mode`:

```bash
    # Frappe выбирает сайт по заголовку Host, а браузер и прокси vite шлют
    # Host: localhost. Без этих двух ключей бенч отвечает 404 "localhost does
    # not exist" на любой запрос с хоста, хотя порт опубликован и соединение
    # проходит. Лечить заголовком в прокси нельзя: починился бы только vite,
    # а прямое открытие localhost:8000 в браузере — нет.
    in_bench "cd /workspace/$BENCH &&
      bench set-config -g default_site $SITE &&
      bench set-config -g serve_default_site true"
```

Проверяется тем, что `curl` **без** заголовка `Host` получает ответ:

```bash
curl -s http://localhost:8000/api/method/ping
```

Ожидается: `{"message":"pong"}`.

- [ ] **Шаг 4: Опубликовать порты бенча наружу**

`.devcontainer/docker-compose.yml` не публикует ни одного порта — в файле стоит
комментарий «Development ports are forwarded by devcontainer.json». Этот проброс
работает, только когда контейнер открывает VS Code. `habibi/dev.sh` поднимает
его обычным `docker compose`, поэтому наружу не выходит ничего: ни сайт в
браузере, ни прокси vite из задачи B4 до бенча не достучатся.

В `devcontainer-example/docker-compose.yml`, сервис `frappe`, добавить:

```yaml
    ports:
      # forwardPorts в devcontainer.json срабатывает только под VS Code, а
      # habibi/dev.sh поднимает контейнер обычным docker compose. Без явной
      # публикации сайт недоступен с хоста, и прокси vite упирается в пустоту.
      # Слушаем на loopback, как это делает compose.dev.yaml движка.
      - "127.0.0.1:8000:8000"
      - "127.0.0.1:9000:9000"
```

`.devcontainer/` — копия примера, и `cmd_init` копирует его только когда каталога
нет. У того, кто уже поднимал среду, копия останется старой и без портов, молча.
Поэтому в `habibi/dev.sh` в `cmd_init`, сразу после блока копирования, добавить
предупреждение о расхождении:

```bash
  # Копия не перезаписывается: .devcontainer в .gitignore именно чтобы его
  # правили под себя. Но расхождение с примером означает потерянные монты или
  # порты, и молчать об этом нельзя — цена в полчаса на поиск причины.
  if ! diff -q devcontainer-example/docker-compose.yml .devcontainer/docker-compose.yml >/dev/null; then
    echo "!!! .devcontainer/docker-compose.yml разошёлся с devcontainer-example/" >&2
    echo "    свежие монты и порты могут отсутствовать; сверьте: diff devcontainer-example/docker-compose.yml .devcontainer/docker-compose.yml" >&2
  fi
```

Затем пересобрать копию и пересоздать контейнеры, чтобы порты вступили в силу:

```bash
cp devcontainer-example/docker-compose.yml .devcontainer/docker-compose.yml
docker compose -f .devcontainer/docker-compose.yml up -d
docker compose -f .devcontainer/docker-compose.yml ps --format '{{.Service}}\t{{.Ports}}'
```

Ожидается: у `frappe` в колонке портов `127.0.0.1:8000->8000/tcp` и `9000->9000/tcp`.

- [ ] **Шаг 5: Поднять среду**

```bash
./habibi/dev.sh up
```

Ожидается: блок «готово» с тремя адресами, без ошибок.

- [ ] **Шаг 6: Проверить, что все процессы живы**

```bash
# /server/health у Directus закрыт настройками по умолчанию и отвечает 403 —
# живость проверяем /server/ping.
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8055/server/ping
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8000/api/method/ping
tail -3 .dev-logs/вотчер.log
```

Ожидается: `200`, `200`, и в логе вотчера строка о собранном расширении.

Второй запрос проходит только после шагов 3 и 4: без публикации портов бенч с
хоста недостижим, а без default_site отвечает 404 на Host: localhost.

- [ ] **Шаг 7: Проверить остановку**

```bash
./habibi/dev.sh down
docker ps --format '{{.Names}}' | grep -c 'frappe\|ai-engine' || true
```

Ожидается: `0`.

- [ ] **Шаг 7: Коммит**

```bash
git add habibi/dev.sh .gitignore devcontainer-example/docker-compose.yml
git commit -m "feat(dev): dev.sh up, down, logs — пять процессов одной командой"
```

---

### Задача B4: HMR фронта против локального бенча

**Файлы:**
- Изменить: `habibi_ui/api/v1/session.py` (метод `boot`)
- Изменить: `habibi_ui/tests/test_session.py`
- Изменить: `frontend/vite.config.ts` (`server.proxy`)
- Изменить: `frontend/src/main.tsx` (подстановка `window.habibi` в dev)

Репозиторий: `habibi_ui`.

**Интерфейсы:**
- Отдаёт: `habibi_ui.api.v1.session.boot()` — whitelisted, доступен по GET,
  возвращает `{"csrf_token": str, "user": str, "desk_theme": str}` — тот же
  состав, что `habibi_boot` в `www/ui.py`.

- [ ] **Шаг 1: Написать падающий тест**

В `habibi_ui/tests/test_session.py` дописать:

```python
from habibi_ui.api.v1.session import boot, me


class TestSessionBoot(IntegrationTestCase):
	def test_отдаёт_тот_же_состав_что_страница_обёртка(self):
		frappe.set_user("Administrator")
		result = boot()
		self.assertEqual(set(result), {"csrf_token", "user", "desk_theme"})
		self.assertEqual(result["user"], "Administrator")
		self.assertTrue(result["csrf_token"])

	def test_гость_отвергается(self):
		self.addCleanup(frappe.set_user, "Administrator")
		frappe.set_user("Guest")
		with self.assertRaises(frappe.PermissionError):
			boot()
```

Существующую строку `from habibi_ui.api.v1.session import me` заменить на
импорт выше.

- [ ] **Шаг 2: Убедиться, что тест падает**

```bash
docker compose -f ../habibi_docker/.devcontainer/docker-compose.yml exec -T frappe bash -lc \
  "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module habibi_ui.tests.test_session"
```

Ожидается: FAIL, `ImportError: cannot import name 'boot'`.

- [ ] **Шаг 3: Написать реализацию**

В `habibi_ui/api/v1/session.py` дописать импорт и метод:

```python
import frappe.sessions
```

```python
@frappe.whitelist(methods=["GET"])
def boot() -> dict:
	"""То же, что страница-обёртка кладёт в window.habibi.

	Нужен только vite dev server: под ним index.html отдаёт сам vite, а не
	www/ui.html, и подставить boot в разметку некому. Метод доступен по GET
	намеренно — CSRF-токен нельзя получить запросом, который сам его требует.
	Ничего сверх того, что обёртка и так отдаёт этому же пользователю, здесь
	не появляется.
	"""
	if frappe.session.user == "Guest":
		frappe.throw(_("Требуется вход"), frappe.PermissionError)

	return {
		"csrf_token": frappe.sessions.get_csrf_token(),
		"user": frappe.session.user,
		"desk_theme": frappe.db.get_value("User", frappe.session.user, "desk_theme") or "",
	}
```

- [ ] **Шаг 4: Убедиться, что тесты проходят**

Та же команда, что в шаге 2.
Ожидается: PASS.

- [ ] **Шаг 5: Добавить прокси в vite**

В `frontend/vite.config.ts`, в объект `defineConfig`, добавить перед `build`:

```ts
  // Под vite страница живёт на :5173, а бенч на :8000. Куку сессии браузер
  // отдаёт обоим — она привязана к хосту localhost, а не к порту, — но
  // запросы всё равно надо довести до бенча, иначе они уйдут в vite.
  server: {
    proxy: {
      "/api": "http://localhost:8000",
      "/assets": "http://localhost:8000",
      "/files": "http://localhost:8000",
    },
  },
```

- [ ] **Шаг 6: Подставить window.habibi в dev**

В `frontend/src/main.tsx` заменить блок рендера на:

```tsx
async function bootstrap() {
  // В проде window.habibi кладёт www/ui.html. Под vite разметку отдаёт vite,
  // и boot приходится добирать запросом.
  if (!window.habibi) {
    const response = await fetch("/api/method/habibi_ui.api.v1.session.boot");
    if (!response.ok) {
      throw new Error("Не удалось получить boot — войдите на http://localhost:8000/login");
    }
    window.habibi = (await response.json()).message;
  }

  createRoot(container).render(
    <StrictMode>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter basename="/ui">
          <App />
        </BrowserRouter>
      </QueryClientProvider>
    </StrictMode>,
  );
}

void bootstrap();
```

- [ ] **Шаг 7: Проверить HMR вживую**

Среда: `../habibi_docker/habibi/dev.sh up`. Войти на `http://localhost:8000/login`
(Administrator / admin), затем открыть `http://localhost:5173/ui`.

Ожидается: лаунчер с плитками, в консоли браузера нет ошибок 403.
Правка текста в `frontend/src/shared/ui/Launcher.tsx` видна без перезагрузки.

- [ ] **Шаг 8: Коммит**

```bash
git add habibi_ui/api/v1/session.py habibi_ui/tests/test_session.py \
        frontend/vite.config.ts frontend/src/main.tsx
git commit -m "feat(dev): HMR фронта против локального бенча"
```

---

# Фаза C. Методы habibi_ai

Репозиторий: `habibi_ai`. Быстрые тесты: `python -m unittest habibi_ai.tests.test_engine -v`.

### Задача C1: Роль и гейт на трассировку

**Файлы:**
- Изменить: `habibi_ai/engine.py` (`EngineClient.send_message`)
- Изменить: `habibi_ai/api.py` (константа роли, проброс флага)
- Изменить: `habibi_ai/hooks.py` (фикстура роли)
- Создать: `habibi_ai/fixtures/role.json`
- Изменить: `habibi_ai/tests/test_engine.py`

**Интерфейсы:**
- Отдаёт: `EngineClient.send_message(chat_id, message, bot_id=None, debug=False)`
  — при `debug=True` кладёт `"debug": True` в тело запроса к движку.
  `habibi_ai.api.DEBUG_ROLE = "Habibi AI Debug"`.

- [ ] **Шаг 1: Написать падающий тест**

В `habibi_ai/tests/test_engine.py` дописать класс:

```python
class TestSendMessageDebug(unittest.TestCase):
	def _client(self):
		client = EngineClient("http://engine", "token", "naqwa.habibi-erp.com")
		client.get_chat = Mock(return_value={"id": 7})
		client._post = Mock(return_value={"response": "ок"})
		return client

	def test_без_флага_поле_debug_не_уходит(self):
		client = self._client()
		client.send_message(7, "привет")
		_, payload = client._post.call_args[0]
		self.assertNotIn("debug", payload)

	def test_с_флагом_поле_debug_уходит(self):
		client = self._client()
		client.send_message(7, "привет", debug=True)
		_, payload = client._post.call_args[0]
		self.assertTrue(payload["debug"])
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```bash
python -m unittest habibi_ai.tests.test_engine.TestSendMessageDebug -v
```

Ожидается: FAIL, `send_message() got an unexpected keyword argument 'debug'`.

- [ ] **Шаг 3: Прокинуть флаг в клиенте**

В `habibi_ai/engine.py` заменить метод:

```python
	def send_message(self, chat_id, message, bot_id=None, debug=False):
		"""Отправка сообщения в движок.

		get_chat вызывается ДО обращения к движку намеренно: сам endpoint
		ai-process-message о тенантах ничего не знает, и без этой проверки
		номер чужого чата ушёл бы в него в обход фильтра.

		debug решает вызывающий, а не клиент: трассировка содержит system
		prompt, и право на неё — вопрос ролей, о которых engine.py не знает.
		"""
		self.get_chat(chat_id)
		payload = {"chat_id": chat_id, "user_message": message}
		if bot_id is not None:
			payload["bot_id"] = bot_id
		if debug:
			payload["debug"] = True
		return self._post("ai-process-message", payload)
```

- [ ] **Шаг 4: Убедиться, что тесты проходят**

```bash
python -m unittest habibi_ai.tests.test_engine -v
```

Ожидается: PASS, все тесты.

- [ ] **Шаг 5: Завести роль и гейт**

В `habibi_ai/api.py` после блока `KNOWN_ERRORS` добавить:

```python
# Кому положена трассировка обработки. Она содержит system prompt — это
# интеллектуальная собственность владельца инсталляции, а не тенанта, поэтому
# право отдельное и по умолчанию его нет ни у кого.
DEBUG_ROLE = "Habibi AI Debug"
```

и заменить метод:

```python
@frappe.whitelist()
def send_message(chat_id, message, bot_id=None):
	"""Флаг трассировки ставит сервер, а не клиент.

	В теле запроса от браузера поля debug нет вообще — ровно так же, как там
	нет tenant. Иначе трассировку мог бы запросить любой пользователь тенанта.
	"""
	debug = DEBUG_ROLE in frappe.get_roles()
	return call(get_client().send_message, int(chat_id), message, bot_id, debug=debug)
```

- [ ] **Шаг 6: Роль приезжает фикстурой**

Создать `habibi_ai/fixtures/role.json`:

```json
[
 {
  "desk_access": 0,
  "docstatus": 0,
  "doctype": "Role",
  "name": "Habibi AI Debug",
  "role_name": "Habibi AI Debug"
 }
]
```

В `habibi_ai/hooks.py` после блока `after_migrate` добавить:

```python
# Роль-переключатель трассировки приезжает фикстурой: без неё в api.py
# ссылка на несуществующую роль, и выдать право некому.
fixtures = [
	{"dt": "Role", "filters": [["name", "in", ["Habibi AI Debug"]]]},
]
```

- [ ] **Шаг 7: Проверить на сайте**

```bash
docker compose -f ../habibi_docker/.devcontainer/docker-compose.yml exec -T frappe bash -lc \
  "cd /workspace/development/frappe-bench && bench --site dev.localhost migrate &&
   bench --site dev.localhost execute frappe.client.get_list --kwargs \"{'doctype':'Role','filters':{'name':'Habibi AI Debug'}}\""
```

Ожидается: список с одной записью.

- [ ] **Шаг 8: Коммит**

```bash
git add habibi_ai/engine.py habibi_ai/api.py habibi_ai/hooks.py \
        habibi_ai/fixtures/role.json habibi_ai/tests/test_engine.py
git commit -m "feat: трассировка обработки по роли Habibi AI Debug"
```

---

### Задача C2: Список чатов с заголовком и превью

**Файлы:**
- Изменить: `habibi_ai/engine.py` (`list_chats`, новый `_previews`)
- Изменить: `habibi_ai/tests/test_engine.py`

**Интерфейсы:**
- Отдаёт: `EngineClient.list_chats(external_user)` возвращает список словарей
  с полями `id`, `bot_id`, `current_scenario`, `title`, `preview`. `title` —
  первое сообщение пользователя, `preview` — последнее сообщение в чате,
  оба обрезаны до 60 символов. Пустой чат даёт `title=""`, `preview=""`.

- [ ] **Шаг 1: Написать падающий тест**

В `habibi_ai/tests/test_engine.py` дописать:

```python
class TestListChatsPreview(unittest.TestCase):
	def _client(self, chats, messages):
		client = EngineClient("http://engine", "token", "naqwa.habibi-erp.com")
		client._items = Mock(side_effect=[chats, messages])
		return client

	def test_заголовок_из_первого_сообщения_пользователя(self):
		client = self._client(
			[{"id": 7, "bot_id": 1, "current_scenario": None}],
			[
				{"chat_id": 7, "role": "user", "content": "хочу курс"},
				{"chat_id": 7, "role": "assistant", "content": "какой именно?"},
			],
		)
		(chat,) = client.list_chats("user@example.com")
		self.assertEqual(chat["title"], "хочу курс")
		self.assertEqual(chat["preview"], "какой именно?")

	def test_длинный_заголовок_обрезается(self):
		client = self._client(
			[{"id": 7, "bot_id": 1, "current_scenario": None}],
			[{"chat_id": 7, "role": "user", "content": "я" * 100}],
		)
		(chat,) = client.list_chats("user@example.com")
		self.assertEqual(len(chat["title"]), 60)

	def test_пустой_чат_не_ломает_список(self):
		client = self._client([{"id": 7, "bot_id": 1, "current_scenario": None}], [])
		(chat,) = client.list_chats("user@example.com")
		self.assertEqual(chat["title"], "")
		self.assertEqual(chat["preview"], "")

	def test_без_чатов_за_сообщениями_не_ходим(self):
		# Пустой _in дал бы Directus фильтр, под который не попадает ничего,
		# то есть лишний запрос ради заведомо пустого ответа.
		client = EngineClient("http://engine", "token", "naqwa.habibi-erp.com")
		client._items = Mock(return_value=[])
		self.assertEqual(client.list_chats("user@example.com"), [])
		self.assertEqual(client._items.call_count, 1)
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```bash
python -m unittest habibi_ai.tests.test_engine.TestListChatsPreview -v
```

Ожидается: FAIL, `KeyError: 'title'`.

- [ ] **Шаг 3: Написать реализацию**

В `habibi_ai/engine.py` рядом с `TIMEOUT` добавить:

```python
# Длина заголовка и превью в списке чатов. Названия у чата нет: поля под него в
# customer_chats не существует, а заводить его в общей продовой схеме ради
# подписи в списке — дороже, чем достать из сообщений.
EXCERPT = 60
```

и заменить `list_chats`:

```python
	def list_chats(self, external_user):
		"""Чаты тенанта, заведённые этим пользователем, с подписью."""
		chats = self._items(
			"customer_chats",
			{
				"filter": scoped_filter(self.tenant, {"external_user": {"_eq": external_user}}),
				"fields": "id,bot_id,current_scenario",
				"sort": "-id",
			},
		)
		if not chats:
			return []

		previews = self._previews([chat["id"] for chat in chats])
		for chat in chats:
			chat.update(previews.get(chat["id"], {"title": "", "preview": ""}))
		return chats

	def _previews(self, chat_ids):
		"""Заголовок и превью для каждого чата одним запросом.

		Один запрос на все чаты, а не по запросу на чат: список открывается на
		каждый заход в раздел, и N+1 здесь виден глазом.
		"""
		messages = self._items(
			"chat_messages",
			{
				"filter": scoped_filter(self.tenant, {"chat_id": {"_in": chat_ids}}),
				"fields": "chat_id,role,content,sort",
				"sort": "chat_id,sort",
				"limit": -1,
			},
		)

		result = {}
		for message in messages:
			entry = result.setdefault(message["chat_id"], {"title": "", "preview": ""})
			content = (message.get("content") or "")[:EXCERPT]
			if not entry["title"] and message.get("role") == "user":
				entry["title"] = content
			entry["preview"] = content
		return result
```

- [ ] **Шаг 4: Убедиться, что тесты проходят**

```bash
python -m unittest habibi_ai.tests.test_engine -v
```

Ожидается: PASS, все тесты.

- [ ] **Шаг 5: Коммит**

```bash
git add habibi_ai/engine.py habibi_ai/tests/test_engine.py
git commit -m "feat: список чатов с заголовком и превью"
```

---

### Задача C3: Демонтаж desk-страницы

Две реализации одного экрана расходятся всегда, а чинить будут ту, что
попалась под руку. Страница уходит вместе со всей цепочкой, которая на неё
ссылается: Desktop Icon → Workspace Sidebar → shortcut → Page.

**Файлы:**
- Удалить: `habibi_ai/habibi_ai/page/ai_chat/` целиком
- Изменить: `habibi_ai/habibi_ai/workspace/habibi_ai/habibi_ai.json` (убрать shortcut)
- Изменить: `habibi_ai/setup.py` (снос устаревшей Desktop Icon)
- Изменить: `habibi_ai/hooks.py` (`required_apps`)
- Изменить: `README.md`

- [ ] **Шаг 1: Удалить страницу**

```bash
git rm -r habibi_ai/habibi_ai/page/ai_chat
```

- [ ] **Шаг 2: Убрать shortcut из workspace**

В `habibi_ai/habibi_ai/workspace/habibi_ai/habibi_ai.json`:
* `"shortcuts"` — заменить массив на `[]`;
* в `"content"` убрать блок с `"id":"ha_shortcut"`, оставив только заголовок:

```json
 "content": "[{\"id\":\"ha_header\",\"type\":\"header\",\"data\":{\"text\":\"<span class=\\\"h4\\\">Habibi AI</span>\",\"col\":12}}]",
```

- [ ] **Шаг 3: Снести устаревшую плитку**

В `habibi_ai/setup.py` заменить `ensure_desktop_icon` на `drop_desktop_icon` и
поправить вызовы:

```python
"""Демонтаж плитки модуля в Desk.

Чат живёт разделом в habibi_ui (/ui/ai), а не страницей Desk. Плитка Desktop
Icon вела на удалённую страницу ai-chat, поэтому её надо убрать — иначе на
сайтах, где модуль уже стоял, в лаунчере остаётся ссылка в пустоту.
"""

import frappe

WORKSPACE = "Habibi AI"


def after_install():
	drop_desktop_icon()


def after_migrate():
	drop_desktop_icon()


def drop_desktop_icon():
	"""Идемпотентно: after_migrate вызывается при каждой миграции сайта."""
	if frappe.db.exists("Desktop Icon", WORKSPACE):
		frappe.delete_doc("Desktop Icon", WORKSPACE, ignore_permissions=True)
```

- [ ] **Шаг 4: Объявить зависимость от оболочки**

В `habibi_ai/hooks.py` после `app_license` добавить:

```python
# Интерфейс модуля — раздел в habibi_ui (/ui/ai). Своей страницы в Desk у него
# больше нет, поэтому без оболочки ставить его некуда.
required_apps = ["habibi_ui"]
```

- [ ] **Шаг 5: Поправить README**

В `README.md` заменить первый абзац:

```markdown
ИИ-модуль habibi: раздел «ИИ» в интерфейсе `habibi_ui` поверх движка Directus.

Ставится тенанту выборочно, как `habibi_ui`, через `saas_bridge` →
`/app/site-manager` → Site apps. Движок живёт отдельно
(`DHI-Partners/habibi_ai_engine`), один на инсталляцию. Исходники раздела —
в `habibi_ui/frontend/src/features/ai`, здесь только серверная часть.
```

- [ ] **Шаг 6: Проверить, что миграция проходит**

```bash
docker compose -f ../habibi_docker/.devcontainer/docker-compose.yml exec -T frappe bash -lc \
  "cd /workspace/development/frappe-bench && bench --site dev.localhost migrate &&
   bench --site dev.localhost execute frappe.client.get_count --kwargs \"{'doctype':'Desktop Icon','filters':{'name':'Habibi AI'}}\""
```

Ожидается: миграция без ошибок, счётчик `0`.

- [ ] **Шаг 7: Коммит**

```bash
git add -A
git commit -m "refactor: чат уезжает в habibi_ui, desk-страница удалена"
```

---

# Фаза D. Раздел ИИ в habibi_ui

Репозиторий: `habibi_ui`. Среда: `../habibi_docker/habibi/dev.sh up`,
фронт на `http://localhost:5173/ui`.

Отступление от спека, раздел 4: `ChatLog.tsx` и `Composer.tsx` отдельными
файлами не заводятся. Лента и поле ввода — это по десятку строк разметки без
собственного состояния; вынесенные в файлы, они дали бы три файла и два набора
пропсов там, где хватает одного компонента. Разделение вернуть, если у ленты
появится своя логика — подгрузка истории, редактирование, вложения.

Цвета берутся классами Tailwind (`border-border`, `bg-muted`, `bg-card`), а не
`var(--border)`: `theme.css` регистрирует токены как `--color-*`, и остальной
интерфейс написан классами.

### Задача D1: Модуль виден, только когда установлен

**Файлы:**
- Изменить: `habibi_ui/api/v1/session.py` (`MODULE_LABELS`)
- Изменить: `habibi_ui/tests/test_session.py`

**Интерфейсы:**
- Отдаёт: `me()["modules"]` содержит `{"key": "habibi_ai", "label": "ИИ"}`,
  когда приложение установлено на сайте.

- [ ] **Шаг 1: Написать падающий тест**

В `habibi_ui/tests/test_session.py`, в класс `TestSessionMe`, дописать:

```python
	def test_ии_модуль_виден_когда_установлен(self):
		# habibi_ai стоит на dev-сайте; на сайтах без него ключа быть не должно,
		# и это единственное, чем управляется доступность раздела в интерфейсе.
		result = me()
		keys = [m["key"] for m in result["modules"]]
		self.assertEqual("habibi_ai" in keys, "habibi_ai" in frappe.get_installed_apps())
```

- [ ] **Шаг 2: Убедиться, что тест падает**

```bash
docker compose -f ../habibi_docker/.devcontainer/docker-compose.yml exec -T frappe bash -lc \
  "cd /workspace/development/frappe-bench && bench --site dev.localhost run-tests --module habibi_ui.tests.test_session"
```

Ожидается: FAIL — `habibi_ai` установлен, но в `modules` его нет.

- [ ] **Шаг 3: Добавить заголовок модуля**

В `habibi_ui/api/v1/session.py` в `MODULE_LABELS` добавить строку:

```python
	"habibi_ai": "ИИ",
```

- [ ] **Шаг 4: Убедиться, что тест проходит**

Та же команда, что в шаге 2.
Ожидается: PASS.

- [ ] **Шаг 5: Коммит**

```bash
git add habibi_ui/api/v1/session.py habibi_ui/tests/test_session.py
git commit -m "feat: модуль ИИ появляется в списке, когда установлен"
```

---

### Задача D2: Типы и клиент раздела

**Файлы:**
- Создать: `frontend/src/features/ai/types.ts`
- Создать: `frontend/src/features/ai/api.ts`

**Интерфейсы:**
- Отдаёт: типы `Bot`, `ChatRef`, `Message`, `TraceStep`, `SendResult`;
  хуки `useBots()`, `useChats()`, `useChat(chatId)`, `useCreateChat()`,
  `useSendMessage(chatId)`.

- [ ] **Шаг 1: Описать типы**

Создать `frontend/src/features/ai/types.ts`:

```ts
// Типы раздела пишутся руками, а не генерируются в shared/types/api.ts.
// Генератор (habibi_ui/typegen.py) импортирует датаклассы на старте, и импорт
// из habibi_ai уронил бы его на сайтах, где модуль не установлен — ровно на
// тех, ради которых раздел и делается необязательным.

export interface Bot {
  id: number;
  name: string;
  person_key: string | null;
  avatar: string | null;
}

export interface ChatRef {
  id: number;
  bot_id: number;
  current_scenario: string | null;
  title: string;
  preview: string;
}

export interface Message {
  id: number;
  role: "user" | "assistant";
  content: string;
  date_created: string;
}

export interface TraceStep {
  step: string;
  data: Record<string, unknown>;
}

export interface SendResult {
  success: boolean;
  response: string;
  scenario_key: string | null;
  scenario_stack: string[];
  /** Приходит только тем, у кого роль Habibi AI Debug. */
  debug?: TraceStep[];
}
```

- [ ] **Шаг 2: Написать клиент**

Создать `frontend/src/features/ai/api.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { call } from "../../shared/api/client";
import type { Bot, ChatRef, Message, SendResult } from "./types";

export function useBots() {
  return useQuery({
    queryKey: ["ai", "bots"],
    queryFn: () => call<Bot[]>("habibi_ai.api.list_bots"),
  });
}

export function useChats() {
  return useQuery({
    queryKey: ["ai", "chats"],
    queryFn: () => call<ChatRef[]>("habibi_ai.api.list_chats"),
  });
}

export function useChat(chatId: number | null) {
  return useQuery({
    queryKey: ["ai", "chat", chatId],
    queryFn: () =>
      call<{ chat: ChatRef; messages: Message[] }>("habibi_ai.api.get_chat", { chat_id: chatId }),
    enabled: chatId !== null,
  });
}

export function useCreateChat() {
  const queryClient = useQueryClient();
  return useMutation({
    // Свежесозданный чат приходит без title и preview: их считает list_chats
    // из сообщений, а сообщений в нём ещё нет. Обещать здесь ChatRef целиком
    // значило бы соврать в типе.
    mutationFn: (botId: number) =>
      call<Pick<ChatRef, "id">>("habibi_ai.api.create_chat", { bot_id: botId }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["ai", "chats"] }),
  });
}

export function useSendMessage(chatId: number | null) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (message: string) =>
      call<SendResult>("habibi_ai.api.send_message", { chat_id: chatId, message }),
    // Историю перечитываем у сервера, а не дописываем локально: сообщения
    // сохраняет движок, и порядок с нумерацией — его.
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ai", "chat", chatId] });
      queryClient.invalidateQueries({ queryKey: ["ai", "chats"] });
    },
  });
}
```

- [ ] **Шаг 3: Проверить типы**

```bash
npx tsc --noEmit -p .
```

Ожидается: без ошибок.

- [ ] **Шаг 4: Коммит**

```bash
git add frontend/src/features/ai/types.ts frontend/src/features/ai/api.ts
git commit -m "feat(ai): типы и клиент раздела"
```

---

### Задача D3: Панель трассировки

Идёт раньше экрана чата намеренно: экран её импортирует, и в обратном порядке
он бы не собрался.

**Файлы:**
- Создать: `frontend/src/features/ai/TracePanel.tsx`

**Интерфейсы:**
- Потребляет: тип `TraceStep` из `./types`.
- Отдаёт: `TracePanel({ steps }: { steps: TraceStep[] })`.

- [ ] **Шаг 1: Написать панель**

Создать `frontend/src/features/ai/TracePanel.tsx`:

```tsx
import { useState } from "react";

import type { TraceStep } from "./types";

const TITLES: Record<string, string> = {
  chat: "Состояние чата",
  router: "Роутер намерений",
  stack: "Стек сценариев",
  scenario: "Сценарий",
  completion: "Запрос в модель",
  auto_return: "Автовозврат",
};

/**
 * Трассировка последнего сообщения.
 *
 * Панель рисуется, только когда сервер прислал шаги, а он их присылает только
 * обладателю роли Habibi AI Debug. Своего переключателя здесь нет намеренно:
 * право решается на сервере, а не спрятанной кнопкой.
 */
export function TracePanel({ steps }: { steps: TraceStep[] }) {
  const [open, setOpen] = useState<string | null>("completion");

  return (
    <aside className="w-96 shrink-0 overflow-y-auto rounded-2xl border border-border bg-card p-3 text-sm">
      <h2 className="mb-2 font-medium">Как это обработалось</h2>
      {steps.map((step) => (
        <div key={step.step} className="mb-1">
          <button
            className="w-full rounded-lg px-2 py-1 text-left hover:bg-accent"
            onClick={() => setOpen(open === step.step ? null : step.step)}
          >
            {TITLES[step.step] ?? step.step}
          </button>
          {open === step.step && (
            // Перенос по словам обязателен: в completion лежит system prompt
            // целиком, и без него панель уезжает горизонтальной прокруткой.
            <pre className="mt-1 rounded-lg bg-muted p-2 text-xs break-words whitespace-pre-wrap">
              {JSON.stringify(step.data, null, 2)}
            </pre>
          )}
        </div>
      ))}
    </aside>
  );
}
```

- [ ] **Шаг 2: Проверить типы**

```bash
npx tsc --noEmit -p .
```

Ожидается: без ошибок.

- [ ] **Шаг 3: Коммит**

```bash
git add frontend/src/features/ai/TracePanel.tsx
git commit -m "feat(ai): панель трассировки обработки"
```

---

### Задача D4: Экран чата, маршрут и плитка

**Файлы:**
- Создать: `frontend/src/features/ai/ChatPage.tsx`
- Изменить: `frontend/src/App.tsx` (маршрут `/ai`)
- Изменить: `frontend/src/shared/ui/Launcher.tsx:199-236` (плитка внутреннего модуля)

**Интерфейсы:**
- Потребляет: `useBots`, `useChats`, `useChat`, `useCreateChat`, `useSendMessage`
  из `./api`; `TracePanel` из `./TracePanel`.
- Отдаёт: компонент `ChatPage`, маршрут `/ai`.

- [ ] **Шаг 1: Написать экран**

Создать `frontend/src/features/ai/ChatPage.tsx`:

```tsx
import { useState } from "react";

import { Button } from "../../shared/ui/button";
import { Skeleton } from "../../shared/ui/skeleton";
import { useBots, useChat, useChats, useCreateChat, useSendMessage } from "./api";
import { TracePanel } from "./TracePanel";
import type { TraceStep } from "./types";

export function ChatPage() {
  const [chatId, setChatId] = useState<number | null>(null);
  const [draft, setDraft] = useState("");
  const [trace, setTrace] = useState<TraceStep[] | null>(null);

  const bots = useBots();
  const chats = useChats();
  const chat = useChat(chatId);
  const createChat = useCreateChat();
  const send = useSendMessage(chatId);

  function start() {
    const bot = bots.data?.[0];
    if (!bot) return;
    createChat.mutate(bot.id, {
      onSuccess: (created) => {
        setChatId(created.id);
        setTrace(null);
      },
    });
  }

  function submit() {
    const text = draft.trim();
    if (!text || chatId === null) return;
    setDraft("");
    // Трассировка приходит только с ролью, поэтому null — норма, а не ошибка.
    send.mutate(text, { onSuccess: (result) => setTrace(result.debug ?? null) });
  }

  return (
    <div className="flex h-[calc(100vh-8rem)] gap-4">
      <aside className="w-64 shrink-0 overflow-y-auto rounded-2xl border border-border bg-card p-2">
        <Button className="mb-2 w-full" onClick={start} disabled={!bots.data?.length}>
          Новый чат
        </Button>
        {chats.isPending && <Skeleton className="h-10 w-full rounded-lg" />}
        {chats.data?.map((item) => (
          <button
            key={item.id}
            onClick={() => {
              setChatId(item.id);
              setTrace(null);
            }}
            className={`block w-full rounded-lg p-2 text-left text-sm ${
              item.id === chatId ? "bg-accent" : "hover:bg-muted"
            }`}
          >
            <span className="block truncate font-medium">{item.title || `Чат ${item.id}`}</span>
            <span className="block truncate text-xs text-muted-foreground">{item.preview}</span>
          </button>
        ))}
      </aside>

      <section className="flex min-w-0 flex-1 flex-col">
        <div className="flex-1 overflow-y-auto rounded-2xl border border-border bg-card p-4">
          {chatId === null && (
            <p className="text-muted-foreground">Выберите чат или начните новый.</p>
          )}
          {chat.data?.messages.map((message) => (
            <div
              key={message.id}
              className={`mb-2 flex ${message.role === "user" ? "justify-end" : "justify-start"}`}
            >
              <span className="max-w-[80%] rounded-2xl bg-muted px-3 py-2 whitespace-pre-wrap">
                {message.content}
              </span>
            </div>
          ))}
          {send.isPending && <p className="text-muted-foreground">…</p>}
          {send.error && <p className="text-destructive">{send.error.message}</p>}
        </div>

        <form
          className="mt-3 flex gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            submit();
          }}
        >
          <input
            className="flex-1 rounded-lg border border-border px-3 py-2"
            placeholder="Сообщение"
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            disabled={chatId === null}
          />
          <Button type="submit" disabled={chatId === null || send.isPending}>
            Отправить
          </Button>
        </form>
      </section>

      {trace && <TracePanel steps={trace} />}
    </div>
  );
}
```

- [ ] **Шаг 2: Добавить маршрут**

В `frontend/src/App.tsx` дописать импорт:

```tsx
import { ChatPage } from "./features/ai/ChatPage";
```

и маршрут перед `<Route path="*" element={<Navigate to="/" replace />} />`:

```tsx
      <Route
        path="/ai"
        element={
          <AppShell>
            <ChatPage />
          </AppShell>
        }
      />
```

- [ ] **Шаг 3: Плитка внутреннего модуля**

В `frontend/src/shared/ui/Launcher.tsx` дописать `Sparkles` в импорт из
`lucide-react`:

```tsx
import { ArrowLeft, ArrowUpRight, Bell, Sparkles } from "lucide-react";
```

Перед `function Grid(...)` добавить:

```tsx
/**
 * Модули со своим экраном внутри интерфейса.
 *
 * Остальные плитки приходят из Desktop Icon и уводят в Desk. Здесь наоборот:
 * модуль установлен (me().modules), значит экран у него свой, и уходить из
 * интерфейса незачем. Список короткий и живёт здесь: маршрут знает роутер
 * этого приложения, сервер о нём не догадывается.
 */
const INTERNAL_ROUTES: Record<string, string> = { habibi_ai: "/ai" };

function InternalTiles({ modules }: { modules: Module[] }) {
  const entries = modules.filter((module) => module.key in INTERNAL_ROUTES);
  if (entries.length === 0) return null;

  return (
    <div className="mb-3 grid grid-cols-[repeat(auto-fill,minmax(212px,1fr))] gap-3">
      {entries.map((module) => (
        <Link
          key={module.key}
          to={INTERNAL_ROUTES[module.key]}
          className="group relative flex flex-col rounded-2xl border border-border bg-card p-4 pb-[18px] no-underline"
        >
          <span className="mb-4 grid size-11 place-items-center rounded-xl bg-accent">
            <Sparkles className="size-[22px]" strokeWidth={1.75} aria-hidden="true" />
          </span>
          <span className="font-medium">{module.label}</span>
        </Link>
      ))}
    </div>
  );
}
```

Дописать `Module` в импорт типов:

```tsx
import type { DesktopItem, DesktopSection, Module, SidebarLink } from "../types/api";
```

И в `Launcher()` вставить перед строкой с `<Grid entries={sections} />`:

```tsx
      {me && <InternalTiles modules={me.modules} />}
```

- [ ] **Шаг 4: Проверить типы и сборку**

```bash
npx tsc --noEmit -p . && yarn build
```

Ожидается: без ошибок.

- [ ] **Шаг 5: Проверить вживую**

Открыть `http://localhost:5173/ui`, нажать плитку «ИИ».

Ожидается: раздел открывается, «Новый чат» заводит чат, сообщение уходит и
приходит ответ бота, чат появляется в списке слева с заголовком из первого
сообщения.

- [ ] **Шаг 6: Коммит**

```bash
git add frontend/src/features/ai/ChatPage.tsx frontend/src/App.tsx \
        frontend/src/shared/ui/Launcher.tsx
git commit -m "feat(ai): экран чата, маршрут /ai и плитка модуля"
```

---

### Задача D5: Трассировка вживую

Отдельная задача, а не шаг предыдущей: право на трассировку выдаётся ролью, и
проверять надо оба состояния — с ролью и без. Это единственное место, где
проверяется, что тенант чужой system prompt не получает.

- [ ] **Шаг 1: Выдать себе роль**

```bash
docker compose -f ../habibi_docker/.devcontainer/docker-compose.yml exec -T frappe bash -lc \
  "cd /workspace/development/frappe-bench && bench --site dev.localhost console"
```

```python
user = frappe.get_doc("User", "Administrator")
user.append("roles", {"role": "Habibi AI Debug"})
user.save(ignore_permissions=True)
frappe.db.commit()
```

- [ ] **Шаг 2: Проверить, что панель появилась**

Открыть `http://localhost:5173/ui/ai`, отправить сообщение.

Ожидается: справа панель с шестью шагами; в «Запрос в модель» виден собранный
system prompt целиком, в «Роутер намерений» — промпт роутера и сырой ответ
модели.

- [ ] **Шаг 3: Снять роль и проверить, что панели нет**

```python
user = frappe.get_doc("User", "Administrator")
user.roles = [row for row in user.roles if row.role != "Habibi AI Debug"]
user.save(ignore_permissions=True)
frappe.db.commit()
```

Перезагрузить страницу, отправить сообщение.

Ожидается: панели нет, чат работает как обычно, в ответе метода поля `debug`
нет.

- [ ] **Шаг 4: Записать проверку в README**

В `README.md` репозитория `habibi_ui` дописать раздел:

```markdown
### Раздел ИИ

Живёт в `frontend/src/features/ai`, ходит в методы `habibi_ai.api.*`.
Появляется в лаунчере, только если на сайте установлен `habibi_ai`.

Панель трассировки показывается обладателям роли **Habibi AI Debug**: она
содержит собранный system prompt, и тенанту он не предназначен.
```

- [ ] **Шаг 5: Коммит**

```bash
git add README.md
git commit -m "docs: раздел ИИ и роль трассировки"
```
