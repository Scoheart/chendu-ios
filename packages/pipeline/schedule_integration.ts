import { runOnce } from "./worker.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !serviceKey) throw new Error("local supabase env is missing");

const fixtures = new URL("./fixtures/", import.meta.url);
const documents: typeof fetch = (target) => {
  const href = String(target);
  const file = href.includes("fixtures.local")
    ? new URL("sample.rss", fixtures)
    : new URL("sample.html", fixtures);
  return Deno.readTextFile(file).then((body) => new Response(body, { status: 200 }));
};

const legal = {
  zh_title: "早盘",
  byline: "Example",
  lead: "开盘很安静。",
  blocks: [{ kind: "para", segments: [{ text: "The market opened quietly.", note: 1 }] }],
  notes: [{ n: 1, kind: "vocab", tag: "词", head: "quietly", body: "安静地" }],
};

const llmFetch: typeof fetch = (_target, init) => {
  const body = JSON.parse(String(init?.body)) as { messages?: { content: string }[] };
  const prompt = body.messages?.[0]?.content ?? "";
  let content: unknown = { index: 0, reason: "clear" };
  if (prompt.includes("批注编辑")) content = legal;
  else if (prompt.includes("值得复习")) {
    content = [{ word: "quietly", ipa: "", meaning: "安静地", example: "The market opened quietly." }];
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
    usage: { prompt_tokens: 12, completion_tokens: 8 },
  }), { status: 200 }));
};

const result = await runOnce({
  supabaseUrl: url,
  serviceKey,
  documentFetch: documents,
  llmFetch,
  keys: { llm: "sk-test-secret-ABCD" },
  log: (event) => {
    const keys = Object.keys(event).sort().join(",");
    if (keys !== "attempt,job_id,step,user_id") throw new Error(keys);
  },
});
if (result.status !== "succeeded") throw new Error(result.status);

const response = await fetch(
  `${url}/rest/v1/issues?user_id=eq.11111111-1111-4111-8111-111111111111&select=status`,
  { headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}` } },
);
const issues = await response.json() as { status: string }[];
if (issues.length !== 1 || issues[0].status !== "ready") throw new Error(JSON.stringify(issues));

const jobs = await fetch(
  `${url}/rest/v1/jobs?id=eq.${result.jobId}&select=status,push_pending`,
  { headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}` } },
);
const rows = await jobs.json() as { status: string; push_pending: boolean }[];
if (rows[0].status !== "succeeded" || rows[0].push_pending !== true) throw new Error(JSON.stringify(rows[0]));
