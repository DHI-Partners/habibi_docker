# План: ядро агента — инструменты вместо роутера намерений

> **Для агентов:** ОБЯЗАТЕЛЬНАЯ ПОД-СКИЛЛА: `superpowers:subagent-driven-development`
> (рекомендуется) или `superpowers:executing-plans`. Шаги отмечаются чекбоксами.

**Цель:** заменить классификатор намерений и стек сценариев на агента с
инструментами: модель видит переписку целиком, сама решает, что спросить, и
вызывает инструменты, которые исполняет `habibi_ai` под правами тенанта.

**Архитектура:** эндпоинт движка из «дай ответ» превращается в «дай следующий
шаг» и возвращает либо текст, либо запрос вызова инструмента. Цикл ведёт
`habibi_ai`: он исполняет инструмент и снова спрашивает движок. Движок остаётся
без доступа к ERP, поэтому учётные данные тенантов ему не нужны.

**Стек:** Directus 12 + TypeScript (`@directus/extensions-sdk` 18, vitest),
Frappe/ERPNext version-16 (Python 3.14, unittest), React 19 + Vite 7.

**Спек:** `habibi/specs/2026-09-10-agent-core-design.md`

## Глобальные ограничения

* Образ движка локально закреплён на `directus/directus:12.3.1` — как на проде.
* База движка — **продовая**, через SSH-туннель `127.0.0.1:15432`.
  Экспериментировать на тестовом боте и тестовом чате.
* `tenant` берётся только из `frappe.local.site`, никогда из параметров
  запроса. Единственная точка построения фильтра — `habibi_ai.engine.scoped_filter`.
* `habibi_ai/engine.py` **не импортирует frappe** — его тесты гоняются без
  поднятия сайта. Проверки прав живут в `api.py`.
* Трассировка содержит system prompt. Флаг `debug` ставит прокси по роли
  `Habibi AI Debug`, браузер повлиять не может.
* **Всё, от чего зависит следующий шаг, меняет код по факту, а не модель по
  намерению.** Это правило спека, раздел 5.1.
* **Поля схемы удаляются из кода, но не из базы** — она общая с работающим
  ботом.
* Комментарии, имена тестов и сообщения коммитов — по-русски, объясняют «почему».
* Каждая задача заканчивается коммитом в своём репозитории.

## Чего в этом плане намеренно нет

**Черновик заказа** (спека, раздел 5) — это часть 3 разрезания. Здесь
реализуется только цикл и один инструмент чтения; `update_draft`, подтверждение
и создание заказа появятся отдельным планом.

**Сжатие контекста** (спека, раздел 6) — часть 2. До неё история уходит
целиком, и достаточно длинный чат однажды не поместится в окно модели.
Спека требует, чтобы это было **громко**: провайдер вернёт ошибку, движок её
пробросит, `habibi_ai.api.call` покажет текст пользователю. Тихой потери начала
разговора при этом не происходит — ровно то поведение, которого добивались.

**Проверка аргументов по настоящим данным** (спека, раздел 7, пункт 1) не
проявится: у `get_menu` аргументов нет. Механизм отказа текстом при этом уже
закладывается в задаче 4 и будет готов к части 3.

## Порядок

Задачи 1–3 в `habibi_ai_engine`, 4–5 в `habibi_ai`, 6 в `habibi_ui`. Порядок
обязателен: 3 потребляет 1 и 2, 5 потребляет 4 и новый контракт из 3.

---

### Задача 1: Слой LLM умеет инструменты

**Файлы:**
- Изменить: `extensions/ai/src/process-message/types.ts`
- Создать: `extensions/ai/src/process-message/llm/messages.ts`
- Создать: `extensions/ai/src/process-message/llm/messages.test.ts`
- Изменить: `extensions/ai/src/process-message/llm/anthropic.ts`
- Изменить: `extensions/ai/src/process-message/llm/openai.ts`
- Изменить: `extensions/ai/src/process-message/llm/index.ts`

**Интерфейсы:**
- Отдаёт: типы `Tool`, `TurnEntry`, `StepResult`; чистые функции
  `buildAnthropicMessages`, `parseAnthropicStep`, `buildOpenAIMessages`,
  `parseOpenAIStep`; и `callLLMStep(systemPrompt, history, turn, tools, apiKey): Promise<StepResult>`.

Провайдеры описывают инструменты и продолжение диалога по-разному, поэтому
сборка сообщений и разбор ответа выносятся в чистые функции — их можно покрыть
тестами без сети, а сетевые вызовы останутся тонкими обёртками.

- [ ] **Шаг 1: Добавить типы**

В `types.ts` дописать:

```ts
/** Описание инструмента, как его видит модель. Приходит от habibi_ai. */
export interface Tool {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
}

/**
 * Что уже произошло внутри текущего хода. В chat_messages это не попадает:
 * переписка — то, что видели люди, а вызовы инструментов уходят в трассировку.
 */
export type TurnEntry =
  | { type: "tool_use"; id: string; name: string; input: Record<string, unknown> }
  | { type: "tool_result"; id: string; content: string };

/** Решение модели на этом шаге: сказать текст или вызвать инструмент. */
export type StepResult =
  | { type: "text"; content: string }
  | { type: "tool_use"; id: string; name: string; input: Record<string, unknown> };
```

- [ ] **Шаг 2: Написать падающие тесты на сборку и разбор**

