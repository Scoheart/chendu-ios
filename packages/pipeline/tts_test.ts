import { SLOW_SPEED, synthesize, type SpeechRequest } from "./tts.ts";
import { StopError } from "./llm.ts";

const FIXED = new Uint8Array([0xff, 0xfb, 0x90]);

Deno.test("a fixture backend returns mp3 bytes", async () => {
  let seen: SpeechRequest | undefined;
  const result = await synthesize({
    provider: "openai",
    model: "tts-1",
    voice: "alloy",
    text: "The market opened quietly.",
    apiKey: "sk-test",
    backend: (request) => {
      seen = request;
      return Promise.resolve(FIXED);
    },
  });
  if (result.status !== "ok") throw new Error(result.status);
  if (result.kind !== "normal") throw new Error(result.kind);
  if (result.bytes.length !== 3 || result.bytes[0] !== 0xff) throw new Error("bytes");
  if (seen?.speed !== 1) throw new Error(String(seen?.speed));
});

Deno.test("slow is a second request at a lower speed", async () => {
  let seen: SpeechRequest | undefined;
  const result = await synthesize({
    provider: "openai",
    model: "tts-1",
    voice: "alloy",
    text: "The market opened quietly.",
    slow: true,
    apiKey: "sk-test",
    backend: (request) => {
      seen = request;
      return Promise.resolve(FIXED);
    },
  });
  if (result.status !== "ok" || result.kind !== "slow") throw new Error("kind");
  if (seen?.speed !== SLOW_SPEED) throw new Error(String(seen?.speed));
});

Deno.test("a missing key is skipped and does not call the backend", async () => {
  let called = false;
  const result = await synthesize({
    provider: "openai",
    model: "tts-1",
    voice: "alloy",
    text: "Hello",
    backend: () => {
      called = true;
      return Promise.resolve(FIXED);
    },
  });
  if (result.status !== "skipped" || result.reason !== "missing api key") throw new Error(result.status);
  if (called) throw new Error("backend ran");
});

Deno.test("openai fixture speech uses the audio endpoint", async () => {
  const result = await synthesize({
    provider: "openai",
    model: "tts-1",
    voice: "alloy",
    text: "Hello",
    apiKey: "sk-test-secret-ABCD",
    fetchImpl: (_url, init) => {
      const body = JSON.parse(String(init?.body)) as { speed: number };
      if (body.speed !== 1) throw new Error("speed");
      return Promise.resolve(new Response(FIXED, { status: 200 }));
    },
  });
  if (result.status !== "ok") throw new Error(result.status);
});

Deno.test("a rejected speech key stops without echoing the key", async () => {
  try {
    await synthesize({
      provider: "openai",
      model: "tts-1",
      voice: "alloy",
      text: "Hello",
      apiKey: "sk-test-secret-ABCD",
      fetchImpl: () => Promise.resolve(new Response("bad key sk-test-secret-ABCD", { status: 401 })),
    });
    throw new Error("should stop");
  } catch (error) {
    if (!(error instanceof StopError)) throw error;
    if (error.message.includes("sk-test-secret-ABCD")) throw new Error(error.message);
  }
});
