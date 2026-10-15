import { contentHash, wordsOf } from "./excerpt.ts";

export const FIXTURE_FILES = [
  "issue-2026-10-09.json",
  "issue-2026-10-10.json",
  "issue-2026-10-11.json",
] as const;

export interface FixtureSegment {
  text: string;
  note?: number;
}

export interface FixtureIssue {
  date: string;
  topic: string;
  topicLabel: string;
  title: string;
  zhTitle: string;
  byline: string;
  lead: string;
  blocks: { kind: string; segments: FixtureSegment[] }[];
  notes: { n: number; kind: string; tag: string; head: string; body: string }[];
  words: { word: string; ipa: string; meaning: string; example: string }[];
  patterns: { pattern: string; patternZh: string; source: string; model: string; modelZh: string }[];
  credit?: { text: string; links: { title: string; url: string }[] };
  podcast?: Record<string, unknown> | null;
  audio?: { id: string }[];
}

export interface ImportArgs {
  supabaseUrl: string;
  serviceKey: string;
  userId: string;
  fixtureDir: URL;
  confirmRemote?: boolean;
  fetchImpl?: typeof fetch;
}

export function assertImportTarget(url: string, confirmRemote: boolean): void {
  const parsed = new URL(url);
  const host = parsed.hostname;
  if (host === "vercel.app" || host.endsWith(".vercel.app")) {
    throw new Error("refusing that host");
  }
  const local = host === "127.0.0.1" || host === "localhost" || host === "::1";
  if (!local && !confirmRemote) throw new Error("refusing a non-local database");
}

export function articleBody(issue: FixtureIssue): string {
  return issue.blocks
    .filter((block) => block.kind === "para")
    .map((block) => block.segments.map((segment) => segment.text).join(""))
    .join("\n\n");
}

export function annotationRows(issue: FixtureIssue) {
  const located = new Map<number, { paragraph_index: number; start_utf16: number; length_utf16: number }>();
  let paragraphIndex = 0;
  for (const block of issue.blocks) {
    if (block.kind !== "para") continue;
    let offset = 0;
    for (const segment of block.segments) {
      if (segment.note != null) {
        located.set(segment.note, {
          paragraph_index: paragraphIndex,
          start_utf16: offset,
          length_utf16: segment.text.length,
        });
      }
      offset += segment.text.length;
    }
    paragraphIndex += 1;
  }
  return issue.notes.map((note) => {
    const place = located.get(note.n);
    return {
      n: note.n,
      kind: note.kind,
      tag: note.tag,
      head: note.head,
      body: note.body,
      paragraph_index: place?.paragraph_index ?? null,
      start_utf16: place?.start_utf16 ?? null,
      length_utf16: place?.length_utf16 ?? null,
    };
  });
}

export async function rowsFor(issue: FixtureIssue, userId: string, issueId: string, fixtureBytes: number) {
  const raw = articleBody(issue);
  const link = issue.credit?.links?.[0]?.url;
  if (!link) throw new Error(`missing source url for ${issue.date}`);
  return {
    article: {
      user_id: userId,
      external_url: link,
      title: issue.title,
      author: issue.byline,
      published_at: `${issue.date}T00:00:00Z`,
      raw_text: raw,
      excerpt: raw,
      word_count: wordsOf(raw).length,
      content_hash: await contentHash(raw),
      license_snapshot: "all-rights-reserved",
    },
    issue: {
      id: issueId,
      user_id: userId,
      issue_date: issue.date,
      topic: issue.topic,
      topic_label: issue.topicLabel,
      title: issue.title,
      zh_title: issue.zhTitle,
      byline: issue.byline,
      lead: issue.lead,
      blocks: issue.blocks,
      credit: issue.credit ?? null,
      podcast: issue.podcast ?? null,
      status: "ready",
      config_snapshot: { origin: "import" },
    },
    annotations: annotationRows(issue),
    vocab: issue.words.map((word, index) => ({
      position: index + 1,
      word: word.word,
      ipa: word.ipa,
      meaning: word.meaning,
      example: word.example,
    })),
    patterns: issue.patterns.map((pattern, index) => ({
      position: index + 1,
      pattern: pattern.pattern,
      pattern_zh: pattern.patternZh,
      source_sentence: pattern.source,
      model_sentence: pattern.model,
      model_zh: pattern.modelZh,
    })),
    audio: (issue.audio ?? []).map((track) => ({
      kind: track.id,
      storage_path: `audio/${userId}/${issueId}/${track.id}.mp3`,
      byte_size: fixtureBytes,
    })),
  };
}

