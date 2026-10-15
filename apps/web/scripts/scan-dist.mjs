import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../dist/", import.meta.url));
const banned = [/service_role/, /c2VydmljZV9yb2xl/, /sb_secret_[A-Za-z0-9]/];

async function files(dir) {
  const found = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) found.push(...await files(path));
    else found.push(path);
  }
  return found;
}

const paths = await files(root);
let failed = false;
for (const path of paths) {
  const text = await readFile(path, "utf8");
  for (const pattern of banned) {
    if (pattern.test(text)) {
      console.error(`${path} matched ${pattern}`);
      failed = true;
    }
  }
}
if (failed) process.exit(1);
console.log(`dist scan clean (${paths.length} files)`);
