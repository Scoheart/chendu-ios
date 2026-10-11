import { annotationRows, articleBody, assertImportTarget, importFixtures, rowsFor } from "./import_issue.ts";
import type { FixtureIssue } from "./import_issue.ts";

const user = "11111111-1111-4111-8111-111111111111";
const fixtures = new URL("../../ChenduTests/Fixtures/", import.meta.url);

async function load(name: string): Promise<FixtureIssue> {
  return JSON.parse(await Deno.readTextFile(new URL(name, fixtures))) as FixtureIssue;
}

Deno.test("fixture rows drop tilt and mark the snapshot as import", async () => {
  const issue = await load("issue-2026-10-09.json");
  const raw = await Deno.readFile(new URL("issue-2026-10-09.json", fixtures));
  const rows = await rowsFor(issue, user, "cccccccc-cccc-4ccc-8ccc-cccccccccccc", raw.byteLength);
  if (rows.issue.config_snapshot.origin !== "import") throw new Error("origin");
  if (Object.keys(rows.issue.config_snapshot).join() !== "origin") throw new Error("snapshot fields");
  if (rows.annotations.length !== issue.notes.length) throw new Error("note count");
  if (rows.annotations.some((row) => "tilt" in row)) throw new Error("tilt kept");
  if (rows.annotations.some((row) => row.paragraph_index == null)) throw new Error("unplaced note");
  if (rows.annotations[0].head !== issue.notes[0].head) throw new Error("head");
  if (rows.vocab[0].position !== 1 || rows.patterns[0].source_sentence !== issue.patterns[0].source) {
    throw new Error("child rows");
  }
  if (rows.audio.map((row) => row.kind).join() !== "normal,slow") throw new Error("audio kinds");
  if (!rows.audio[0].storage_path.endsWith("/cccccccc-cccc-4ccc-8ccc-cccccccccccc/normal.mp3")) {
    throw new Error(rows.audio[0].storage_path);
  }
  if (rows.article.word_count < 50) throw new Error("words");
  if (articleBody(issue).length === 0) throw new Error("body");
});

Deno.test("import refuses the live site and any non-local database by default", () => {
  assertImportTarget("http://127.0.0.1:54321", false);
  let refused = false;
  try {
    assertImportTarget("https://example.supabase.co", false);
  } catch {
    refused = true;
  }
  if (!refused) throw new Error("remote was allowed");
  assertImportTarget("https://example.supabase.co", true);
  for (const confirm of [false, true]) {
    let blocked = false;
    try {
      assertImportTarget("https://example.vercel.app", confirm);
    } catch {
      blocked = true;
    }
    if (!blocked) throw new Error("vercel host was allowed");
  }
});

Deno.test("import talks only to the local api and uploads fixture bytes", async () => {
  const calls: string[] = [];
  const bodies: Uint8Array[] = [];
  const fetchImpl: typeof fetch = (input, init) => {
    const href = String(input);
    const method = init?.method ?? "GET";
    calls.push(`${method} ${href}`);
    const host = new URL(href).hostname;
    if (host !== "127.0.0.1") throw new Error(host);
    if (href.includes("/profiles")) {
      return Promise.resolve(new Response(JSON.stringify([{ id: user }])));
    }
    if (method === "GET" && href.includes("/issues?")) {
      return Promise.resolve(new Response("[]"));
    }
    if (href.includes("/storage/v1/object/audio/")) {
      bodies.push(new Uint8Array(init?.body as ArrayBuffer));
      return Promise.resolve(new Response("", { status: 200 }));
    }
    if (href.endsWith("/articles")) {
      return Promise.resolve(new Response(JSON.stringify([{ id: crypto.randomUUID() }])));
    }
    return Promise.resolve(new Response("", { status: 201 }));
  };

  const written = await importFixtures({
    supabaseUrl: "http://127.0.0.1:54321",
    serviceKey: "service-key-test",
    userId: user,
    fixtureDir: fixtures,
    fetchImpl,
  });
  if (written.map((row) => row.date).join() !== "2026-10-09,2026-10-10,2026-10-11") {
    throw new Error(written.map((row) => row.date).join());
  }
  if (calls.some((call) => !call.includes("127.0.0.1:54321"))) throw new Error(calls.join("\n"));
  if (bodies.length !== 6) throw new Error(`uploads ${bodies.length}`);
  const first = await Deno.readFile(new URL("issue-2026-10-09.json", fixtures));
  if (bodies[0].byteLength !== first.byteLength) throw new Error("payload size");
});
