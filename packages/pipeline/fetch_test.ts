import { excerptLimit, excerptText, contentHash, wordsOf } from "./excerpt.ts";
import { parseHtml, parseRss } from "./extract.ts";
import { fetchDocument } from "./fetch.ts";

const fixtures = new URL("./fixtures/", import.meta.url);

Deno.test("rss fixture yields published date, title, and link", async () => {
  const xml = await Deno.readTextFile(new URL("sample.rss", fixtures));
  const [item] = parseRss(xml);
  if (item.title !== "Morning Markets") throw new Error(item.title);
  if (item.link !== "https://example.com/morning") throw new Error(item.link);
  if (item.publishedAt !== "Fri, 09 Oct 2026 08:00:00 GMT") throw new Error(item.publishedAt ?? "");
  if (!item.description.includes("market opened quietly")) throw new Error(item.description);
});

Deno.test("html fixture yields published date, title, and link", async () => {
  const html = await Deno.readTextFile(new URL("sample.html", fixtures));
  const article = parseHtml(html);
  if (article.title !== "Morning Markets") throw new Error(article.title);
  if (article.link !== "https://example.com/morning") throw new Error(article.link);
  if (article.publishedAt !== "2026-10-09T08:00:00Z") throw new Error(article.publishedAt ?? "");
  if (wordsOf(article.body).length < 600) throw new Error(String(wordsOf(article.body).length));
});

Deno.test("a long body is cut to the license word cap", async () => {
  const html = await Deno.readTextFile(new URL("sample.html", fixtures));
  const article = parseHtml(html);
  const reserved = excerptLimit(900, "all-rights-reserved", 2000);
  if (reserved !== 500) throw new Error(String(reserved));
  const cut = excerptText(article.body, reserved);
  if (wordsOf(cut).length !== 500) throw new Error(String(wordsOf(cut).length));

  const cc = excerptLimit(2000, "cc-by-4.0", 1500);
  if (cc !== 1500) throw new Error(String(cc));
  const publicDomain = excerptLimit(800, "public-domain", 2000);
  if (publicDomain !== 800) throw new Error(String(publicDomain));
  const wider = excerptText(article.body, excerptLimit(600, "cc-by", 2000));
  if (wordsOf(wider).length !== 600) throw new Error(String(wordsOf(wider).length));
});

Deno.test("the same body keeps a stable content hash", async () => {
  const html = await Deno.readTextFile(new URL("sample.html", fixtures));
  const article = parseHtml(html);
  const once = await contentHash(article.body);
  const twice = await contentHash(article.body.replace(/ +/g, "   "));
  if (once !== twice) throw new Error("hash drifted");
  if (once.length !== 64) throw new Error(once);
  const other = await contentHash(article.body + " extra");
  if (once === other) throw new Error("hash collided");
});

Deno.test("fetch uses the injected transport", async () => {
  const doc = await fetchDocument("https://example.com/morning", () =>
    Promise.resolve(
      new Response("<article>Hello</article>", {
        status: 200,
        headers: { "content-type": "text/html" },
      }),
    ));
  if (doc.status !== 200 || doc.contentType !== "text/html") throw new Error("status");
  if (!doc.body.includes("Hello")) throw new Error(doc.body);
});