Создать `llm/messages.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
  buildAnthropicMessages,
  parseAnthropicStep,
  buildOpenAIMessages,
  parseOpenAIStep,
} from "./messages";
import type { ChatMessage, TurnEntry } from "../types";

const history: ChatMessage[] = [
  { role: "user", content: "привет" },
  { role: "assistant", content: "здравствуйте" },
];

describe("buildAnthropicMessages", () => {
  it("без хода отдаёт только историю", () => {
    expect(buildAnthropicMessages(history, [])).toEqual([
      { role: "user", content: "привет" },
      { role: "assistant", content: "здравствуйте" },
    ]);
  });

  it("вызов и результат становятся парой assistant/user", () => {
    const turn: TurnEntry[] = [
      { type: "tool_use", id: "t1", name: "get_menu", input: {} },
      { type: "tool_result", id: "t1", content: "[]" },
    ];
    expect(buildAnthropicMessages(history, turn).slice(2)).toEqual([
      {
        role: "assistant",
        content: [{ type: "tool_use", id: "t1", name: "get_menu", input: {} }],
      },
      {
        role: "user",
        content: [{ type: "tool_result", tool_use_id: "t1", content: "[]" }],
      },
    ]);
  });
});

describe("parseAnthropicStep", () => {
  it("текстовый блок даёт text", () => {
    expect(
      parseAnthropicStep({ content: [{ type: "text", text: "готово" }] })
    ).toEqual({ type: "text", content: "готово" });
  });

  it("блок tool_use важнее текстового", () => {
    // Модель часто сопровождает вызов пояснением. Отдать пользователю текст и
    // потерять вызов значило бы молча не выполнить действие.
    expect(
      parseAnthropicStep({
        content: [
          { type: "text", text: "сейчас посмотрю" },
          { type: "tool_use", id: "t9", name: "get_menu", input: { a: 1 } },
        ],
      })
    ).toEqual({ type: "tool_use", id: "t9", name: "get_menu", input: { a: 1 } });
  });

  it("блок thinking не мешает", () => {
    expect(
      parseAnthropicStep({
        content: [{ type: "thinking", thinking: "..." }, { type: "text", text: "ок" }],
      })
    ).toEqual({ type: "text", content: "ок" });
  });
});

describe("buildOpenAIMessages", () => {
  it("вызов и результат дают assistant с tool_calls и сообщение роли tool", () => {
    const turn: TurnEntry[] = [
      { type: "tool_use", id: "t1", name: "get_menu", input: {} },
      { type: "tool_result", id: "t1", content: "[]" },
    ];
    expect(buildOpenAIMessages(history, turn).slice(2)).toEqual([
      {
        role: "assistant",
        tool_calls: [
          { id: "t1", type: "function", function: { name: "get_menu", arguments: "{}" } },
        ],
      },
      { role: "tool", tool_call_id: "t1", content: "[]" },
    ]);
  });
});

describe("parseOpenAIStep", () => {
  it("tool_calls разбирается, аргументы приходят строкой", () => {
    expect(
      parseOpenAIStep({
        choices: [
          {
            message: {
              tool_calls: [
                { id: "c1", function: { name: "get_menu", arguments: '{"x":2}' } },
              ],
            },
          },
        ],
      })
    ).toEqual({ type: "tool_use", id: "c1", name: "get_menu", input: { x: 2 } });
  });

  it("битые аргументы не роняют разбор", () => {
    // Модель иногда присылает не-JSON. Упасть здесь значило бы потерять весь
    // ход; пустой input даст инструменту отказ по валидации, и модель исправится.
    expect(
      parseOpenAIStep({
        choices: [{ message: { tool_calls: [{ id: "c2", function: { name: "f", arguments: "{" } }] } }],
      })
    ).toEqual({ type: "tool_use", id: "c2", name: "f", input: {} });
  });

  it("без tool_calls отдаёт текст", () => {
    expect(
      parseOpenAIStep({ choices: [{ message: { content: "привет" } }] })
    ).toEqual({ type: "text", content: "привет" });
  });
});
```

- [ ] **Шаг 3: Убедиться, что тесты падают**

Запустить: `cd extensions/ai && npm test`
Ожидается: FAIL, `Failed to resolve import "./messages"`.

- [ ] **Шаг 4: Написать чистые функции**

Создать `llm/messages.ts`:

```ts
import type { ChatMessage, StepResult, TurnEntry } from "../types";

/**
 * Сборка сообщений для Anthropic.
 *
 * Вызов инструмента и его результат — это не одно сообщение, а пара:
 * assistant с блоком tool_use и user с блоком tool_result. Провайдер
 * отказывается продолжать, если пара разорвана.
 */
export function buildAnthropicMessages(
  history: ChatMessage[],
  turn: TurnEntry[]
): any[] {
  const messages: any[] = history.map((m) => ({ role: m.role, content: m.content }));

  for (const entry of turn) {
    if (entry.type === "tool_use") {
      messages.push({
        role: "assistant",
        content: [
          { type: "tool_use", id: entry.id, name: entry.name, input: entry.input },
        ],
      });
    } else {
      messages.push({
        role: "user",
        content: [
          { type: "tool_result", tool_use_id: entry.id, content: entry.content },
        ],
      });
    }
  }

  return messages;
}

/**
 * Разбор ответа Anthropic.
 *
 * Вызов инструмента важнее текста: модель часто сопровождает его пояснением
 * вроде «сейчас посмотрю», и отдать пользователю текст, потеряв вызов,
 * значило бы молча не выполнить действие.
 */
export function parseAnthropicStep(data: any): StepResult {
  const blocks = data?.content || [];

  const toolUse = blocks.find((b: any) => b.type === "tool_use");
  if (toolUse) {
    return {
      type: "tool_use",
      id: toolUse.id,
      name: toolUse.name,
      input: toolUse.input || {},
    };
  }

  // Ищем блок по типу, а не берём первый: на современных моделях мышление
  // включено адаптивно, и content[0] может быть блоком thinking без поля text.
  const textBlock = blocks.find((b: any) => b.type === "text");
  return { type: "text", content: textBlock?.text || "" };
}

/** Сборка сообщений для OpenAI: своя форма для того же самого. */
export function buildOpenAIMessages(
  history: ChatMessage[],
  turn: TurnEntry[]
): any[] {
  const messages: any[] = history.map((m) => ({ role: m.role, content: m.content }));

  for (const entry of turn) {
    if (entry.type === "tool_use") {
      messages.push({
        role: "assistant",
        tool_calls: [
          {
            id: entry.id,
            type: "function",
            function: { name: entry.name, arguments: JSON.stringify(entry.input) },
          },
        ],
      });
    } else {
      messages.push({ role: "tool", tool_call_id: entry.id, content: entry.content });
    }
  }

  return messages;
}

/** Разбор ответа OpenAI. Аргументы приходят строкой и могут быть не-JSON. */
export function parseOpenAIStep(data: any): StepResult {
  const message = data?.choices?.[0]?.message;
  const call = message?.tool_calls?.[0];

  if (call) {
    let input: Record<string, unknown> = {};
    try {
      input = JSON.parse(call.function?.arguments || "{}");
    } catch {
      // Упасть здесь значило бы потерять весь ход. Пустой input приведёт к
      // отказу по валидации на стороне инструмента, и модель исправится.
      input = {};
    }
    return { type: "tool_use", id: call.id, name: call.function?.name, input };
  }

  return { type: "text", content: message?.content || "" };
}
```

