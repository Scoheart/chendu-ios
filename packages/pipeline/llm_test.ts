import { complete, RetryableError, StopError, type JsonSchema } from "./llm.ts";

const schema: JsonSchema = {
  type: "object",
  required: ["index"],
  properties: { index: { type: "number" } },
};

const KEY = "sk-test-secret-ABCD";

function fake(url: string, body: unknown, status = 200): typeof fetch {
  return () =>
    Promise.resolve(
      new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
      }),
    );
}

Deno.test("openai fixture returns json and a cost", async () => {
  const result = await complete({
    provider: "openai",
    model: "gpt-4.1-mini",
    apiKey: KEY,
    schema,
    prompt: "pick",
    fetchImpl: fake("https://api.openai.com/v1/chat/completions", {
      choices: [{ message: { content: JSON.stringify({ index: 1 }) } }],
      usage: { prompt_tokens: 1000, completion_tokens: 100 },
    }),
  });
  if (result.json.index !== 1) throw new Error("index");
  if (result.usage.inputTokens !== 1000) throw new Error("tokens");
  if (result.costUsd <= 0) throw new Error("cost");
});

Deno.test("anthropic fixture returns json", async () => {
  const result = await complete({
    provider: "anthropic",
    model: "claude-sonnet-4-5",
    apiKey: KEY,
    schema,
    prompt: "pick",
    fetchImpl: fake("https://api.anthropic.com/v1/messages", {
      content: [{ text: JSON.stringify({ index: 0 }) }],
      usage: { input_tokens: 10, output_tokens: 5 },
    }),
  });
  if (result.json.index !== 0) throw new Error("index");
});

Deno.test("xai fixture returns json", async () => {
  const result = await complete({
    provider: "xai",
    model: "grok-4",
    apiKey: KEY,
    schema,
    prompt: "pick",
    fetchImpl: fake("https://api.x.ai/v1/chat/completions", {
      choices: [{ message: { content: JSON.stringify({ index: 2 }) } }],
      usage: { prompt_tokens: 8, completion_tokens: 4 },
    }),
  });
  if (result.json.index !== 2) throw new Error("index");
});

Deno.test("schema mismatch is retryable", async () => {
  try {
    await complete({
      provider: "openai",
      model: "gpt-4.1-mini",
      apiKey: KEY,
      schema,
      prompt: "pick",
      fetchImpl: fake("https://api.openai.com/v1/chat/completions", {
        choices: [{ message: { content: JSON.stringify({ nope: true }) } }],
        usage: { prompt_tokens: 1, completion_tokens: 1 },
      }),
    });
    throw new Error("should have failed");
  } catch (error) {
    if (!(error instanceof RetryableError)) throw error;
  }
});

Deno.test("provider error does not echo the key", async () => {
  try {
    await complete({
      provider: "openai",
      model: "gpt-4.1-mini",
      apiKey: KEY,
      schema,
      prompt: "pick",
      fetchImpl: fake("https://api.openai.com/v1/chat/completions", {
        error: `bad key ${KEY}`,
      }, 401),
    });
    throw new Error("should have failed");
  } catch (error) {
    if (!(error instanceof StopError)) throw error;
    if (error.message.includes(KEY)) throw new Error(error.message);
  }
});
