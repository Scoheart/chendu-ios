import { composeIssue, type Candidate } from "./compose.ts";
import { contentHash, excerptLimit, excerptText, wordsOf } from "./excerpt.ts";
import { fetchDocument } from "./fetch.ts";
import { parseHtml, parseRss } from "./extract.ts";
import type { IssueDraft } from "./issue.ts";
import { RetryableError, StopError, type Provider } from "./llm.ts";
import type { LearnerProfile } from "./prompt.ts";
import { redactSecrets } from "./redact.ts";
import { synthesize } from "./tts.ts";

export interface WorkerLog {
  job_id: string;
  user_id: string;
  step: string;
  attempt: number;
}

export interface RunOnceArgs {
  supabaseUrl: string;
  serviceKey: string;
  fetchImpl?: typeof fetch;
  documentFetch?: typeof fetch;
  llmFetch?: typeof fetch;
  keys?: { llm?: string; tts?: string };
  log?: (event: WorkerLog) => void;
  workerId?: string;
}

const TOPIC_LABEL: Record<string, string> = {
  stocks: "股市",
  ai: "AI",
  general: "综合",
};

export function failureOf(error: unknown): { stop: boolean; message: string } {
  if (error instanceof StopError && (error.status === 401 || error.status === 403)) {
    return { stop: true, message: "key needs resave" };
  }
  if (error instanceof StopError) return { stop: true, message: redactSecrets(error.message) };
  const message = error instanceof Error ? error.message : "failed";
  return { stop: false, message: redactSecrets(message) };
}