function redact(text: string, secret: string): string {
  return text.replaceAll(secret, "[redacted]").slice(0, 240);
}

export async function importFixtures(args: ImportArgs): Promise<{ date: string; issueId: string }[]> {
  assertImportTarget(args.supabaseUrl, args.confirmRemote === true);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(args.userId)) {
    throw new Error("user id is not a uuid");
  }
  const fetchImpl = args.fetchImpl ?? fetch;
  const headers = {
    apikey: args.serviceKey,
    authorization: `Bearer ${args.serviceKey}`,
    "content-type": "application/json",
  };

  async function send(path: string, init?: RequestInit): Promise<unknown> {
    const response = await fetchImpl(`${args.supabaseUrl}${path}`, {
      ...init,
      headers: { ...headers, ...(init?.headers ?? {}) },
    });
    const text = await response.text();
    if (!response.ok) throw new Error(`${path} ${response.status} ${redact(text, args.serviceKey)}`);
    return text ? JSON.parse(text) : null;
  }

  const profiles = await send(`/rest/v1/profiles?id=eq.${args.userId}&select=id`) as { id: string }[];
  if (!Array.isArray(profiles) || profiles.length !== 1) throw new Error("user does not exist");

  const dates = "2026-10-09,2026-10-10,2026-10-11";
  const existing = await send(
    `/rest/v1/issues?user_id=eq.${args.userId}&issue_date=in.(${dates})&select=issue_date`,
  ) as { issue_date: string }[];
  if (existing.length > 0) throw new Error("those dates already exist for this user");

  const written: { date: string; issueId: string }[] = [];
  for (const name of FIXTURE_FILES) {
    const file = new URL(name, args.fixtureDir);
    const bytes = await Deno.readFile(file);
    const issue = JSON.parse(new TextDecoder().decode(bytes)) as FixtureIssue;
    const issueId = crypto.randomUUID();
    const mapped = await rowsFor(issue, args.userId, issueId, bytes.byteLength);

    for (const track of mapped.audio) {
      const objectPath = track.storage_path.replace(/^audio\//, "");
      const upload = await fetchImpl(`${args.supabaseUrl}/storage/v1/object/audio/${objectPath}`, {
        method: "POST",
        headers: {
          apikey: args.serviceKey,
          authorization: `Bearer ${args.serviceKey}`,
          "content-type": "audio/mpeg",
          "x-upsert": "true",
        },
        body: bytes as unknown as BodyInit,
      });
      if (!upload.ok) {
        const detail = redact(await upload.text(), args.serviceKey);
        throw new Error(`audio upload ${upload.status} ${detail}`);
      }
    }

    const inserted = await send("/rest/v1/articles", {
      method: "POST",
      headers: { prefer: "return=representation" },
      body: JSON.stringify(mapped.article),
    }) as { id: string }[];
    const articleId = inserted[0]?.id;
    if (!articleId) throw new Error("article insert returned no id");

    const withIssue = <T extends Record<string, unknown>>(rows: T[]) =>
      rows.map((row) => ({ ...row, issue_id: issueId }));

    await send("/rest/v1/issues", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({ ...mapped.issue, article_id: articleId }),
    });
    await send("/rest/v1/annotations", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify(withIssue(mapped.annotations)),
    });
    await send("/rest/v1/vocab", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify(withIssue(mapped.vocab)),
    });
    await send("/rest/v1/patterns", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify(withIssue(mapped.patterns)),
    });
    await send("/rest/v1/audio_assets", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify(withIssue(mapped.audio)),
    });
    written.push({ date: issue.date, issueId });
  }
  return written;
}

function option(name: string, argv: string[]): string | undefined {
  const index = argv.indexOf(name);
  if (index < 0 || index + 1 >= argv.length) return undefined;
  return argv[index + 1];
}

if (import.meta.main) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const userId = option("--user", Deno.args);
  if (!supabaseUrl || !serviceKey) throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
  if (!userId) throw new Error("--user is required");
  const written = await importFixtures({
    supabaseUrl,
    serviceKey,
    userId,
    fixtureDir: new URL("../../ChenduTests/Fixtures/", import.meta.url),
    confirmRemote: Deno.args.includes("--confirm-remote"),
  });
  for (const row of written) console.log(`${row.date} ${row.issueId}`);
}