- [ ] **Шаг 5: Убедиться, что тесты проходят**

Запустить: `npm test`
Ожидается: PASS.

- [ ] **Шаг 6: Сетевые обёртки**

В `llm/anthropic.ts` дописать:

```ts
export async function callAnthropicStep(
  systemPrompt: string,
  history: ChatMessage[],
  turn: TurnEntry[],
  tools: Tool[],
  apiKey: string
): Promise<StepResult> {
  const body: any = {
    model: getAnthropicModel(),
    max_tokens: ANTHROPIC_COMPLETION_MAX_TOKENS,
    system: systemPrompt,
    messages: buildAnthropicMessages(history, turn),
  };
  // Пустой массив инструментов провайдер отвергает — бот без инструментов это
  // законная конфигурация (обычный собеседник), поэтому поле опускаем вовсе.
  if (tools.length > 0) body.tools = tools;

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`Anthropic API error: ${response.status} - ${await response.text()}`);
  }

  return parseAnthropicStep(await response.json());
}
```

В `llm/openai.ts` — то же самое, с формой OpenAI:

```ts
export async function callOpenAIStep(
  systemPrompt: string,
  history: ChatMessage[],
  turn: TurnEntry[],
  tools: Tool[],
  apiKey: string
): Promise<StepResult> {
  const body: any = {
    model: getOpenAIModel(),
    max_tokens: OPENAI_COMPLETION_MAX_TOKENS,
    messages: [
      { role: "system", content: systemPrompt },
      ...buildOpenAIMessages(history, turn),
    ],
  };
  if (tools.length > 0) {
    body.tools = tools.map((t) => ({
      type: "function",
      function: {
        name: t.name,
        description: t.description,
        parameters: t.input_schema,
      },
    }));
  }

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`OpenAI API error: ${response.status} - ${await response.text()}`);
  }

  return parseOpenAIStep(await response.json());
}
```

Импорты `buildAnthropicMessages`/`parseAnthropicStep` и типы добавить в шапки
соответствующих файлов.

- [ ] **Шаг 7: Выбор провайдера**

В `llm/index.ts` дописать:

```ts
export async function callLLMStep(
  systemPrompt: string,
  history: ChatMessage[],
  turn: TurnEntry[],
  tools: Tool[],
  apiKey?: string
): Promise<StepResult> {
  if (!apiKey) {
    throw new Error("API key not found. Set OPENAI_API_KEY or ANTHROPIC_API_KEY");
  }

  if (isAnthropicKey(apiKey)) {
    return await callAnthropicStep(systemPrompt, history, turn, tools, apiKey);
  }
  return await callOpenAIStep(systemPrompt, history, turn, tools, apiKey);
}
```

- [ ] **Шаг 8: Сборка и коммит**

```bash
npm test && npm run build
git add extensions/ai/src/process-message/types.ts \
        extensions/ai/src/process-message/llm/
git commit -m "feat(agent): слой LLM умеет вызовы инструментов"
```

---

### Задача 2: Инструкция собирается из всех сценариев

**Файлы:**
- Изменить: `extensions/ai/src/process-message/services/scenario.service.ts`
- Создать: `extensions/ai/src/process-message/services/scenario.service.test.ts`

**Интерфейсы:**
- Потребляет: ничего из задачи 1.
- Отдаёт: `ScenarioService.getActiveConfig(botId): Promise<{ instruction: string; toolNames: string[] }>`.

Сценарии перестают быть состоянием. Все включённые наборы бота сливаются: их
фрагменты инструкции — в один текст, их инструменты — в один список. Никто не
выбирает набор в рантайме.

- [ ] **Шаг 1: Написать падающий тест**

Создать `services/scenario.service.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest";
import { ScenarioService } from "./scenario.service";

function serviceWith(scenarios: any[], prompts: any[]) {
  const readByQuery = vi
    .fn()
    .mockResolvedValueOnce(scenarios)
    .mockResolvedValueOnce(prompts);
  const ItemsService = vi.fn(() => ({ readByQuery })) as any;
  return { service: new ScenarioService(ItemsService, {}, null), readByQuery };
}

describe("getActiveConfig", () => {
  it("сливает инструкции всех сценариев и объединяет инструменты", async () => {
    const { service } = serviceWith(
      [
        { scenario_key: "order", initial_prompt: 3, tools: ["get_menu", "update_draft"] },
        { scenario_key: "complaint", initial_prompt: 4, tools: ["log_complaint"] },
      ],
      [
        { id: 3, system_prompt: "Заказ оформляй только зная состав." },
        { id: 4, system_prompt: "Жалобу фиксируй сразу." },
      ]
    );

    const config = await service.getActiveConfig(1);

    expect(config.instruction).toBe(
      "Заказ оформляй только зная состав.\n\nЖалобу фиксируй сразу."
    );
    expect(config.toolNames).toEqual(["get_menu", "update_draft", "log_complaint"]);
  });

  it("повторяющийся инструмент не дублируется", async () => {
    const { service } = serviceWith(
      [
        { scenario_key: "a", initial_prompt: 1, tools: ["get_menu"] },
        { scenario_key: "b", initial_prompt: 2, tools: ["get_menu"] },
      ],
      [{ id: 1, system_prompt: "A" }, { id: 2, system_prompt: "B" }]
    );

    expect((await service.getActiveConfig(1)).toolNames).toEqual(["get_menu"]);
  });

  it("бот без сценариев даёт пустую конфигурацию и не ходит за промптами", async () => {
    // Законный случай: собеседник без инструментов. Второй запрос с пустым
    // _in вернул бы заведомо пустой ответ — лишний круг к базе.
    const { service, readByQuery } = serviceWith([], []);
    const config = await service.getActiveConfig(1);

    expect(config).toEqual({ instruction: "", toolNames: [] });
    expect(readByQuery).toHaveBeenCalledTimes(1);
  });

  it("сценарий без tools не роняет сборку", async () => {
    const { service } = serviceWith(
      [{ scenario_key: "a", initial_prompt: 1, tools: null }],
      [{ id: 1, system_prompt: "A" }]
    );
    expect((await service.getActiveConfig(1)).toolNames).toEqual([]);
  });
});
```