export function issueDate(now: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

function dateLabel(isoDate: string): string {
  const [, month, day] = isoDate.split("-");
  return `${Number(month)}月${Number(day)}日`;
}

function emit(args: RunOnceArgs, event: WorkerLog) {
  const line: WorkerLog = {
    job_id: event.job_id,
    user_id: event.user_id,
    step: event.step,
    attempt: event.attempt,
  };
  if (args.log) args.log(line);
  else console.log(JSON.stringify(line));
}

function rest(args: RunOnceArgs) {
  const fetchImpl = args.fetchImpl ?? fetch;
  const headers = {
    apikey: args.serviceKey,
    authorization: `Bearer ${args.serviceKey}`,
    "content-type": "application/json",
  };
  return {
    async rpc<T>(name: string, body: Record<string, unknown>): Promise<T> {
      const response = await fetchImpl(`${args.supabaseUrl}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers,
        body: JSON.stringify(body),
      });
      const text = await response.text();
      if (!response.ok) throw new RetryableError(redactSecrets(text).slice(0, 300));
      return text ? JSON.parse(text) as T : null as T;
    },
    async get<T>(path: string): Promise<T> {
      const response = await fetchImpl(`${args.supabaseUrl}/rest/v1/${path}`, { headers });
      const text = await response.text();
      if (!response.ok) throw new RetryableError(redactSecrets(text).slice(0, 300));
      return JSON.parse(text) as T;
    },
    async patch(path: string, body: Record<string, unknown>): Promise<void> {
      const response = await fetchImpl(`${args.supabaseUrl}/rest/v1/${path}`, {
        method: "PATCH",
        headers: { ...headers, prefer: "return=minimal" },
        body: JSON.stringify(body),
      });
      if (!response.ok) {
        throw new RetryableError(redactSecrets(await response.text()).slice(0, 300));
      }
    },
  };
}

interface JobRow {
  id: string;
  user_id: string;
  attempts: number;
  status: string;
}

interface ProfileRow {
  id: string;
  learner_level: string;
  explanation_lang: string;
  annotation_depth: string;
  annotation_kinds: string[];
  excerpt_words: number;
  vocab_count: number;
  include_ipa: boolean;
  pattern_count: number;
  tasks: {
    select?: { provider?: string; model?: string };
    tts?: { provider?: string; model?: string; voice?: string };
  };
}

interface TemplateRow {
  id: string;
  owner_id: string | null;
  task: string;
  version: number;
  body: string;
}

interface SourceRow {
  id: string;
  kind: string;
  url: string;
  topic: string | null;
  license: string;
  config: { excerpt_cap?: number };
  enabled: boolean;
}

interface Prepared {
  candidate: Candidate;
  raw: string;
  license: string;
  sourceId: string;
}

function learner(row: ProfileRow): LearnerProfile {
  return {
    learnerLevel: row.learner_level,
    explanationLang: row.explanation_lang,
    annotationDepth: row.annotation_depth,
    annotationKinds: row.annotation_kinds,
    excerptWords: row.excerpt_words,
    vocabCount: row.vocab_count,
    includeIpa: row.include_ipa,
    patternCount: row.pattern_count,
  };
}

async function prepareSource(
  source: SourceRow,
  excerptWords: number,
  documentFetch: typeof fetch,
): Promise<Prepared[]> {
  const doc = await fetchDocument(source.url, documentFetch);
  if (doc.status >= 400) throw new RetryableError(`source fetch ${doc.status}`);
  const cap = source.config?.excerpt_cap;
  const limit = excerptLimit(excerptWords, source.license, cap);
  const pages = source.kind === "rss" || doc.body.includes("<item")
    ? parseRss(doc.body).slice(0, 5).map((item) => ({
      title: item.title,
      url: item.link || source.url,
      publishedAt: item.publishedAt,
      html: false,
      text: item.description,
    }))
    : [{
      title: parseHtml(doc.body).title,
      url: parseHtml(doc.body).link || source.url,
      publishedAt: parseHtml(doc.body).publishedAt,
      html: true,
      text: parseHtml(doc.body).body,
    }];

  const prepared: Prepared[] = [];
  for (const page of pages) {
    let raw = page.text;
    if (!page.html && page.url !== source.url) {
      const linked = await fetchDocument(page.url, documentFetch);
      if (linked.status < 400 && /<html|<article/i.test(linked.body)) {
        const article = parseHtml(linked.body);
        if (article.body) raw = article.body;
      }
    }
    const excerpt = excerptText(raw, limit);
    if (!excerpt) continue;
    prepared.push({
      candidate: { title: page.title, url: page.url, publishedAt: page.publishedAt, text: excerpt },
      raw,
      license: source.license,
      sourceId: source.id,
    });
  }
  return prepared;
}

function plainText(issue: IssueDraft): string {
  return issue.blocks
    .filter((block) => block.kind === "para")
    .map((block) => block.segments.map((segment) => segment.text).join(""))
    .join("\n\n");
}

function annotationsOf(issue: IssueDraft) {
  const paragraphFor = new Map<number, number>();
  let paragraph = 0;
  for (const block of issue.blocks) {
    if (block.kind === "gap") continue;
    for (const segment of block.segments) {
      if (segment.note != null && !paragraphFor.has(segment.note)) paragraphFor.set(segment.note, paragraph);
    }
    paragraph += 1;
  }
  return issue.notes.map((note) => ({
    n: note.n,
    kind: note.kind,
    tag: note.tag,
    head: note.head,
    body: note.body,
    paragraph_index: paragraphFor.get(note.n) ?? null,
  }));
}

export async function runOnce(args: RunOnceArgs): Promise<{ jobId: string | null; status: string }> {
  const db = rest(args);
  const claimed = await db.rpc<JobRow[]>("claim_next_job", { p_worker: args.workerId ?? "local" });
  const job = Array.isArray(claimed) ? claimed[0] : claimed;
  if (!job?.id) return { jobId: null, status: "idle" };

  const step = (name: string) => emit(args, {
    job_id: job.id,
    user_id: job.user_id,
    step: name,
    attempt: job.attempts,
  });

  try {
    step("snapshot");
    const [profile] = await db.get<ProfileRow[]>(
      `generation_profiles?user_id=eq.${job.user_id}&select=id,learner_level,explanation_lang,annotation_depth,annotation_kinds,excerpt_words,vocab_count,include_ipa,pattern_count,tasks`,
    );
    const [settings] = await db.get<{ timezone: string }[]>(
      `user_settings?user_id=eq.${job.user_id}&select=timezone`,
    );
    const templates = await db.get<TemplateRow[]>(
      `prompt_templates?or=(owner_id.eq.${job.user_id},owner_id.is.null)&select=id,owner_id,task,version,body`,
    );
    const picked = new Map<string, TemplateRow>();
    for (const template of templates) {
      const current = picked.get(template.task);
      if (!current || (template.owner_id && !current.owner_id)) picked.set(template.task, template);
    }
    const provider = (profile.tasks?.select?.provider ?? "openai") as Provider;
    const model = profile.tasks?.select?.model ?? "gpt-4.1-mini";
    const voice = profile.tasks?.tts?.voice ?? "alloy";
    const ttsModel = profile.tasks?.tts?.model ?? "tts-1";
    const snapshot = {
      profile_id: profile.id,
      learner_level: profile.learner_level,
      explanation_lang: profile.explanation_lang,
      annotation_depth: profile.annotation_depth,
      annotation_kinds: profile.annotation_kinds,
      excerpt_words: profile.excerpt_words,
      vocab_count: profile.vocab_count,
      include_ipa: profile.include_ipa,
      pattern_count: profile.pattern_count,
      templates: Object.fromEntries(
        [...picked.entries()].map(([task, template]) => [task, { id: template.id, version: template.version }]),
      ),
      provider,
      model,
      voice,
      timezone: settings?.timezone ?? "Asia/Shanghai",
    };
    await db.patch(`jobs?id=eq.${job.id}`, { config_snapshot: snapshot, provider, model });

    step("fetch");
    const subscriptions = await db.get<{ sources: SourceRow }[]>(
      `subscriptions?user_id=eq.${job.user_id}&enabled=eq.true&select=sources(id,kind,url,topic,license,config,enabled)`,
    );
    const documentFetch = args.documentFetch ?? args.fetchImpl ?? fetch;
    const prepared: Prepared[] = [];
    for (const row of subscriptions) {
      if (!row.sources?.enabled) continue;
      prepared.push(...await prepareSource(row.sources, profile.excerpt_words, documentFetch));
    }
    if (prepared.length === 0) throw new RetryableError("no source text");

    const llmKey = args.keys?.llm;
    if (!llmKey) throw new StopError("key needs resave", 401);

    step("compose");
    const day = issueDate(new Date(), snapshot.timezone);
    const topic = subscriptions[0].sources.topic ?? "general";
    const composed = await composeIssue({
      date: day,
      topic,
      topicLabel: TOPIC_LABEL[topic] ?? "综合",
      dateLabel: dateLabel(day),
      profile: learner(profile),
      templates: {
        select: picked.get("select")!.body,
        annotate: picked.get("annotate")!.body,
        vocab: picked.get("vocab")!.body,
        patterns: picked.get("patterns")!.body,
      },
      candidates: prepared.map((item) => item.candidate),
      provider,
      model,
      apiKey: llmKey,
      fetchImpl: args.llmFetch ?? args.fetchImpl,
    });
    const chosen = prepared.find((item) => item.candidate.url === composed.issue.credit?.links[0]?.url) ?? prepared[0];
    const spoken = plainText(composed.issue);
    const audio: { kind: string; storage_path: string; voice: string; byte_size: number }[] = [];
    const issueId = crypto.randomUUID();

    step("tts");
    for (const slow of [false, true]) {
      const speech = await synthesize({
        provider: profile.tasks?.tts?.provider ?? "openai",
        model: ttsModel,
        voice,
        text: spoken,
        slow,
        apiKey: args.keys?.tts,
        fetchImpl: args.llmFetch ?? args.fetchImpl,
      });
      if (speech.status === "skipped") continue;
      const objectPath = `${job.user_id}/${issueId}/${speech.kind}.mp3`;
      const upload = await (args.fetchImpl ?? fetch)(
        `${args.supabaseUrl}/storage/v1/object/audio/${objectPath}`,
        {
          method: "POST",
          headers: {
            apikey: args.serviceKey,
            authorization: `Bearer ${args.serviceKey}`,
            "content-type": "audio/mpeg",
            "x-upsert": "true",
          },
          body: speech.bytes as unknown as BodyInit,
        },
      );
      if (!upload.ok) throw new RetryableError(`audio upload ${upload.status}`);
      audio.push({
        kind: speech.kind,
        storage_path: `audio/${objectPath}`,
        voice,
        byte_size: speech.bytes.byteLength,
      });
    }

    step("commit");
    await db.rpc<string>("commit_generated_issue", {
      p_job_id: job.id,
      p_payload: {
        issue_id: issueId,
        article: {
          source_id: chosen.sourceId,
          external_url: chosen.candidate.url,
          title: chosen.candidate.title,
          published_at: chosen.candidate.publishedAt,
          raw_text: chosen.raw,
          excerpt: chosen.candidate.text,
          word_count: wordsOf(chosen.candidate.text).length,
          content_hash: await contentHash(chosen.raw),
          license_snapshot: chosen.license,
        },
        issue: {
          issue_date: composed.issue.date,
          topic: composed.issue.topic,
          topic_label: composed.issue.topicLabel,
          title: composed.issue.title,
          zh_title: composed.issue.zhTitle,
          byline: composed.issue.byline,
          lead: composed.issue.lead,
          blocks: composed.issue.blocks,
          credit: composed.issue.credit,
          podcast: null,
        },
        annotations: annotationsOf(composed.issue),
        vocab: composed.issue.words,
        patterns: composed.issue.patterns,
        audio,
        usage: {
          provider,
          model,
          input_tokens: composed.usage.inputTokens,
          output_tokens: composed.usage.outputTokens,
          audio_chars: audio.length ? spoken.length : 0,
          cost_usd: composed.costUsd,
        },
      },
    });
    return { jobId: job.id, status: "succeeded" };
  } catch (error) {
    const failure = failureOf(error);
    step(failure.stop ? "stop" : "retry");
    await db.rpc("fail_job", { p_job_id: job.id, p_error: failure.message, p_stop: failure.stop });
    return { jobId: job.id, status: failure.stop ? "failed" : "queued" };
  }
}

if (import.meta.main) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
    Deno.exit(1);
  }
  const result = await runOnce({
    supabaseUrl,
    serviceKey,
    keys: {
      llm: Deno.env.get("OPENAI_API_KEY") ?? undefined,
      tts: Deno.env.get("OPENAI_TTS_API_KEY") ?? undefined,
    },
  });
  if (!result.jobId) {
    console.log(JSON.stringify({ job_id: null, user_id: null, step: "idle", attempt: 0 }));
  }
}
