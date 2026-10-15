import { runOnce, type WorkerLog } from "./worker.ts";

const user = "11111111-1111-4111-8111-111111111111";
const jobs = {
  good: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01",
  bad: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02",
  auth: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03",
};
const key = "sk-test-secret-ABCD";
const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !serviceKey) throw new Error("local supabase env is missing");

const fixtures = new URL("./fixtures/", import.meta.url);

const documents: typeof fetch = (target) => {
  const href = String(target);
  const file = href.includes("sample.rss") || href.includes("fixtures.local")
    ? new URL("sample.rss", fixtures)
    : new URL("sample.html", fixtures);
  return Deno.readTextFile(file).then((body) =>
    new Response(body, { status: 200, headers: { "content-type": "text/xml" } })
  );
};

const legal = {
  zh_title: "早盘",
  byline: "Example",
  lead: "开盘很安静。",
  blocks: [{ kind: "para", segments: [{ text: "The market opened quietly.", note: 1 }] }],
  notes: [{ n: 1, kind: "vocab", tag: "词", head: "quietly", body: "安静地" }],
};

const unauthorized: typeof fetch = () => Promise.resolve(new Response("unauthorized", { status: 401 }));

function legalPayload(): unknown {
  return { index: 0, reason: "clear" };
}

function routed(mode: "ok" | "bad"): typeof fetch {
  return (_target, init) => {
    const body = JSON.parse(String(init?.body)) as { messages?: { content: string }[] };
    const prompt = body.messages?.[0]?.content ?? "";
    let content: unknown = legalPayload();
    if (mode === "bad" && prompt.includes("批注编辑")) content = { zh_title: "x" };
    else if (prompt.includes("批注编辑")) content = legal;
    else if (prompt.includes("值得复习")) {
      content = [{ word: "quietly", ipa: "/ˈkwaɪətli/", meaning: "安静地", example: "The market opened quietly." }];
    } else if (prompt.includes("句型")) {
      content = [{
        pattern: "opened quietly",
        pattern_zh: "安静地开始",
        source: "The market opened quietly.",
        model: "The shop opened quietly.",
        model_zh: "店安静地开了。",
      }];
    }
    return Promise.resolve(new Response(JSON.stringify({
      choices: [{ message: { content: JSON.stringify(content) } }],
      usage: { prompt_tokens: 20, completion_tokens: 10 },
    }), { status: 200 }));
  };
}

async function api(path: string, init?: RequestInit): Promise<unknown> {
  const response = await fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: serviceKey!,
      authorization: `Bearer ${serviceKey}`,
      "content-type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${path} ${response.status} ${text.slice(0, 240)}`);
  return text ? JSON.parse(text) : null;
}

function assertLog(event: WorkerLog) {
  const keys = Object.keys(event).sort().join(",");
  if (keys !== "attempt,job_id,step,user_id") throw new Error(keys);
  if (JSON.stringify(event).includes(key)) throw new Error("log kept the key");
}

const logs: WorkerLog[] = [];
const base = {
  supabaseUrl: url,
  serviceKey,
  documentFetch: documents,
  keys: { llm: key },
  log: (event: WorkerLog) => {
    assertLog(event);
    logs.push(event);
  },
};

const first = await runOnce({ ...base, llmFetch: routed("ok") });
if (first.status !== "succeeded") throw new Error(first.status);

const issues = await api(
  `issues?user_id=eq.${user}&select=status,title,config_snapshot`,
) as { status: string; title: string; config_snapshot: Record<string, unknown> }[];
if (issues.length !== 1 || issues[0].status !== "ready") throw new Error("issue was not ready");
if (issues[0].title !== "Morning Markets") throw new Error(issues[0].title);
const snapshot = issues[0].config_snapshot;
if (snapshot.excerpt_words !== 400 || snapshot.learner_level !== "B1") {
  throw new Error(JSON.stringify(snapshot));
}
if (!snapshot.model || !snapshot.voice) throw new Error("snapshot missing model");
const templates = snapshot.templates as Record<string, { version: number }>;
if (templates.select.version !== 1) throw new Error("template version");
if (JSON.stringify(snapshot).includes("sk-")) throw new Error("snapshot kept a key");

await api(`generation_profiles?user_id=eq.${user}`, {
  method: "PATCH",
  headers: { prefer: "return=minimal" },
  body: JSON.stringify({ excerpt_words: 180 }),
});
const again = await api(
  `issues?user_id=eq.${user}&select=config_snapshot`,
) as { config_snapshot: { excerpt_words: number } }[];
if (again[0].config_snapshot.excerpt_words !== 400) throw new Error("snapshot changed with the profile");

const saved = await api(
  `jobs?id=eq.${jobs.good}&select=status,input_tokens,output_tokens,cost_usd`,
) as { status: string; input_tokens: number | null; output_tokens: number | null; cost_usd: number | null }[];
if (saved[0].status !== "succeeded") throw new Error(saved[0].status);
if (saved[0].input_tokens == null || saved[0].output_tokens == null || saved[0].cost_usd == null) {
  throw new Error("cost columns empty");
}
if (Number(saved[0].cost_usd) <= 0) throw new Error("cost");

const second = await runOnce({ ...base, llmFetch: routed("bad") });
if (second.jobId !== jobs.bad || second.status !== "queued") throw new Error(`${second.jobId} ${second.status}`);
const bad = await api(
  `jobs?id=eq.${jobs.bad}&select=status,attempts,last_error`,
) as { status: string; attempts: number; last_error: string }[];
if (bad[0].status !== "queued" || bad[0].attempts !== 1) throw new Error(JSON.stringify(bad[0]));
if (bad[0].last_error.includes(key)) throw new Error("error kept the key");

const third = await runOnce({ ...base, llmFetch: unauthorized });
if (third.jobId !== jobs.auth || third.status !== "failed") throw new Error(`${third.jobId} ${third.status}`);
const auth = await api(
  `jobs?id=eq.${jobs.auth}&select=status,attempts,last_error`,
) as { status: string; attempts: number; last_error: string }[];
if (auth[0].status !== "failed" || auth[0].last_error !== "key needs resave") {
  throw new Error(JSON.stringify(auth[0]));
}
if (logs.length === 0) throw new Error("no logs");