- [ ] **Шаг 2: Убедиться, что тесты падают**

Запустить: `npm test`
Ожидается: FAIL, `service.getActiveConfig is not a function`.

- [ ] **Шаг 3: Реализовать**

В `services/scenario.service.ts` добавить метод:

```ts
  /**
   * Инструкция и инструменты бота, собранные из всех его сценариев.
   *
   * Сценарий больше не состояние, а набор возможностей: выбирать его в
   * рантайме некому и незачем — модель видит всё сразу и решает сама.
   */
  async getActiveConfig(
    botId: number
  ): Promise<{ instruction: string; toolNames: string[] }> {
    const scenariosService = new this.itemsService("chatbot_scenarios", {
      schema: this.schema,
      accountability: this.accountability,
    });

    const scenarios = await scenariosService.readByQuery({
      filter: { bot_id: { _eq: botId } },
      fields: ["scenario_key", "initial_prompt", "tools"],
      sort: ["id"],
    });

    if (!scenarios || scenarios.length === 0) {
      return { instruction: "", toolNames: [] };
    }

    const promptIds = scenarios
      .map((s: any) => s.initial_prompt)
      .filter((id: any) => typeof id === "number");

    const promptsService = new this.itemsService("ai_prompts", {
      schema: this.schema,
      accountability: this.accountability,
    });
    const prompts = promptIds.length
      ? await promptsService.readByQuery({
          filter: { id: { _in: promptIds } },
          fields: ["id", "system_prompt"],
        })
      : [];

    const textById = new Map<number, string>(
      (prompts || []).map((p: any) => [p.id, p.system_prompt || ""])
    );

    const parts: string[] = [];
    const toolNames: string[] = [];

    for (const scenario of scenarios) {
      const text = textById.get(scenario.initial_prompt) || "";
      if (text) parts.push(text);
      for (const name of scenario.tools || []) {
        if (!toolNames.includes(name)) toolNames.push(name);
      }
    }

    return { instruction: parts.join("\n\n"), toolNames };
  }
```

- [ ] **Шаг 4: Убедиться, что тесты проходят**

Запустить: `npm test`
Ожидается: PASS.

- [ ] **Шаг 5: Завести поле tools в схеме**

Поля `tools` в `chatbot_scenarios` нет. Завести через MCP или админку
`ai.habibi-erp.com`: тип **JSON**, nullable, интерфейс — список строк.

Nullable намеренно: база общая с работающим ботом, старое ядро поля не читает,
новое на пустом значении даёт набор без инструментов.

Проверка:

```bash
curl -s -H "Authorization: Bearer <токен>" \
  "https://ai.habibi-erp.com/items/chatbot_scenarios?fields=id,scenario_key,tools&limit=5" | jq
```

Ожидается: поле `tools` присутствует, значение `null`.

- [ ] **Шаг 6: Коммит**

```bash
npm test && npm run build
git add extensions/ai/src/process-message/services/
git commit -m "feat(agent): инструкция и инструменты собираются из всех сценариев"
```

---

### Задача 3: Эндпоинт становится шагом

**Файлы:**
- Изменить: `extensions/ai/src/process-message/index.ts` (переписывается)
- Изменить: `extensions/ai/src/process-message/types.ts`
- Удалить: `extensions/ai/src/process-message/utils/scenario-stack.ts`
- Удалить: `extensions/ai/src/process-message/utils/scenario-stack.test.ts`

**Интерфейсы:**
- Потребляет: `callLLMStep` и типы из задачи 1, `getActiveConfig` из задачи 2.
- Отдаёт: `POST /ai-process-message/` принимает `{chat_id, bot_id?, user_message,
  turn?, tools?, debug?}` и возвращает `{type: "text", content}` либо
  `{type: "tool_use", id, name, input}`, в обоих случаях с необязательным `debug`.

- [ ] **Шаг 1: Обновить тип запроса**

В `types.ts` заменить `ProcessMessageRequest`:

```ts
export interface ProcessMessageRequest {
  chat_id: number;
  user_message: string;
  bot_id?: number;
  /** Что уже произошло внутри этого хода. Пусто на первом шаге. */
  turn?: TurnEntry[];
  /** Что habibi_ai готов исполнить для этого тенанта и бота. */
  tools?: Tool[];
  debug?: boolean;
}
```

- [ ] **Шаг 2: Переписать обработчик**

`index.ts` целиком:

