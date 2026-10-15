import { StopError } from "./llm.ts";
import { failureOf, issueDate } from "./worker.ts";

Deno.test("auth failures stop and ask for the key to be saved again", () => {
  const auth = failureOf(new StopError("sk-test-secret-ABCD", 401));
  if (!auth.stop || auth.message !== "key needs resave") throw new Error(auth.message);
  const bad = failureOf(new Error("missing blocks sk-test-secret-ABCD"));
  if (bad.stop) throw new Error("should retry");
  if (bad.message.includes("sk-test-secret-ABCD")) throw new Error(bad.message);
});

Deno.test("issue date follows the user timezone", () => {
  const instant = new Date("2026-10-11T16:30:00Z");
  if (issueDate(instant, "Asia/Shanghai") !== "2026-10-12") throw new Error(issueDate(instant, "Asia/Shanghai"));
  if (issueDate(instant, "UTC") !== "2026-10-11") throw new Error("utc");
});
