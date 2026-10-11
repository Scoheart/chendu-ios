const RESERVED_CAP = 500;

export function excerptLimit(
  excerptWords: number,
  license: string,
  configuredCap?: number,
): number {
  const name = license.trim().toLowerCase();
  const permissive = name.startsWith("cc") || name === "public-domain" || name === "public domain";
  const cap = permissive ? (configuredCap ?? 100_000) : RESERVED_CAP;
  const requested = Number.isFinite(excerptWords) ? Math.max(0, Math.floor(excerptWords)) : 0;
  return Math.min(requested, cap);
}

export function wordsOf(text: string): string[] {
  return text.trim().split(/\s+/).filter(Boolean);
}

export function excerptText(text: string, limit: number): string {
  if (limit <= 0) return "";
  const paragraphs = text.trim().split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
  const out: string[] = [];
  let used = 0;
  for (const paragraph of paragraphs) {
    const words = wordsOf(paragraph);
    if (used + words.length <= limit) {
      out.push(words.join(" "));
      used += words.length;
      continue;
    }
    const remain = limit - used;
    if (remain > 0) out.push(words.slice(0, remain).join(" "));
    break;
  }
  if (out.length > 0) return out.join("\n\n");
  return wordsOf(text).slice(0, limit).join(" ");
}

export function normalizeBody(text: string): string {
  return text.trim().replace(/\s+/g, " ");
}

export async function contentHash(text: string): Promise<string> {
  const data = new TextEncoder().encode(normalizeBody(text));
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