```ts
import { defineEndpoint } from "@directus/extensions-sdk";
import type { Request, Response } from "express";
import type { ProcessMessageRequest } from "./types";
import { getAccountability } from "./utils/accountability";
import { Trace } from "./utils/trace";
import { ChatService } from "./services/chat.service";
import { BotService } from "./services/bot.service";
import { ScenarioService } from "./services/scenario.service";
import { callLLMStep, resolveLLMCallInfo } from "./llm";

export default defineEndpoint((router, context) => {
  const { services, getSchema } = context;
  const ItemsService = services.ItemsService;

  /**
   * POST /ai-process-message
   *
   * Один ШАГ обработки, а не весь ход: возвращает либо текст пользователю,
   * либо запрос вызова инструмента. Цикл ведёт habibi_ai — он единственный
   * знает тенанта и его права, а движку учётные данные тенантов не нужны.
   */
  router.post("/", async (req: Request, res: Response) => {
    try {
      const {
        chat_id,
        user_message,
        bot_id,
        turn = [],
        tools = [],
        debug,
      }: ProcessMessageRequest = req.body;
      const trace = new Trace(debug === true);

      if (!chat_id || !user_message) {
        return res.status(400).json({
          error: "Missing required fields: chat_id and user_message are required",
        });
      }

      const schema = await getSchema();
      const accountability = getAccountability(req);

      const chatService = new ChatService(ItemsService, schema, accountability);
      const botService = new BotService(ItemsService, schema);
      const scenarioService = new ScenarioService(ItemsService, schema, accountability);

      let chat = await chatService.getChatById(chat_id);
      const chatExisted = chat !== null;

      if (!chat) {
        if (!bot_id) {
          return res.status(400).json({
            error: "bot_id is required when creating a new chat",
          });
        }
        chat = await chatService.createChat(chat_id, bot_id, accountability?.user || null);
      }
      if (!chat) {
        return res.status(500).json({ error: "Failed to create or read chat" });
      }

      const targetBotId = bot_id || (chat.bot_id as number);
      if (!targetBotId) {
        return res.status(400).json({ error: "bot_id is required" });
      }

      trace.add("chat", {
        created: !chatExisted,
        bot_id: targetBotId,
        metadata: (chat.metadata as Record<string, any>) || {},
        turn_length: turn.length,
      });

      const bot = await botService.getBotById(targetBotId);
      if (!bot) {
        return res.status(404).json({ error: "Bot not found" });
      }

      const { instruction, toolNames } = await scenarioService.getActiveConfig(targetBotId);

      // Имя из конфигурации, которого habibi_ai не прислал, игнорируется: конфиг
      // правят в админке без ревью, и опечатка не должна ронять диалог. Но и
      // молчать нельзя — иначе человек будет искать, почему бот «не умеет».
      const offered = tools.filter((t) => toolNames.includes(t.name));
      const missing = toolNames.filter((n) => !tools.some((t) => t.name === n));

      trace.add("tools", {
        configured: toolNames,
        offered: offered.map((t) => t.name),
        missing,
      });

      const systemPrompt = [bot.global_system_prompt || "", instruction]
        .filter(Boolean)
        .join("\n\n");

      // Сообщение пользователя сохраняется один раз за ход — на первом шаге,
      // когда turn ещё пуст. Историю читаем ПОСЛЕ сохранения: тогда свежая
      // реплика в ней уже есть, и дописывать её руками не нужно. На втором
      // витке она тоже там — дописывание дало бы дубль.
      if (turn.length === 0) {
        await chatService.createMessage(chat_id, "user", user_message, (chat as any).tenant);
      }
      const historyForModel = await chatService.getChatMessages(chat_id);

      const callInfo = resolveLLMCallInfo(
        process.env.OPENAI_API_KEY || process.env.ANTHROPIC_API_KEY,
        "completion"
      );
      trace.add("completion", {
        system_prompt: systemPrompt,
        messages: historyForModel,
        turn,
        tools: offered.map((t) => t.name),
        ...callInfo,
      });

      const step = await callLLMStep(
        systemPrompt,
        historyForModel,
        turn,
        offered,
        process.env.OPENAI_API_KEY || process.env.ANTHROPIC_API_KEY
      );

      if (step.type === "tool_use") {
        trace.add("tool_use", { id: step.id, name: step.name, input: step.input });
        const steps = trace.result();
        return res.json({ ...step, ...(steps ? { debug: steps } : {}) });
      }

      await chatService.createMessage(chat_id, "assistant", step.content, (chat as any).tenant);
      trace.add("answer", { length: step.content.length });

      const steps = trace.result();
      return res.json({ ...step, ...(steps ? { debug: steps } : {}) });
    } catch (error: any) {
      console.error("[AI Process] Error:", error);
      return res.status(500).json({ error: "Internal server error", message: error.message });
    }
  });
});
```

- [ ] **Шаг 3: Удалить машинерию стека**

```bash
git rm extensions/ai/src/process-message/utils/scenario-stack.ts \
       extensions/ai/src/process-message/utils/scenario-stack.test.ts
```

Девять тестов уходят вместе с механизмом, который они закрепляли. Это не потеря
покрытия: они описывали поведение, которого больше нет.

- [ ] **Шаг 4: Убрать осиротевшие методы сервисов**

Вместе с роутером и стеком перестают вызываться три метода. Оставить их значит
оставить код, который выглядит рабочим и никем не используется — следующий
читатель потратит время, выясняя, кто их зовёт.

* `ChatService.updateChatState` — писал `current_scenario` и `scenario_stack`;
* `ScenarioService.getScenarioByKey` — искал сценарий по ключу от роутера;
* `PromptService.getRouterPrompt` — доставал промпт классификатора.

Удалить вместе с их тестами, если таковые есть.

- [ ] **Шаг 5: Проверить, что ничего не ссылается на удалённое**

```bash
grep -rn "scenario-stack\|processScenarioStack\|processAutoReturn\|RETURN_TO_PREVIOUS\|current_scenario\|scenario_stack\|max_stack\|max_history_messages" \
  extensions/ai/src --include="*.ts" | grep -v directus-schema
```

Ожидается: пусто. Упоминания в `types/directus-schema.ts` остаются — это
сгенерированный снимок схемы, а поля из базы не удаляются.

- [ ] **Шаг 6: Тесты и сборка**

```bash
npm test && npm run build
```

Ожидается: PASS (тесты `trace` и `messages`, `scenario.service`), сборка без
ошибок TypeScript.

- [ ] **Шаг 7: Коммит**

