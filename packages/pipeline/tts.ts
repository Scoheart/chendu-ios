import { RetryableError, StopError } from "./llm.ts";
import { redactSecrets } from "./redact.ts";

export const SLOW_SPEED = 0.75;

export interface SpeechRequest {
  provider: string;
  model: string;
  voice: string;
  text: string;
  speed: number;
  apiKey: string;
}

export type SpeechBackend = (request: SpeechRequest, fetchImpl: typeof fetch) => Promise<Uint8Array>;

export interface SynthArgs {
  provider: string;
  model: string;
  voice: string;
  text: string;
  slow?: boolean;
  apiKey?: string;
  fetchImpl?: typeof fetch;
  backend?: SpeechBackend;
}

export type SynthResult =
  | { status: "ok"; kind: "normal" | "slow"; bytes: Uint8Array; voice: string }
  | { status: "skipped"; kind: "normal" | "slow"; reason: string };

function providerError(status: number, body: string, apiKey: string): Error {
  const cleaned = redactSecrets(body.split(apiKey).join("[redacted]"));
  if (cleaned.includes(apiKey)) return new StopError("provider error");
  if (status === 401 || status === 403) return new StopError(cleaned, status);
  return new RetryableError(cleaned);
}

export const openaiSpeech: SpeechBackend = async (request, fetchImpl) => {
  const response = await fetchImpl("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      authorization: `Bearer ${request.apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: request.model,
      voice: request.voice,
      input: request.text,
      speed: request.speed,
    }),
  });
  if (!response.ok) throw providerError(response.status, await response.text(), request.apiKey);
  return new Uint8Array(await response.arrayBuffer());
};

/** Second provider slot. A later backend can replace this without changing synthesize(). */
export const reservedSpeech: SpeechBackend = () => {
  return Promise.reject(new StopError("reserved tts provider is not configured"));
};

const backends: Record<string, SpeechBackend> = {
  openai: openaiSpeech,
  reserved: reservedSpeech,
};

export async function synthesize(args: SynthArgs): Promise<SynthResult> {
  const kind = args.slow ? "slow" : "normal";
  if (!args.apiKey) return { status: "skipped", kind, reason: "missing api key" };
  const backend = args.backend ?? backends[args.provider];
  if (!backend) return { status: "skipped", kind, reason: `provider ${args.provider} is not implemented` };
  const bytes = await backend({
    provider: args.provider,
    model: args.model,
    voice: args.voice,
    text: args.text,
    speed: args.slow ? SLOW_SPEED : 1,
    apiKey: args.apiKey,
  }, args.fetchImpl ?? fetch);
  return { status: "ok", kind, bytes, voice: args.voice };
}
