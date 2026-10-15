import { redactSecrets } from "./redact.ts";

Deno.test("redacts a key embedded in an error", () => {
  const raw = "provider rejected sk-test-secret-ABCD (401)";
  const out = redactSecrets(raw);
  if (out.includes("sk-test-secret-ABCD")) {
    throw new Error(out);
  }
  if (out !== "provider rejected sk-*** (401)") {
    throw new Error(out);
  }
});
