import { RetryableError, StopError } from "./llm.ts";
import { composeIssue } from "./compose.ts";
import { profileVars, renderPrompt, type LearnerProfile } from "./prompt.ts";

const profile: LearnerProfile = {
  learnerLevel: "B1",
  explanationLang: "zh-CN",
  annotationDepth: "standard",
  annotationKinds: ["vocab", "grammar"],
  excerptWords: 400,
  vocabCount: 12,
  includeIpa: true,
  patternCount: 4,
};

const root = new URL("../prompts/", import.meta.url);

async function templates() {
  return {
    select: await Deno.readTextFile(new URL("select.md", root)),
    annotate: await Deno.readTextFile(new URL("annotate.md", root)),
    vocab: await Deno.readTextFile(new URL("vocab.md", root)),
    patterns: await Deno.readTextFile(new URL("patterns.md", root)),
  };
}

const legal = {
  zh_title: "早盘",
  byline: "Example",
  lead: "开盘很安静。",
  blocks: [{ kind: "para", segments: [{ text: "The market opened quietly.", note: 1 }] }],
  notes: [{ n: 1, kind: "vocab", tag: "词", head: "quietly", body: "安静地" }],
};

function route(payloadFor: (prompt: string) => unknown, status = 200): typeof fetch {
  return (_url, init) => {
    const body = JSON.parse(String(init?.body)) as { messages: { content: string }[] };
    const prompt = body.messages[0].content;
    const content = payloadFor(prompt);
    return Promise.resolve(new Response(JSON.stringify({
      choices: [{ message: { content: JSON.stringify(content) } }],
      usage: { prompt_tokens: 20, completion_tokens: 10 },
    }), { status, headers: { "content-type": "application/json" } }));
  };
}

function legalPayload(prompt: string): unknown {
  if (prompt.includes("选文编辑")) return { index: 0, reason: "clear prose" };
  if (prompt.includes("批注编辑")) return legal;
  if (prompt.includes("值得复习")) {
    return [{ word: "quietly", ipa: "/ˈkwaɪətli/", meaning: "安静地", example: "The market opened quietly." }];
  }
  return [{
    pattern: "opened quietly",
    pattern_zh: "安静地开始",
    source: "The market opened quietly.",
    model: "The shop opened quietly.",
    model_zh: "店安静地开了。",
  }];
}

Deno.test("rendered prompts include the learner profile", async () => {
  const files = await templates();
  const vars = profileVars(profile, { topic: "stocks", candidates: "[]", title: "Morning", source_url: "https://example.com", excerpt: "text" });
  const select = renderPrompt(files.select, vars);
  const annotate = renderPrompt(files.annotate, vars);
  const vocab = renderPrompt(files.vocab, vars);
  const patterns = renderPrompt(files.patterns, vars);
  for (const prompt of [select, annotate, vocab, patterns]) {
    if (!prompt.includes("B1") || !prompt.includes("zh-CN")) throw new Error(prompt);
  }
  if (!annotate.includes("standard") || !annotate.includes("vocab,grammar")) throw new Error(annotate);
  if (!vocab.includes("12") || !patterns.includes("4")) throw new Error("counts");
});

Deno.test("a fixture model returns an issue-shaped object", async () => {
  const result = await composeIssue({
    date: "2026-10-11",
    topic: "stocks",
    topicLabel: "股市",
    dateLabel: "10月11日",
    profile,
    templates: await templates(),
    candidates: [{
      title: "Morning Markets",
      url: "https://example.com/morning",
      publishedAt: "2026-10-11",
      text: "The market opened quietly.",
    }],
    provider: "openai",
    model: "gpt-4.1-mini",
    apiKey: "sk-test",
    fetchImpl: route(legalPayload),
  });
  const issue = result.issue;
  if (issue.title !== "Morning Markets" || issue.zhTitle !== "早盘") throw new Error(issue.zhTitle);
  if (issue.blocks[0].kind !== "para" || issue.notes[0].n !== 1) throw new Error("shape");
  if (issue.words[0].word !== "quietly" || issue.patterns[0].patternZh !== "安静地开始") throw new Error("lists");
  if (issue.notes[0].tilt !== 0) throw new Error("tilt");
  if (!result.prompts.annotate.includes("B1")) throw new Error("prompt");
  if (result.costUsd <= 0) throw new Error("cost");
});

Deno.test("a missing annotation field is retryable and auth failure stops", async () => {
  const common = {
    date: "2026-10-11",
    topic: "stocks",
    topicLabel: "股市",
    dateLabel: "10月11日",
    profile,
    templates: await templates(),
    candidates: [{ title: "Morning Markets", url: "https://example.com/morning", publishedAt: null, text: "Hello." }],
    provider: "openai" as const,
    model: "gpt-4.1-mini",
    apiKey: "sk-test",
  };
  try {
    await composeIssue({
      ...common,
      fetchImpl: route((prompt) => prompt.includes("批注编辑") ? { zh_title: "x" } : legalPayload(prompt)),
    });
    throw new Error("should have failed");
  } catch (error) {
    if (!(error instanceof RetryableError)) throw error;
  }
  try {
    await composeIssue({
      ...common,
      fetchImpl: () => Promise.resolve(new Response("nope", { status: 401 })),
    });
    throw new Error("should have stopped");
  } catch (error) {
    if (!(error instanceof StopError)) throw error;
  }
});
