import { redactSecrets } from "./redact.ts";
import { costUsd } from "./pricing.ts";

export type Provider = "openai" | "anthropic" | "xai";

export class RetryableError extends Error {
  readonly retryable = true;
}

export class StopError extends Error {
  readonly retryable = false;
}

export interface Usage {
  inputTokens: number;
  outputTokens: number;
}

export interface JsonSchema {
  type: "object";
  required?: string[];
  properties?: Record<string, { type: "string" | "number" | "boolean" | "object" | "array" }>;
}

export interface CompleteArgs {
  provider: Provider;
  model: string;
  apiKey: string;
  schema: JsonSchema;
  prompt: string;
  fetchImpl?: typeof fetch;
}

export interface CompleteResult {
  json: Record<string, unknown>;
  usage: Usage;
  costUsd: number;
}

const URLS: Record<Provider, string> = {
  openai: "https://api.openai.com/v1/chat/completions",
  xai: "https://api.x.ai/v1/chat/completions",
  anthropic: "https://api.anthropic.com/v1/messages",
};

function fail(status: number, body: string, apiKey: string): Error {
  const cleaned = redactSecrets(body.split(apiKey).join("[redacted]"));
  if (cleaned.includes(apiKey)) {
    return new StopError("provider error");
  }
  if (status === 401 || status === 403) return new StopError(cleaned);
  return new RetryableError(cleaned);
}

function checkSchema(value: unknown, schema: JsonSchema): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new RetryableError("model json is not an object");
  }
  const obj = value as Record<string, unknown>;
  for (const key of schema.required ?? []) {
    if (!(key in obj)) throw new RetryableError(`missing ${key}`);
  }
  for (const [key, spec] of Object.entries(schema.properties ?? {})) {
    if (!(key in obj) || obj[key] == null) continue;
    const actual = Array.isArray(obj[key]) ? "array" : typeof obj[key];
    if (actual !== spec.type) throw new RetryableError(`field ${key} is ${actual}`);
  }
  return obj;
}

function chatBody(args: CompleteArgs): unknown {
  if (args.provider === "anthropic") {
    return {
      model: args.model,
      max_tokens: 4096,
      messages: [{ role: "user", content: args.prompt }],
    };
  }
  return {
    model: args.model,
    messages: [{ role: "user", content: args.prompt }],
    response_format: { type: "json_object" },
  };
}

function parseContent(provider: Provider, payload: Record<string, unknown>): { text: string; usage: Usage } {
  if (provider === "anthropic") {
    const blocks = payload.content as Array<{ text?: string }> | undefined;
    const usage = payload.usage as { input_tokens?: number; output_tokens?: number } | undefined;
    return {
      text: blocks?.[0]?.text ?? "",
      usage: {
        inputTokens: usage?.input_tokens ?? 0,
        outputTokens: usage?.output_tokens ?? 0,
      },
    };
  }
  const choices = payload.choices as Array<{ message?: { content?: string } }> | undefined;
  const usage = payload.usage as { prompt_tokens?: number; completion_tokens?: number } | undefined;
  return {
    text: choices?.[0]?.message?.content ?? "",
    usage: {
      inputTokens: usage?.prompt_tokens ?? 0,
      outputTokens: usage?.completion_tokens ?? 0,
    },
  };
}

interface ModelPayload {
  json: unknown;
  usage: Usage;
}

async function callProvider(args: CompleteArgs): Promise<ModelPayload> {
  const fetchImpl = args.fetchImpl ?? fetch;
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (args.provider === "anthropic") {
    headers["x-api-key"] = args.apiKey;
    headers["anthropic-version"] = "2023-06-01";
  } else {
    headers.authorization = `Bearer ${args.apiKey}`;
  }
  let response: Response;
  try {
    response = await fetchImpl(URLS[args.provider], {
      method: "POST",
      headers,
      body: JSON.stringify(chatBody(args)),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "fetch failed";
    throw new RetryableError(redactSecrets(message.split(args.apiKey).join("[redacted]")));
  }
  const raw = await response.text();
  if (!response.ok) throw fail(response.status, raw, args.apiKey);
  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    throw new RetryableError("provider returned non-json");
  }
  const parsed = parseContent(args.provider, payload);
  try {
    return { json: JSON.parse(parsed.text), usage: parsed.usage };
  } catch {
    throw new RetryableError("model content is not json");
  }
}

export async function complete(args: CompleteArgs): Promise<CompleteResult> {
  const parsed = await callProvider(args);
  return {
    json: checkSchema(parsed.json, args.schema),
    usage: parsed.usage,
    costUsd: costUsd(args.model, parsed.usage.inputTokens, parsed.usage.outputTokens),
  };
}

export async function completeList(
  args: Omit<CompleteArgs, "schema"> & { itemRequired: string[] },
): Promise<{ items: Record<string, unknown>[]; usage: Usage; costUsd: number }> {
  const parsed = await callProvider({ ...args, schema: { type: "object" } });
  if (!Array.isArray(parsed.json)) throw new RetryableError("model json is not an array");
  const items: Record<string, unknown>[] = [];
  for (const item of parsed.json) {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      throw new RetryableError("list item is not an object");
    }
    const row = item as Record<string, unknown>;
    for (const key of args.itemRequired) {
      if (!(key in row)) throw new RetryableError(`missing ${key}`);
    }
    items.push(row);
  }
  return {
    items,
    usage: parsed.usage,
    costUsd: costUsd(args.model, parsed.usage.inputTokens, parsed.usage.outputTokens),
  };
}
