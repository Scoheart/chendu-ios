import { RetryableError, StopError, complete, completeList, type Provider, type Usage } from "./llm.ts";
import type { IssueBlock, IssueDraft, IssueNote, IssuePattern, IssueWord } from "./issue.ts";
import { profileVars, renderPrompt, type LearnerProfile } from "./prompt.ts";

export interface Candidate {
  title: string;
  url: string;
  publishedAt: string | null;
  text: string;
}

export interface ComposeArgs {
  date: string;
  topic: string;
  topicLabel: string;
  dateLabel: string;
  profile: LearnerProfile;
  templates: { select: string; annotate: string; vocab: string; patterns: string };
  candidates: Candidate[];
  provider: Provider;
  model: string;
  apiKey: string;
  fetchImpl?: typeof fetch;
}

export interface ComposeResult {
  issue: IssueDraft;
  prompts: { select: string; annotate: string; vocab: string; patterns: string };
  usage: Usage;
  costUsd: number;
}

const selectSchema = {
  type: "object" as const,
  required: ["index", "reason"],
  properties: { reason: { type: "string" as const } },
};

const annotateSchema = {
  type: "object" as const,
  required: ["zh_title", "byline", "lead", "blocks", "notes"],
  properties: {
    zh_title: { type: "string" as const },
    byline: { type: "string" as const },
    lead: { type: "string" as const },
    blocks: { type: "array" as const },
    notes: { type: "array" as const },
  },
};

function addUsage(left: Usage, right: Usage): Usage {
  return {
    inputTokens: left.inputTokens + right.inputTokens,
    outputTokens: left.outputTokens + right.outputTokens,
  };
}

function asString(value: unknown, field: string): string {
  if (typeof value !== "string") throw new RetryableError(`field ${field} is ${typeof value}`);
  return value;
}

function blocksOf(value: unknown): IssueBlock[] {
  if (!Array.isArray(value) || value.length === 0) throw new RetryableError("missing blocks");
  return value.map((block, index) => {
    if (block === null || typeof block !== "object") throw new RetryableError(`block ${index} is not an object`);
    const row = block as Record<string, unknown>;
    const kind = row.kind;
    if (kind !== "para" && kind !== "gap") throw new RetryableError(`block ${index} kind`);
    const segments = row.segments;
    if (kind === "gap") return { kind, segments: [] };
    if (!Array.isArray(segments) || segments.length === 0) throw new RetryableError(`block ${index} segments`);
    return {
      kind,
      segments: segments.map((segment) => {
        if (segment === null || typeof segment !== "object") throw new RetryableError("segment");
        const item = segment as Record<string, unknown>;
        const text = asString(item.text, "segment.text");
        const note = item.note == null ? undefined : Number(item.note);
        if (note != null && !Number.isInteger(note)) throw new RetryableError("segment.note");
        return note == null ? { text } : { text, note };
      }),
    };
  });
}

function notesOf(value: unknown): IssueNote[] {
  if (!Array.isArray(value)) throw new RetryableError("missing notes");
  return value.map((note) => {
    if (note === null || typeof note !== "object") throw new RetryableError("note");
    const row = note as Record<string, unknown>;
    for (const key of ["n", "kind", "tag", "head", "body"]) {
      if (!(key in row)) throw new RetryableError(`missing ${key}`);
    }
    const kind = row.kind;
    if (kind !== "vocab" && kind !== "grammar" && kind !== "idiom") {
      throw new RetryableError("note.kind");
    }
    return {
      n: Number(row.n),
      kind,
      tag: asString(row.tag, "tag"),
      head: asString(row.head, "head"),
      body: asString(row.body, "body"),
      tilt: 0,
    };
  });
}

function wordsOf(items: Record<string, unknown>[]): IssueWord[] {
  return items.map((row) => ({
    word: asString(row.word, "word"),
    ipa: asString(row.ipa, "ipa"),
    meaning: asString(row.meaning, "meaning"),
    example: asString(row.example, "example"),
  }));
}

function patternsOf(items: Record<string, unknown>[]): IssuePattern[] {
  return items.map((row) => ({
    pattern: asString(row.pattern, "pattern"),
    patternZh: asString(row.pattern_zh, "pattern_zh"),
    source: asString(row.source, "source"),
    model: asString(row.model, "model"),
    modelZh: asString(row.model_zh, "model_zh"),
  }));
}

export async function composeIssue(args: ComposeArgs): Promise<ComposeResult> {
  const base = profileVars(args.profile, { topic: args.topic });
  const selectPrompt = renderPrompt(args.templates.select, {
    ...base,
    candidates: JSON.stringify(args.candidates.map((item) => ({
      title: item.title,
      url: item.url,
      published_at: item.publishedAt,
      text: item.text,
    }))),
  });
  const selected = await complete({
    provider: args.provider,
    model: args.model,
    apiKey: args.apiKey,
    schema: selectSchema,
    prompt: selectPrompt,
    fetchImpl: args.fetchImpl,
  });
  const index = selected.json.index;
  if (index === null) throw new StopError(asString(selected.json.reason, "reason"));
  if (typeof index !== "number" || !Number.isInteger(index) || index < 0 || index >= args.candidates.length) {
    throw new RetryableError("select index is out of range");
  }
  const chosen = args.candidates[index];
  const shared = {
    ...base,
    title: chosen.title,
    source_url: chosen.url,
    excerpt: chosen.text,
  };
  const annotatePrompt = renderPrompt(args.templates.annotate, shared);
  const vocabPrompt = renderPrompt(args.templates.vocab, shared);
  const patternsPrompt = renderPrompt(args.templates.patterns, shared);
  const call = { provider: args.provider, model: args.model, apiKey: args.apiKey, fetchImpl: args.fetchImpl };
  const annotated = await complete({ ...call, schema: annotateSchema, prompt: annotatePrompt });
  const vocab = await completeList({ ...call, prompt: vocabPrompt, itemRequired: ["word", "ipa", "meaning", "example"] });
  const patterns = await completeList({
    ...call,
    prompt: patternsPrompt,
    itemRequired: ["pattern", "pattern_zh", "source", "model", "model_zh"],
  });
  const usage = addUsage(addUsage(selected.usage, annotated.usage), addUsage(vocab.usage, patterns.usage));
  const issue: IssueDraft = {
    date: args.date,
    topic: args.topic,
    topicLabel: args.topicLabel,
    dateLabel: args.dateLabel,
    title: chosen.title,
    zhTitle: asString(annotated.json.zh_title, "zh_title"),
    byline: asString(annotated.json.byline, "byline"),
    lead: asString(annotated.json.lead, "lead"),
    blocks: blocksOf(annotated.json.blocks),
    notes: notesOf(annotated.json.notes),
    credit: { text: chosen.title, links: [{ title: chosen.title, url: chosen.url }] },
    audio: [],
    words: wordsOf(vocab.items),
    patterns: patternsOf(patterns.items),
    podcast: null,
  };
  return {
    issue,
    prompts: { select: selectPrompt, annotate: annotatePrompt, vocab: vocabPrompt, patterns: patternsPrompt },
    usage,
    costUsd: selected.costUsd + annotated.costUsd + vocab.costUsd + patterns.costUsd,
  };
}
