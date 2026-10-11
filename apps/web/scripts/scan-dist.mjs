import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../dist/", import.meta.url));
const role = ["service", "role"].join("_");
const encoded = ["c2Vydmlj", "ZV9yb2xl"].join("");
const prefix = ["sb", "secret", ""].join("_");
const banned = [role, encoded, `${prefix}[A-Za-z0-9]`].map((source) => new RegExp(source));

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
