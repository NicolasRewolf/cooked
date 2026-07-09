/**
 * C3 — contrat path canonique Cooked × GSC.
 * decode → Unicode NFC → strip trailing slash (sauf /).
 * Vecteur partagé : contracts/canonical_path_vectors.json
 */
export function canonicalPath(p: string | null): string | null {
  if (p == null) return null;
  let path: string;
  try {
    path = decodeURIComponent(p);
  } catch {
    path = p;
  }
  path = path.normalize("NFC");
  if (path.length > 1 && path.endsWith("/")) {
    path = path.slice(0, -1);
  }
  return path || "/";
}
