export interface RssItem {
  title: string;
  link: string;
  publishedAt: string | null;
  description: string;
}

export interface HtmlArticle {
  title: string;
  link: string;
  publishedAt: string | null;
  body: string;
}

function decodeEntities(text: string): string {
  return text
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&nbsp;/g, " ");
}

function inner(block: string, name: string): string | null {
  const re = new RegExp(`<${name}\\b[^>]*>([\\s\\S]*?)</${name}>`, "i");
  const match = block.match(re);
  return match ? decodeEntities(match[1]).trim() : null;
}

export function stripTags(html: string): string {
  return decodeEntities(html)
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

export function parseRss(xml: string): RssItem[] {
  const items: RssItem[] = [];
  const re = /<item\b[^>]*>([\s\S]*?)<\/item>/gi;
  for (const match of xml.matchAll(re)) {
    const block = match[1];
    const encoded = block.match(/<content:encoded\b[^>]*>([\s\S]*?)<\/content:encoded>/i);
    const description = stripTags(
      encoded ? decodeEntities(encoded[1]) : (inner(block, "description") ?? ""),
    );
    items.push({
      title: stripTags(inner(block, "title") ?? ""),
      link: (inner(block, "link") ?? "").trim(),
      publishedAt: inner(block, "pubDate") ?? inner(block, "published") ?? null,
      description,
    });
  }
  return items;
}

function metaContent(html: string, key: string): string | null {
  const patterns = [
    new RegExp(
      `<meta\\b[^>]*(?:property|name)=["']${key}["'][^>]*content=["']([^"']+)["'][^>]*>`,
      "i",
    ),
    new RegExp(
      `<meta\\b[^>]*content=["']([^"']+)["'][^>]*(?:property|name)=["']${key}["'][^>]*>`,
      "i",
    ),
  ];
  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (match) return decodeEntities(match[1]).trim();
  }
  return null;
}

function canonical(html: string): string | null {
  const match = html.match(
    /<link\b[^>]*rel=["']canonical["'][^>]*href=["']([^"']+)["'][^>]*>/i,
  ) ?? html.match(
    /<link\b[^>]*href=["']([^"']+)["'][^>]*rel=["']canonical["'][^>]*>/i,
  );
  return match ? decodeEntities(match[1]).trim() : null;
}

export function parseHtml(html: string): HtmlArticle {
  const article = html.match(/<article\b[^>]*>([\s\S]*?)<\/article>/i);
  const published = metaContent(html, "article:published_time") ??
    html.match(/<time\b[^>]*datetime=["']([^"']+)["'][^>]*>/i)?.[1] ??
    null;
  return {
    title: metaContent(html, "og:title") ?? stripTags(inner(html, "title") ?? ""),
    link: canonical(html) ?? metaContent(html, "og:url") ?? "",
    publishedAt: published ? decodeEntities(published).trim() : null,
    body: stripTags(article ? article[1] : html),
  };
}
