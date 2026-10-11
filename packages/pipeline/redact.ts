/** Strip provider key material before it is stored or logged. */
export function redactSecrets(message: string): string {
  return message
    .replace(/\bsk-[A-Za-z0-9_-]{8,}\b/g, "sk-***")
    .replace(/\bxai-[A-Za-z0-9_-]{8,}\b/g, "xai-***");
}