```bash
git add -A
git commit -m "feat(agent): эндпоинт отдаёт шаг, роутер и стек удалены"
```

---

### Задача 4: Реестр инструментов и get_menu

**Файлы:**
- Создать: `habibi_ai/tools/__init__.py`
- Создать: `habibi_ai/tools/menu.py`
- Создать: `habibi_ai/tests/test_tools.py`

Репозиторий: `habibi_ai`.

**Интерфейсы:**
- Отдаёт: `habibi_ai.tools.registry()` → `dict[str, Tool]`;
  `habibi_ai.tools.definitions(names)` → список `{name, description, input_schema}`;
  `habibi_ai.tools.execute(name, args)` → строка результата.

Инструменты объявляются кодом: права и валидация под тестами и ревью, а не в
формочках админки.

- [ ] **Шаг 1: Написать падающий тест**

Создать `habibi_ai/tests/test_tools.py`:

```python
"""Тесты реестра инструментов.

Модуль импортирует frappe (через сами инструменты), но сайт не нужен: ERP-вызовы
подменяются. Проверяется реестр и поведение на неизвестном имени — то, из-за
чего диалог может оборваться на ровном месте.
"""

import unittest
from unittest.mock import patch

from habibi_ai import tools


class TestРеестр(unittest.TestCase):
	def test_get_menu_объявлен(self):
		self.assertIn("get_menu", tools.registry())

	def test_определения_отдаются_только_для_запрошенных(self):
		defs = tools.definitions(["get_menu"])
		self.assertEqual([d["name"] for d in defs], ["get_menu"])
		self.assertTrue(defs[0]["description"])
		self.assertEqual(defs[0]["input_schema"]["type"], "object")

	def test_неизвестное_имя_в_определениях_пропускается(self):
		# Имена приходят из конфигурации, которую правят в админке без ревью.
		# Опечатка не должна ронять диалог.
		self.assertEqual(tools.definitions(["get_menu", "опечатка"]), tools.definitions(["get_menu"]))

	def test_вызов_неизвестного_инструмента_даёт_отказ_текстом(self):
		# Отказ возвращается модели, чтобы она исправилась сама, а не исключение,
		# которое оборвало бы ход.
		result = tools.execute("нет_такого", {})
		self.assertIn("нет_такого", result)
		self.assertIn("Доступные", result)


class TestGetMenu(unittest.TestCase):
	def test_возвращает_позиции_с_ценами(self):
		items = [
			{"item_code": "BURGER-01", "item_name": "Сигнатурный бургер", "standard_rate": 3890},
			{"item_code": "FRIES-01", "item_name": "Картофель фри", "standard_rate": 990},
		]
		with patch("frappe.get_all", return_value=items):
			result = tools.execute("get_menu", {})

		self.assertIn("Сигнатурный бургер", result)
		self.assertIn("3890", result)

	def test_пустое_меню_говорит_об_этом_словами(self):
		# Пустая строка выглядела бы как сбой инструмента; модель должна понять,
		# что позиций действительно нет, и сказать это клиенту.
		with patch("frappe.get_all", return_value=[]):
			self.assertIn("пуст", tools.execute("get_menu", {}).lower())
```

- [ ] **Шаг 2: Убедиться, что тесты падают**

```bash
cd /Users/fsa/Projects/habibi/habibi_docker
docker compose -f .devcontainer/docker-compose.yml exec -T frappe bash -lc \
  "cd /workspace/development/frappe-bench && env/bin/python -m unittest habibi_ai.tests.test_tools -v"
```

Ожидается: FAIL, `ModuleNotFoundError: No module named 'habibi_ai.tools'`.

- [ ] **Шаг 3: Реестр**

Создать `habibi_ai/tools/__init__.py`:

```python
"""Реестр инструментов агента.

Инструменты объявляются кодом, а не в админке: аргументы приходят от языковой
модели, и проверка их правдоподобия — это то, что должно лежать под тестами и
ревью. Сценарий в Directus только выбирает имена из объявленного здесь.
"""

import json

_REGISTRY = {}


def tool(name, description, input_schema):
	"""Объявляет функцию инструментом, видимым модели."""

	def decorator(func):
		_REGISTRY[name] = {
			"name": name,
			"description": description,
			"input_schema": input_schema,
			"run": func,
		}
		return func

	return decorator


def registry():
	return dict(_REGISTRY)


def definitions(names):
	"""Описания для модели — только по запрошенным именам.

	Неизвестное имя пропускается: конфигурацию правят без ревью, и опечатка не
	повод обрывать диалог. Движок такие имена показывает в трассировке.
	"""
	return [
		{k: v for k, v in _REGISTRY[n].items() if k != "run"}
		for n in names
		if n in _REGISTRY
	]


def execute(name, args):
	"""Исполняет инструмент, всегда возвращая строку для модели.

	Отказ — тоже строка, а не исключение: модель должна увидеть причину и
	исправиться сама. Исключение оборвало бы весь ход.
	"""
	entry = _REGISTRY.get(name)
	if entry is None:
		return f"Инструмент {name} недоступен. Доступные: {', '.join(sorted(_REGISTRY))}"

	try:
		return entry["run"](**(args or {}))
	except TypeError as e:
		return f"Неверные аргументы для {name}: {e}"
	except Exception as e:
		return f"Инструмент {name} завершился ошибкой: {e}"


from habibi_ai.tools import menu  # noqa: E402,F401  регистрация при импорте пакета
```

- [ ] **Шаг 4: Инструмент меню**

Создать `habibi_ai/tools/menu.py`:

