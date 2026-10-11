/** USD per token. Estimates only; the platform does not bill. */
const PER_TOKEN: Record<string, { input: number; output: number }> = {
  "gpt-4.1-mini": { input: 0.4 / 1_000_000, output: 1.6 / 1_000_000 },
  "claude-sonnet-4-5": { input: 3 / 1_000_000, output: 15 / 1_000_000 },
  "grok-4": { input: 3 / 1_000_000, output: 15 / 1_000_000 },
};

const FALLBACK = { input: 1 / 1_000_000, output: 1 / 1_000_000 };

export function costUsd(model: string, inputTokens: number, outputTokens: number): number {
  const price = PER_TOKEN[model] ?? FALLBACK;
  const usd = inputTokens * price.input + outputTokens * price.output;
  return Math.round(usd * 1_000_000) / 1_000_000;
}
