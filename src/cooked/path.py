"""C3 — path canonique Cooked × GSC (pur, sans dépendances lourdes)."""
from __future__ import annotations

import unicodedata
from urllib.parse import unquote, urlparse


def canonical_path(raw: str) -> str:
    """Path canonique partagé (pathname ou URL GSC complète)."""
    if raw.startswith("http://") or raw.startswith("https://"):
        path = urlparse(raw).path
    else:
        path = raw
    path = unquote(path)
    path = unicodedata.normalize("NFC", path)
    if len(path) > 1 and path.endswith("/"):
        path = path[:-1]
    return path or "/"