```python
"""Чтение меню из ERPNext.

Меню принадлежит ERPNext, а не боту: правило, соблюдаемое в промпте, — это
правило, от которого модель можно отговорить. Бот не помнит цены, а спрашивает.
"""

import frappe

from habibi_ai.tools import tool


@tool(
	name="get_menu",
	description=(
		"Актуальные позиции меню с ценами. Вызывай перед тем, как называть "
		"клиенту состав или стоимость — цены меняются, помнить их нельзя."
	),
	input_schema={"type": "object", "properties": {}},
)
def get_menu():
	# get_all применяет права текущего пользователя: инструмент исполняется под
	# сессией тенанта, поэтому чужих позиций он не увидит.
	items = frappe.get_all(
		"Item",
		filters={"is_sales_item": 1, "disabled": 0},
		fields=["item_code", "item_name", "standard_rate"],
		limit_page_length=100,
		order_by="item_name",
	)

	if not items:
		return "Меню пусто — позиций для продажи не заведено."

	lines = [
		f"{i['item_name']} ({i['item_code']}) — {i['standard_rate']}"
		for i in items
	]
	return "\n".join(lines)
```

- [ ] **Шаг 5: Убедиться, что тесты проходят**

Та же команда, что в шаге 2.
Ожидается: PASS, 6 тестов.

- [ ] **Шаг 6: Коммит**

```bash
git add habibi_ai/tools/ habibi_ai/tests/test_tools.py
git commit -m "feat(agent): реестр инструментов и чтение меню из ERPNext"
```

---

### Задача 5: Цикл в habibi_ai

**Файлы:**
- Изменить: `habibi_ai/engine.py` (`send_message` → `step`)
- Изменить: `habibi_ai/api.py` (`send_message` ведёт цикл)
- Изменить: `habibi_ai/tests/test_engine.py`
- Изменить: `habibi_ai/tests/test_api.py`

**Интерфейсы:**
- Потребляет: `tools.definitions`, `tools.execute` из задачи 4; контракт шага из задачи 3.
- Отдаёт: `EngineClient.step(chat_id, message, bot_id=None, turn=None, tools=None, debug=False)` →
  словарь ответа движка; `habibi_ai.api.MAX_LOOP = 8`.

- [ ] **Шаг 1: Написать падающие тесты цикла**

В `habibi_ai/tests/test_api.py` дописать:

```python
class TestЦиклИнструментов(unittest.TestCase):
	def _client_с_шагами(self, steps):
		client = Mock()
		client.step = Mock(side_effect=steps)
		return client

	def test_текст_с_первого_шага_отдаётся_как_есть(self):
		client = self._client_с_шагами([{"type": "text", "content": "привет"}])
		with patch("frappe.get_roles", return_value=[]):
			with patch("habibi_ai.api.get_client", return_value=client):
				result = api.send_message(1, "привет")
		self.assertEqual(result["response"], "привет")
		self.assertEqual(client.step.call_count, 1)

	def test_вызов_инструмента_исполняется_и_цикл_продолжается(self):
		client = self._client_с_шагами([
			{"type": "tool_use", "id": "t1", "name": "get_menu", "input": {}},
			{"type": "text", "content": "шаурма 350"},
		])
		with patch("frappe.get_roles", return_value=[]):
			with patch("habibi_ai.api.get_client", return_value=client):
				with patch("habibi_ai.tools.execute", return_value="шаурма — 350") as run:
					result = api.send_message(1, "что есть?")

		run.assert_called_once_with("get_menu", {})
		self.assertEqual(result["response"], "шаурма 350")
		# Результат инструмента ушёл во второй вызов движка.
		turn = client.step.call_args_list[1].kwargs["turn"]
		self.assertEqual(turn[1], {"type": "tool_result", "id": "t1", "content": "шаурма — 350"})

	def test_бесконечный_цикл_обрывается_ошибкой(self):
		# Модель, которая вызывает инструменты и не приходит к ответу, означает,
		# что задача ей не по силам. Молчаливая остановка скрыла бы это.
		steps = [{"type": "tool_use", "id": f"t{i}", "name": "get_menu", "input": {}} for i in range(api.MAX_LOOP + 1)]
		client = self._client_с_шагами(steps)
		with patch("frappe.get_roles", return_value=[]):
			with patch("habibi_ai.api.get_client", return_value=client):
				with patch("habibi_ai.tools.execute", return_value="[]"):
					with self.assertRaises(Exception):
						api.send_message(1, "зациклись")

	def test_инструменты_подаются_только_объявленные(self):
		client = self._client_с_шагами([{"type": "text", "content": "ок"}])
		with patch("frappe.get_roles", return_value=[]):
			with patch("habibi_ai.api.get_client", return_value=client):
				api.send_message(1, "привет")
		sent = client.step.call_args.kwargs["tools"]
		self.assertTrue(all("run" not in d for d in sent))
```

- [ ] **Шаг 2: Убедиться, что тесты падают**

```bash
cd /Users/fsa/Projects/habibi/habibi_docker
docker compose -f .devcontainer/docker-compose.yml exec -T frappe bash -lc \
  "cd /workspace/development/frappe-bench && env/bin/python -m unittest habibi_ai.tests.test_api -v"
```

Ожидается: FAIL, `AttributeError: module 'habibi_ai.api' has no attribute 'MAX_LOOP'`.

- [ ] **Шаг 3: Клиент умеет шаг**

В `habibi_ai/engine.py` заменить `send_message`:

```python
	def step(self, chat_id, message, bot_id=None, turn=None, tools=None, debug=False):
		"""Один шаг обработки: движок отвечает текстом либо просит вызвать инструмент.

		get_chat вызывается ДО обращения к движку намеренно: сам endpoint о
		тенантах ничего не знает, и без этой проверки номер чужого чата ушёл бы
		в него в обход фильтра.

		Цикл ведёт вызывающий (api.send_message), а не движок: инструменты
		исполняются под правами тенанта, и учётные данные тенантов движку не
		нужны и не передаются.
		"""
		self.get_chat(chat_id)

		payload = {"chat_id": chat_id, "user_message": message, "turn": turn or [], "tools": tools or []}
		if bot_id is not None:
			payload["bot_id"] = bot_id
		if debug:
			payload["debug"] = True

		return self._post("ai-process-message", payload)
```

- [ ] **Шаг 4: Цикл в прокси**

В `habibi_ai/api.py` дописать импорт и константу:

