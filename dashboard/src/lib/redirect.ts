// Garde anti open-redirect pour le paramètre `next` (magic-link).
// N'accepte QU'un chemin interne : commence par "/", pas "//" (URL
// protocol-relative → autre origine), pas de "\" (que certains navigateurs
// normalisent en "/" et qui permet "/\\evil.com"). Sinon on retombe sur "/".
// Client-safe (pas de `server-only`) : utilisé côté route serveur ET côté login.
export function safeNext(next: string | null | undefined): string {
  if (
    typeof next === "string" &&
    next.startsWith("/") &&
    !next.startsWith("//") &&
    !next.includes("\\")
  ) {
    return next;
  }
  return "/";
}
