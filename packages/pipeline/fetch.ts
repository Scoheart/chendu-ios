export interface FetchedDocument {
  url: string;
  status: number;
  contentType: string;
  body: string;
}

export async function fetchDocument(
  url: string,
  fetchImpl: typeof fetch = fetch,
): Promise<FetchedDocument> {
  const response = await fetchImpl(url);
  const body = await response.text();
  return {
    url: response.url || url,
    status: response.status,
    contentType: response.headers.get("content-type") ?? "",
    body,
  };
}