```python
from habibi_ai import tools

# Сколько витков цикла допускается на один ход. Исчерпание — ошибка, а не
# молчаливая остановка: модель, которая вызывает инструменты и не приходит к
# ответу, не справляется с задачей имеющимися средствами, и человек должен
# об этом узнать.
MAX_LOOP = 8
```

и заменить `send_message`:

```python
@frappe.whitelist()
def send_message(chat_id, message, bot_id=None):
	"""Ведёт цикл: движок решает, мы исполняем, пока не получим текст.

	Флаг трассировки ставит сервер, а не клиент: в теле запроса от браузера
	поля debug нет вообще — ровно так же, как там нет tenant.
	"""
	debug = DEBUG_ROLE in frappe.get_roles()
	client = get_client()

	turn = []
	collected_debug = []

	for _ in range(MAX_LOOP):
		step = call(
			client.step,
			int(chat_id),
			message,
			bot_id,
			turn=list(turn),
			tools=tools.definitions(_tool_names()),
			debug=debug,
		)

		if debug and step.get("debug"):
			collected_debug.extend(step["debug"])

		if step.get("type") == "text":
			result = {"success": True, "response": step.get("content", "")}
			if collected_debug:
				result["debug"] = collected_debug
			return result

		turn.append(
			{"type": "tool_use", "id": step["id"], "name": step["name"], "input": step.get("input") or {}}
		)
		turn.append(
			{"type": "tool_result", "id": step["id"], "content": tools.execute(step["name"], step.get("input") or {})}
		)

	frappe.throw(
		f"Бот не смог завершить ответ за {MAX_LOOP} обращений к инструментам. "
		"Проверьте инструкции сценариев в трассировке."
	)


def _tool_names():
	"""Какие инструменты habibi_ai готов исполнить.

	Пока весь реестр: отбор по сценариям делает движок, сверяя присланное с
	конфигурацией. Здесь остаётся граница «что вообще существует в коде».
	"""
	return sorted(tools.registry())
```

- [ ] **Шаг 5: Убедиться, что тесты проходят**

Прогнать оба модуля:

```bash
docker compose -f .devcontainer/docker-compose.yml exec -T frappe bash -lc \
  "cd /workspace/development/frappe-bench && env/bin/python -m unittest habibi_ai.tests.test_engine habibi_ai.tests.test_api habibi_ai.tests.test_tools -v"
```

Ожидается: PASS. Тесты `test_engine`, ссылающиеся на `send_message` клиента,
переименовать под `step` — сигнатура изменилась, поведение проверки чата нет.

- [ ] **Шаг 6: Коммит**

```bash
git add habibi_ai/engine.py habibi_ai/api.py habibi_ai/tests/
git commit -m "feat(agent): цикл инструментов ведёт прокси, а не движок"
```

---

### Задача 6: Консоль показывает цикл

**Файлы:**
- Изменить: `frontend/src/features/ai/types.ts`
- Изменить: `frontend/src/features/ai/TracePanel.tsx` (только словарь заголовков)

Репозиторий: `habibi_ui`.

**Интерфейсы:**
- Потребляет: форму ответа `send_message` из задачи 5.

Разбор шага уже идёт **по форме значения**, а не по списку известных полей —
новые поля отрисуются сами. Менять надо только подписи шагов и тип ответа.

- [ ] **Шаг 1: Обновить тип ответа**

В `frontend/src/features/ai/types.ts` заменить `SendResult`:

```ts
export interface SendResult {
  success: boolean;
  response: string;
  /**
   * Трассировка всех витков цикла за этот ход, а не одного вызова модели.
   * Приходит только обладателю роли Habibi AI Debug.
   */
  debug?: TraceStep[];
}
```

Поля `scenario_key` и `scenario_stack` удаляются: их больше не существует.

- [ ] **Шаг 2: Подписи новых шагов**

В `TracePanel.tsx`, в `TITLES`, заменить содержимое на:

```tsx
const TITLES: Record<string, string> = {
  chat: "Состояние чата",
  tools: "Предложенные инструменты",
  completion: "Запрос в модель",
  tool_use: "Вызов инструмента",
  answer: "Ответ пользователю",
};
```

Шаги `router`, `stack`, `scenario` и `auto_return` удаляются — механизмов,
которые их порождали, больше нет. Незнакомый шаг всё равно отрисуется под своим
сырым ключом, это уже заложено.

- [ ] **Шаг 3: Проверить**

```bash
cd frontend && npx tsc --noEmit -p tsconfig.json
cd .. && yarn build
```

Ожидается: обе команды чисто. Если `tsc` покажет обращения к удалённым полям
`scenario_key`/`scenario_stack` — убрать их по месту; экран чата их не читал.

- [ ] **Шаг 4: Коммит**

```bash
git add frontend/src/features/ai/
git commit -m "feat(agent): консоль показывает витки цикла вместо стека сценариев"
```

---

### Задача 7: Живая проверка

Выполняется человеком: нужен ключ LLM, живой вызов модели и данные ERP.

- [ ] **Шаг 1: Настроить тестового бота**

В админке `ai.habibi-erp.com` или через MCP у бота 1:

* в `chatbot_scenarios` для сценария `order` выставить `tools: ["get_menu"]`;
* в `global_system_prompt` убедиться, что нет прозаического перечисления цен —
  бот должен спрашивать меню, а не пересказывать его.

- [ ] **Шаг 2: Прогнать диалог**

```
./habibi/dev.sh check      # среда цела
```

Открыть `http://localhost:5173/ui/ai`, спросить «что у вас есть?».

Ожидается: в трассировке виден шаг **Вызов инструмента** с `get_menu`, затем
ответ, где позиции совпадают с `Item` в ERPNext.

- [ ] **Шаг 3: Проверить, что бот не выдумывает**

Спросить про заведомо отсутствующую позицию: «а пицца есть?».

Ожидается: бот отвечает, что такой позиции нет, **не придумывая цену**. Если
придумал — это находка, и она означает, что инструкция сценария недостаточно
строга; фиксируется и правится в Directus, а не в коде.
