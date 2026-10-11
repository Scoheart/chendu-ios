import { FIXTURE_FILES, importFixtures } from "./import_issue.ts";

const user = "11111111-1111-4111-8111-111111111111";
const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !serviceKey) throw new Error("local supabase env is missing");
if (!url.includes("127.0.0.1") && !url.includes("localhost")) throw new Error("refusing a non-local run");

const fixtures = new URL("../../ChenduTests/Fixtures/", import.meta.url);
const written = await importFixtures({
  supabaseUrl: url,
  serviceKey,
  userId: user,
  fixtureDir: fixtures,
});
if (written.length !== 3) throw new Error(`wrote ${written.length}`);

const headers = {
  apikey: serviceKey,
  authorization: `Bearer ${serviceKey}`,
};
const response = await fetch(
  `${url}/rest/v1/issues?user_id=eq.${user}&select=issue_date,title,config_snapshot,annotations(n,head),audio_assets(kind,storage_path,byte_size)&order=issue_date.desc`,
  { headers },
);
if (!response.ok) throw new Error(`issues ${response.status}`);
const issues = await response.json() as {
  issue_date: string;
  title: string;
  config_snapshot: { origin?: string };
  annotations: { n: number; head: string }[];
  audio_assets: { kind: string; storage_path: string; byte_size: number }[];
}[];
const dates = issues.map((issue) => issue.issue_date).join();
if (dates !== "2026-10-11,2026-10-10,2026-10-09") throw new Error(dates);

for (const name of FIXTURE_FILES) {
  const fixture = JSON.parse(await Deno.readTextFile(new URL(name, fixtures))) as {
    date: string;
    title: string;
    notes: { n: number; head: string }[];
  };
  const issue = issues.find((row) => row.issue_date === fixture.date);
  if (!issue) throw new Error(fixture.date);
  if (issue.title !== fixture.title) throw new Error(issue.title);
  if (issue.config_snapshot.origin !== "import") throw new Error("origin");
  if (JSON.stringify(issue.config_snapshot).includes("sk-")) throw new Error("snapshot kept a key");
  const heads = [...issue.annotations].sort((a, b) => a.n - b.n).map((row) => row.head);
  const want = [...fixture.notes].sort((a, b) => a.n - b.n).map((row) => row.head);
  if (heads.join("\n") !== want.join("\n")) throw new Error(`heads ${fixture.date}`);
  const file = await Deno.readFile(new URL(name, fixtures));
  if (issue.audio_assets.length !== 2) throw new Error("audio rows");
  for (const asset of issue.audio_assets) {
    if (asset.byte_size !== file.byteLength) throw new Error("byte_size");
    const objectPath = asset.storage_path.replace(/^audio\//, "");
    const downloaded = await fetch(`${url}/storage/v1/object/audio/${objectPath}`, { headers });
    if (!downloaded.ok) throw new Error(`download ${downloaded.status}`);
    const got = new Uint8Array(await downloaded.arrayBuffer());
    if (got.byteLength !== file.byteLength || got.some((byte, index) => byte !== file[index])) {
      throw new Error(`object ${objectPath}`);
    }
  }
}

console.log(written.map((row) => row.issueId).join(" "));
console.log("import integration passed");
