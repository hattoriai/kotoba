// The link URL rule. It is the rule of `Kotoba.Sanitizer.link_url/2`, so
// the editor keeps every link that the server keeps:
//
//   * a URL with control characters, an empty URL, or a URL longer than
//     2048 characters is refused;
//   * a URL with a scheme is kept when the scheme is allowed;
//   * a URL without a scheme (a relative URL such as "/docs#top") is kept.
//
// The allowed schemes come from the hook's `data-link-schemes` attribute
// (comma-separated, default "http,https,mailto").

export const DEFAULT_LINK_SCHEMES: readonly string[] = ["http", "https", "mailto"];

const URL_LIMIT = 2048;
const CONTROL = /[\u0000-\u001F\u007F-\u009F]/u;
const SCHEME = /^([a-zA-Z][a-zA-Z0-9+.-]*):/;

/** Reads `data-link-schemes`: comma-separated scheme names. */
export function parseLinkSchemes(value: string | undefined): string[] {
  if (value === undefined) return [...DEFAULT_LINK_SCHEMES];
  return value
    .split(",")
    .map((scheme) => scheme.trim().toLowerCase().replace(/:$/, ""))
    .filter((scheme) => /^[a-z][a-z0-9+.-]*$/.test(scheme));
}

/** Returns the scheme of a URL in lower case, or `null` for a relative URL. */
export function linkScheme(url: string): string | null {
  const match = SCHEME.exec(url.trim());
  return match?.[1] === undefined ? null : match[1].toLowerCase();
}

/** Returns `true` when the server keeps the link (see the rule above). */
export function isAllowedLinkUrl(url: string, schemes: readonly string[]): boolean {
  const trimmed = url.trim();
  if (trimmed === "" || [...trimmed].length > URL_LIMIT || CONTROL.test(trimmed)) return false;
  const scheme = linkScheme(trimmed);
  return scheme === null || schemes.includes(scheme);
}

/**
 * Returns `true` for an allowed URL that has a scheme. Pasted text becomes a
 * link only when it passes this check, so that a pasted word does not.
 */
export function isAbsoluteLinkUrl(url: string, schemes: readonly string[]): boolean {
  return linkScheme(url) !== null && isAllowedLinkUrl(url, schemes);
}

/**
 * Completes a URL typed in the link form: "example.com" becomes
 * "https://example.com" and "ada@example.com" becomes
 * "mailto:ada@example.com". A URL with a scheme, and a relative URL that
 * starts with "/", "#", "?" or ".", stays as it is.
 */
export function normalizeUrl(input: string): string {
  const url = input.trim();
  if (url === "" || linkScheme(url) !== null || /^[/#?.]/.test(url)) return url;
  if (/^[^\s@/]+@[^\s@/]+\.[^\s@/]+$/.test(url)) return `mailto:${url}`;
  return `https://${url}`;
}
