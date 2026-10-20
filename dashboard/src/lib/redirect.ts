// Garde anti open-redirect pour le paramètre `next` (magic-link).
// Valider l'URL RÉSOLUE : les navigateurs retirent notamment LF/TAB/CR avant
// résolution, et normalisent les segments "..". La valeur retournée doit rester
// interne même après la seconde résolution faite par le callback.
// Client-safe (pas de `server-only`) : utilisé côté route serveur ET côté login.
export function safeNext(next: string | null | undefined): string {
  if (typeof next !== "string" || !next.startsWith("/") || next.startsWith("//")) return "/";
  if ([...next].some((c) => c === "\\" || c.charCodeAt(0) < 32 || (c.charCodeAt(0) >= 127 && c.charCodeAt(0) <= 159))) {
    return "/";
  }
  const origin = "https://cooked.invalid";
  try {
    const resolved = new URL(next, origin);
    if (resolved.origin !== origin || resolved.pathname.startsWith("//")) return "/";
    return `${resolved.pathname}${resolved.search}${resolved.hash}`;
  } catch {
    return "/";
  }
}
