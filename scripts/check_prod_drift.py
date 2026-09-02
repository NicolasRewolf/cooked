#!/usr/bin/env python3
"""T-12 — Compare la prod à la prod (lecture seule).

Nécessite DATABASE_URL (rôle cooked_ci_ro / secret GitHub DATABASE_URL_RO).

Contrôles :
  1. Chaque migration prod depuis CUTOFF a un fichier local de même version
  2. Versions critiques listées dans contracts/doc_constants.json présentes
  3. content_sha256 de supabase/rpcs.sql = dump live des corps public.*
  4. cron.job (actifs) = contracts/doc_constants.json → cron_jobs
  5. alert_rule_exposure() → 0 ligne (si la fonction existe)
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
RPCS = ROOT / "supabase" / "rpcs.sql"
META = ROOT / "contracts" / "rpc_snapshot_meta.json"
CONSTANTS = ROOT / "contracts" / "doc_constants.json"

# Fenêtre « nouvelles migrations MCP sans miroir » — l'historique re-daté
# avant cette borne reste une dette (54 fichiers) hors gate dure T-12.
CUTOFF = "20260801000000"

VERSION_RE = re.compile(r"^(\d{14})_")
BODY_MARKER = "-- ═══ public."

DUMP_SQL = """
SELECT coalesce(string_agg(
  format(E'-- ═══ public.%s(%s) ═══\\n%s',
    p.proname,
    pg_get_function_identity_arguments(p.oid),
    pg_get_functiondef(p.oid)),
  E'\\n\\n' ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)), '')
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind IN ('f', 'p');
""".strip()


def local_versions() -> set[str]:
    out: set[str] = set()
    for path in MIGRATIONS.glob("*.sql"):
        m = VERSION_RE.match(path.name)
        if m:
            out.add(m.group(1))
    return out


def rpcs_body_sha(text: str) -> str:
    """Hash des corps seulement (après l'en-tête), comme rpc_snapshot_meta.content_sha256."""
    idx = text.find(BODY_MARKER)
    body = text[idx:] if idx >= 0 else text
    # generate_rpcs_sql écrit body + "\n" puis file = header+body+"\n"
    if not body.endswith("\n"):
        body = body + "\n"
    # meta content_sha256 = hash(body) sans le newline final du fichier ?
    # generate_rpcs_sql: content = header + body + "\n" ; content_sha256 = sha256(body.encode())
    # où body = row[0] or ""  (sans newline forcé dans write: header + body + "\n")
    raw = text[idx:] if idx >= 0 else text
    if raw.endswith("\n"):
        raw = raw[:-1]
    return hashlib.sha256(raw.encode()).hexdigest()


def main() -> int:
    url = (os.environ.get("DATABASE_URL") or os.environ.get("DATABASE_URL_RO") or "").strip()
    if not url:
        print("T-12 FAIL — DATABASE_URL / DATABASE_URL_RO absent")
        return 1

    try:
        import psycopg2  # type: ignore
    except ImportError:
        print("T-12 FAIL — psycopg2 requis (pip install psycopg2-binary)")
        return 1

    constants = json.loads(CONSTANTS.read_text(encoding="utf-8"))
    meta = json.loads(META.read_text(encoding="utf-8")) if META.exists() else {}
    local = local_versions()
    failures: list[str] = []

    with psycopg2.connect(url) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT version, name FROM supabase_migrations.schema_migrations "
                "WHERE version >= %s ORDER BY version",
                (CUTOFF,),
            )
            recent = cur.fetchall()
            missing = [(v, n) for v, n in recent if v not in local]
            if missing:
                sample = ", ".join(f"{v}/{n}" for v, n in missing[:5])
                failures.append(
                    f"{len(missing)} migration(s) prod ≥ {CUTOFF} sans fichier local "
                    f"(ex. {sample})"
                )

            for v in constants.get("migrations_must_exist", []):
                if v not in local:
                    failures.append(f"migration critique absente du repo : {v}")

            cur.execute(DUMP_SQL)
            live_body = cur.fetchone()[0] or ""
            live_sha = hashlib.sha256(live_body.encode()).hexdigest()
            live_count = live_body.count(BODY_MARKER)

            file_text = RPCS.read_text(encoding="utf-8") if RPCS.exists() else ""
            file_sha = rpcs_body_sha(file_text) if file_text else ""
            meta_sha = meta.get("content_sha256", "")

            if live_sha != file_sha:
                failures.append(
                    f"rpcs.sql dérive de la prod : live={live_sha[:12]}… "
                    f"file={file_sha[:12] or '∅'}… (régénérer scripts/generate_rpcs_sql.py)"
                )
            if meta_sha and meta_sha != live_sha:
                failures.append(
                    f"contracts/rpc_snapshot_meta.json content_sha256 ≠ prod "
                    f"(meta={meta_sha[:12]}… live={live_sha[:12]}…)"
                )
            if live_count < int(constants.get("rpc_function_count_expected_min", 0)):
                failures.append(
                    f"trop peu de fonctions public en prod : {live_count} "
                    f"(min {constants['rpc_function_count_expected_min']})"
                )

            # cron.job n'est pas lisible ligne à ligne par un rôle non-owner :
            # passer par cooked_ci_cron_jobs() (SECURITY DEFINER, T-12).
            cur.execute(
                "SELECT jobname, schedule FROM public.cooked_ci_cron_jobs() "
                "WHERE active ORDER BY jobname"
            )
            live_cron = {(r[0], r[1]) for r in cur.fetchall()}
            expected_cron = {
                (c["jobname"], c["schedule"]) for c in constants.get("cron_jobs", [])
            }
            if live_cron != expected_cron:
                only_live = sorted(live_cron - expected_cron)
                only_doc = sorted(expected_cron - live_cron)
                failures.append(
                    f"cron.job ≠ contracts/doc_constants.json "
                    f"(prod_only={only_live[:5]} doc_only={only_doc[:5]})"
                )

            # Même logique que alert_rule_exposure(), en lecture catalogue
            # (cooked_ci_ro n'a pas EXECUTE sur la fonction SECURITY DEFINER).
            cur.execute(
                """
                SELECT string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ')
                FROM pg_proc p
                JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public'
                  AND p.prosecdef
                  AND (has_function_privilege('anon', p.oid, 'EXECUTE')
                       OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))
                """
            )
            exposed_fn = cur.fetchone()[0]
            if exposed_fn:
                failures.append(f"fonctions SECURITY DEFINER exécutables par anon/auth : {exposed_fn}")

    if failures:
        print("T-12 prod-drift FAIL:\n")
        for f in failures:
            print(f"  • {f}")
        return 1

    print(
        f"T-12 OK — migrations ≥{CUTOFF} mirroirées, rpcs.sql={live_count} fn "
        f"aligné prod, cron={len(live_cron)} jobs, exposure=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
