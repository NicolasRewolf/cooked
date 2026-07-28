#!/usr/bin/env python3
"""
Framework d'analyse mathematique avancee pour Cooked.

Cinq modules complementaires, chacun repondant a une question que le CPI ne
sait pas poser :

  1. Chaines de Markov      — quelle page, si on la retirait du site, ferait
                              perdre le plus de contacts ? (removal effect)
  2. Theorie des graphes    — quelle page est un carrefour de navigation vers
                              les pages business ? (betweenness centrality)
  3. Valeur de Shapley      — quelle est la contribution marginale exacte
                              d'une page, comparee a l'attribution 1/L du CPI ?
  4. Inference causale      — qu'a reellement produit une reecriture, une fois
                              la maree du site soustraite ? (controle synthetique)
  5. STL / Kalman           — quelles pages declinent en tendance de fond,
                              sous le bruit hebdomadaire ? (signal precoce)

INVARIANTS RESPECTES (CLAUDE.md)
  - `events_human` uniquement (jamais `events` brut) : le filtrage bot/bruit
    est fait en amont par les RPC `math_*`.
  - Visiteur recousu via `identity_stitch` (bug de rotation aid/sid du 12/07).
  - Timezone Paris pour toute date affichee, format JJ/MM/AAAA.
  - Contacts macro = `cta_phone_click` + `form_submit` filtre. Les micro
    (`cta_booking_click`) ne sont JAMAIS comptees comme des contacts.
  - Aucun secret en dur : SUPABASE_SECRET_KEY vient de l'environnement.

SOURCES DE DONNEES
  --source supabase : lit les tables snapshot `math_*_snapshot` (rapides) et
                      les series GSC/CPI via PostgREST. Necessite
                      SUPABASE_SECRET_KEY.
  --source cache    : rejoue depuis un repertoire de JSON (aucun secret
                      requis) — sert aux tests et a la reproductibilite.

Les snapshots sont rafraichis cote base par `math_refresh_snapshots(days)` :
`math_visit_sequences(28)` coute ~65 s alors que PostgREST plafonne a 8 s,
une RPC lourde n'est donc pas appelable directement depuis ce script.

Usage :
    python3 scripts/advanced_math_analytics.py --module all --window 28
    python3 scripts/advanced_math_analytics.py --module markov --window 84
    python3 scripts/advanced_math_analytics.py --source cache --cache-dir /tmp/x
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Iterable, Sequence

import numpy as np

DEFAULT_SUPABASE_URL = "https://mxycmjkeotrycyneacje.supabase.co"
SITE_HOST = "www.jplouton-avocat.fr"

# Etats absorbants de la chaine de Markov
STATE_START = "(start)"
STATE_CONV = "(conversion)"
STATE_NULL = "(null)"

# Pages "business" : celles ou un contact peut se declencher.
BUSINESS_PREFIXES = (
    "/defense-penale",
    "/indemnisation-des-victimes",
    "/droit-des-contrats-et-des-personnes",
    "/honoraires-rendez-vous",
)

# Certaines annotations kind='site_change' decrivent un changement de MESURE
# (restatement CPI, reclassification de canal) et non un changement du site.
# Les passer au module causal produirait un "effet" purement comptable : le
# 27/07/2026, classify_channel v3 sort le GMB de l'organique — la home perd
# 45 % de ses entrees organiques sans que rien n'ait bouge cote site.
# La taxonomie `annotations.kind` gagnerait une valeur dediee ('restatement').
MEASUREMENT_CHANGE_MARKERS = (
    "restatement",
    "finitions audit",
    "classify_channel",
    "aucune modif site",
)


def is_measurement_change(label: str | None) -> bool:
    low = (label or "").lower()
    return any(m in low for m in MEASUREMENT_CHANGE_MARKERS)


def fr_date(value: date | datetime | str) -> str:
    """Toute date affichee est en JJ/MM/AAAA (regle absolue CLAUDE.md)."""
    if isinstance(value, str):
        value = date.fromisoformat(value[:10])
    return value.strftime("%d/%m/%Y")


def is_business(path: str) -> bool:
    return any(path.startswith(p) for p in BUSINESS_PREFIXES)


def is_resource_post(path: str) -> bool:
    return path.startswith("/post/")


# ═══════════════════════════════════════════════════════════════════════
# Acces aux donnees
# ═══════════════════════════════════════════════════════════════════════


@dataclass
class VisitSequence:
    """Une classe de visites recousues partageant le meme parcours."""

    journey: tuple[str, ...]
    converted: bool
    entry_channel: str | None
    n: int


class DataSource:
    """Interface commune aux deux back-ends."""

    def visit_sequences(self, window_days: int) -> list[VisitSequence]:
        raise NotImplementedError

    def internal_edges(self, window_days: int) -> list[dict]:
        raise NotImplementedError

    def gsc_daily(self, paths: Sequence[str] | None = None) -> list[dict]:
        raise NotImplementedError

    def cpi_daily(self) -> list[dict]:
        raise NotImplementedError

    def annotations(self) -> list[dict]:
        raise NotImplementedError

    def macro_contacts(self, window_days: int) -> dict[str, int]:
        """Contacts macro par page (phone + form filtre) — source SQL unique."""
        raise NotImplementedError


class SupabaseSource(DataSource):
    """Lecture via PostgREST (clé service). Aucun secret en dur."""

    PAGE = 1000

    def __init__(self, url: str, key: str) -> None:
        from supabase import create_client

        self._client = create_client(url, key)

    @classmethod
    def from_env(cls) -> "SupabaseSource":
        key = os.environ.get("SUPABASE_SECRET_KEY")
        if not key:
            sys.exit(
                "SUPABASE_SECRET_KEY absent de l'environnement.\n"
                "  export SUPABASE_SECRET_KEY=... (clé service, jamais commitée)\n"
                "  ou utilisez --source cache --cache-dir <dir> pour rejouer "
                "un export local."
            )
        url = os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE_URL)
        return cls(url, key)

    def _select_all(self, table: str, columns: str, filters: dict | None = None,
                    order: str | None = None) -> list[dict]:
        """Pagination PostgREST : la limite par defaut tronque silencieusement."""
        out: list[dict] = []
        start = 0
        while True:
            q = self._client.table(table).select(columns)
            for col, val in (filters or {}).items():
                q = q.eq(col, val)
            if order:
                q = q.order(order)
            res = q.range(start, start + self.PAGE - 1).execute()
            rows = res.data or []
            out.extend(rows)
            if len(rows) < self.PAGE:
                return out
            start += self.PAGE

    def visit_sequences(self, window_days: int) -> list[VisitSequence]:
        rows = self._select_all(
            "math_visit_sequences_snapshot",
            "journey,converted,entry_channel,n",
            {"window_days": window_days},
        )
        if not rows:
            sys.exit(
                f"Aucun snapshot pour window_days={window_days}.\n"
                f"  Rafraichir cote base : SELECT math_refresh_snapshots({window_days});"
            )
        return [
            VisitSequence(tuple(r["journey"]), bool(r["converted"]),
                          r.get("entry_channel"), int(r["n"]))
            for r in rows
        ]

    def internal_edges(self, window_days: int) -> list[dict]:
        return self._select_all(
            "math_internal_edges_snapshot",
            "src,dst,kind,placement,weight,dst_resolved",
            {"window_days": window_days},
        )

    def gsc_daily(self, paths: Sequence[str] | None = None) -> list[dict]:
        if paths is None:
            return self._select_all("gsc_path_daily", "day,path,clicks,impressions")
        out: list[dict] = []
        for p in paths:
            out.extend(
                self._select_all("gsc_path_daily", "day,path,clicks,impressions",
                                 {"path": p})
            )
        return out

    def cpi_daily(self) -> list[dict]:
        return self._select_all("cpi_daily", "day,path,cpi,grade,momentum,zc,zr,zl,zv,n_org")

    def annotations(self) -> list[dict]:
        return self._select_all("annotations", "day,kind,label,paths")

    def macro_contacts(self, window_days: int) -> dict[str, int]:
        res = self._client.rpc("macro_contacts_by_path",
                               {"days_back": window_days}).execute()
        return {r["path"]: int(r["contacts"]) for r in (res.data or [])}


class CacheSource(DataSource):
    """Rejoue un export JSON local — aucun secret requis."""

    def __init__(self, cache_dir: Path) -> None:
        self.dir = cache_dir
        if not cache_dir.is_dir():
            sys.exit(f"Repertoire de cache introuvable : {cache_dir}")

    def _load(self, name: str) -> list[dict]:
        f = self.dir / f"{name}.json"
        if not f.exists():
            sys.exit(f"Fichier de cache manquant : {f}")
        return json.loads(f.read_text())

    def visit_sequences(self, window_days: int) -> list[VisitSequence]:
        rows = self._load(f"visit_sequences_{window_days}")
        return [
            VisitSequence(tuple(r["journey"]), bool(r["converted"]),
                          r.get("entry_channel"), int(r["n"]))
            for r in rows
        ]

    def internal_edges(self, window_days: int) -> list[dict]:
        return self._load(f"internal_edges_{window_days}")

    def gsc_daily(self, paths: Sequence[str] | None = None) -> list[dict]:
        rows = self._load("gsc_daily")
        if paths is not None:
            keep = set(paths)
            rows = [r for r in rows if r["path"] in keep]
        return rows

    def cpi_daily(self) -> list[dict]:
        return self._load("cpi_daily")

    def annotations(self) -> list[dict]:
        return self._load("annotations")

    def macro_contacts(self, window_days: int) -> dict[str, int]:
        try:
            rows = self._load(f"macro_contacts_{window_days}")
        except SystemExit:
            return {}
        return {r["path"]: int(r["contacts"]) for r in rows}


# ═══════════════════════════════════════════════════════════════════════
# Module 1 — Chaines de Markov : matrice de transition & removal effect
# ═══════════════════════════════════════════════════════════════════════


@dataclass
class MarkovResult:
    p_conversion: float
    removal: dict[str, float]
    removal_abs: dict[str, float]
    support: dict[str, int]
    conv_support: dict[str, int]
    n_visits: int
    n_conversions: int
    ci: dict[str, tuple[float, float]] = field(default_factory=dict)


def _build_transition_matrix(
    sequences: Sequence[VisitSequence], states: list[str]
) -> np.ndarray:
    """Compte les transitions START -> pages -> {CONV, NULL}, ponderees."""
    idx = {s: i for i, s in enumerate(states)}
    m = len(states)
    counts = np.zeros((m, m), dtype=float)
    for vs in sequences:
        if not vs.journey:
            continue
        w = float(vs.n)
        prev = idx[STATE_START]
        for page in vs.journey:
            j = idx.get(page)
            if j is None:
                continue
            counts[prev, j] += w
            prev = j
        counts[prev, idx[STATE_CONV if vs.converted else STATE_NULL]] += w
    return counts


def _absorption_probability(
    counts: np.ndarray, states: list[str], drop: str | None = None
) -> float:
    """
    P(atteindre CONV depuis START) sur la chaine absorbante.

    Retirer une page k (`drop`) = rediriger tout son trafic entrant vers NULL,
    ce qui simule un site ou cette page n'existe pas. C'est la definition du
    removal effect.
    """
    idx = {s: i for i, s in enumerate(states)}
    i_conv, i_null, i_start = idx[STATE_CONV], idx[STATE_NULL], idx[STATE_START]

    c = counts.copy()
    if drop is not None:
        k = idx[drop]
        # tout ce qui entrait en k part desormais vers NULL
        c[:, i_null] += c[:, k]
        c[:, k] = 0.0
        c[k, :] = 0.0

    transient = [i for i in range(len(states)) if i not in (i_conv, i_null)]
    if drop is not None:
        transient = [i for i in transient if i != idx[drop]]

    row_sums = c.sum(axis=1)
    # Un etat transitoire sans sortie n'aboutit jamais : on l'envoie vers NULL.
    p = np.zeros_like(c)
    nz = row_sums > 0
    p[nz] = c[nz] / row_sums[nz, None]
    p[~nz, i_null] = 1.0

    pos = {s: n for n, s in enumerate(transient)}
    q = p[np.ix_(transient, transient)]
    r_conv = p[transient, i_conv]

    # (I - Q) x = R_conv  ->  x[start] = P(conversion)
    a = np.eye(len(transient)) - q
    try:
        x = np.linalg.solve(a, r_conv)
    except np.linalg.LinAlgError:
        x = np.linalg.lstsq(a, r_conv, rcond=None)[0]
    return float(x[pos[i_start]])


def run_markov(
    sequences: Sequence[VisitSequence],
    min_support: int = 3,
    bootstrap: int = 0,
    seed: int = 12345,
) -> MarkovResult:
    pages = sorted({p for vs in sequences for p in vs.journey})
    states = [STATE_START] + pages + [STATE_CONV, STATE_NULL]

    support: dict[str, int] = defaultdict(int)
    conv_support: dict[str, int] = defaultdict(int)
    for vs in sequences:
        for p in set(vs.journey):
            support[p] += vs.n
            if vs.converted:
                conv_support[p] += vs.n

    counts = _build_transition_matrix(sequences, states)
    base = _absorption_probability(counts, states)

    removal: dict[str, float] = {}
    removal_abs: dict[str, float] = {}
    n_visits = sum(vs.n for vs in sequences)
    n_conv = sum(vs.n for vs in sequences if vs.converted)

    # Ne scorer que les pages ayant un minimum de visites converties : en
    # dessous, le removal effect est du bruit d'echantillonnage.
    candidates = [p for p in pages if conv_support.get(p, 0) >= min_support]
    for p in candidates:
        pk = _absorption_probability(counts, states, drop=p)
        removal[p] = (base - pk) / base if base > 0 else 0.0
        removal_abs[p] = removal[p] * n_conv

    res = MarkovResult(
        p_conversion=base,
        removal=removal,
        removal_abs=removal_abs,
        support=dict(support),
        conv_support=dict(conv_support),
        n_visits=n_visits,
        n_conversions=n_conv,
    )

    if bootstrap > 0 and candidates:
        res.ci = _markov_bootstrap(sequences, candidates, bootstrap, seed)
    return res


def _markov_bootstrap(
    sequences: Sequence[VisitSequence],
    candidates: Sequence[str],
    n_boot: int,
    seed: int,
) -> dict[str, tuple[float, float]]:
    """
    IC 90 % par reechantillonnage des visites (multinomial sur les classes).

    Indispensable ici : avec quelques dizaines de parcours multi-touch, un
    removal effect ponctuel n'a aucune valeur sans sa dispersion.
    """
    rng = np.random.default_rng(seed)
    weights = np.array([vs.n for vs in sequences], dtype=float)
    total = int(weights.sum())
    probs = weights / weights.sum()
    pages = sorted({p for vs in sequences for p in vs.journey})
    states = [STATE_START] + pages + [STATE_CONV, STATE_NULL]

    draws: dict[str, list[float]] = {p: [] for p in candidates}
    for _ in range(n_boot):
        resampled_n = rng.multinomial(total, probs)
        boot = [
            VisitSequence(vs.journey, vs.converted, vs.entry_channel, int(k))
            for vs, k in zip(sequences, resampled_n)
            if k > 0
        ]
        if not any(vs.converted for vs in boot):
            continue
        counts = _build_transition_matrix(boot, states)
        base = _absorption_probability(counts, states)
        if base <= 0:
            continue
        for p in candidates:
            pk = _absorption_probability(counts, states, drop=p)
            draws[p].append((base - pk) / base)

    out: dict[str, tuple[float, float]] = {}
    for p, vals in draws.items():
        if len(vals) >= 10:
            out[p] = (float(np.percentile(vals, 5)), float(np.percentile(vals, 95)))
    return out


# ═══════════════════════════════════════════════════════════════════════
# Module 2 — Theorie des graphes : betweenness centrality
# ═══════════════════════════════════════════════════════════════════════


@dataclass
class GraphResult:
    betweenness: dict[str, float]
    flow_betweenness: dict[str, float]
    to_business: dict[str, int]
    n_nodes: int
    n_edges: int
    resolved_edges: int


def run_graph(
    edges: Sequence[dict], sequences: Sequence[VisitSequence] | None = None
) -> GraphResult:
    """
    Graphe oriente pondere des flux reels de navigation.

    Deux sources d'aretes complementaires :
      - kind='flow'  : transitions effectivement observees (ce que les gens font)
      - kind='click' : clics internes traces (ou le lien etait pose)
    Le poids d'une arete est la somme des deux ; la distance utilisee pour les
    plus courts chemins est 1/poids (une arete tres empruntee est "courte").
    """
    import networkx as nx

    g = nx.DiGraph()
    g_flow = nx.DiGraph()
    resolved = 0
    for e in edges:
        src, dst = e["src"], e["dst"]
        w = float(e["weight"])
        if e.get("dst_resolved"):
            resolved += 1
        if g.has_edge(src, dst):
            g[src][dst]["weight"] += w
        else:
            g.add_edge(src, dst, weight=w)
        if e["kind"] == "flow":
            if g_flow.has_edge(src, dst):
                g_flow[src][dst]["weight"] += w
            else:
                g_flow.add_edge(src, dst, weight=w)

    for graph in (g, g_flow):
        for _, _, d in graph.edges(data=True):
            d["distance"] = 1.0 / d["weight"] if d["weight"] > 0 else 1e9

    bet = nx.betweenness_centrality(g, weight="distance", normalized=True)
    bet_flow = (
        nx.betweenness_centrality(g_flow, weight="distance", normalized=True)
        if g_flow.number_of_nodes() > 2
        else {}
    )

    # Combien de trafic une page envoie-t-elle vers une page business ?
    to_business: dict[str, int] = defaultdict(int)
    for src, dst, d in g.edges(data=True):
        if is_business(dst):
            to_business[src] += int(d["weight"])

    return GraphResult(
        betweenness=bet,
        flow_betweenness=bet_flow,
        to_business=dict(to_business),
        n_nodes=g.number_of_nodes(),
        n_edges=g.number_of_edges(),
        resolved_edges=resolved,
    )


# ═══════════════════════════════════════════════════════════════════════
# Module 3 — Valeur de Shapley
# ═══════════════════════════════════════════════════════════════════════


@dataclass
class ShapleyResult:
    shapley: dict[str, float]
    linear_1_over_l: dict[str, float]
    universe: list[str]
    n_permutations: int
    grand_value: float


def run_shapley(
    sequences: Sequence[VisitSequence],
    max_pages: int = 60,
    n_perm: int = 3000,
    seed: int = 7,
    min_conv_support: int = 2,
) -> ShapleyResult:
    """
    Jeu cooperatif : v(S) = taux de conversion des visites dont l'ensemble des
    pages vues est inclus dans S. La valeur de Shapley repartit v(univers)
    entre les pages selon leur contribution marginale moyenne sur toutes les
    permutations.

    Note importante : si l'on avait pris v(S) = *nombre* de conversions des
    visites incluses dans S, la valeur de Shapley se reduirait exactement a
    l'attribution 1/L — le calcul n'apprendrait rien de neuf. C'est le passage
    au *taux* de conversion des coalitions qui rend le resultat different de
    l'attribution lineaire, donc informatif.

    Estimation par echantillonnage de permutations (Monte-Carlo) : le calcul
    exact demanderait 2^|U| evaluations.
    """
    rng = np.random.default_rng(seed)

    conv_support: dict[str, int] = defaultdict(int)
    for vs in sequences:
        if vs.converted:
            for p in set(vs.journey):
                conv_support[p] += vs.n

    universe = [p for p, c in conv_support.items() if c >= min_conv_support]
    universe.sort(key=lambda p: -conv_support[p])
    universe = universe[:max_pages]
    if not universe:
        return ShapleyResult({}, {}, [], 0, 0.0)

    pos = {p: i for i, p in enumerate(universe)}
    uset = set(universe)

    # Coalitions observees : une visite ne compte que si TOUTES ses pages sont
    # dans l'univers (sinon son ensemble n'est jamais inclus dans S).
    coalitions: dict[int, list[float]] = defaultdict(lambda: [0.0, 0.0])
    for vs in sequences:
        pages = set(vs.journey)
        if not pages or not pages <= uset:
            continue
        mask = 0
        for p in pages:
            mask |= 1 << pos[p]
        coalitions[mask][0] += vs.n
        if vs.converted:
            coalitions[mask][1] += vs.n

    if not coalitions:
        return ShapleyResult({}, {}, universe, 0, 0.0)

    masks = np.array(list(coalitions.keys()), dtype=object)
    tot = np.array([coalitions[m][0] for m in masks], dtype=float)
    cnv = np.array([coalitions[m][1] for m in masks], dtype=float)

    # Position d'activation d'une coalition dans une permutation = rang de sa
    # page la plus tardive. Evite de tester l'inclusion a chaque etape.
    coal_pages = [[i for i in range(len(universe)) if (int(m) >> i) & 1] for m in masks]

    shap = np.zeros(len(universe), dtype=float)
    n_done = 0
    for _ in range(n_perm):
        perm = rng.permutation(len(universe))
        rank = np.empty(len(universe), dtype=int)
        rank[perm] = np.arange(len(universe))

        activate_at = np.array([max(rank[p] for p in pgs) for pgs in coal_pages])
        order = np.argsort(activate_at, kind="stable")

        cum_tot = 0.0
        cum_cnv = 0.0
        prev_v = 0.0
        i = 0
        n_coal = len(order)
        for step in range(len(universe)):
            while i < n_coal and activate_at[order[i]] == step:
                cum_tot += tot[order[i]]
                cum_cnv += cnv[order[i]]
                i += 1
            v = (cum_cnv / cum_tot) if cum_tot > 0 else 0.0
            shap[perm[step]] += v - prev_v
            prev_v = v
        n_done += 1

    shap /= max(n_done, 1)
    grand = float(cnv.sum() / tot.sum()) if tot.sum() > 0 else 0.0

    # Attribution lineaire 1/L, telle que pratiquee par le terme zv du CPI.
    linear: dict[str, float] = defaultdict(float)
    for vs in sequences:
        if not vs.converted or not vs.journey:
            continue
        share = vs.n / len(set(vs.journey))
        for p in set(vs.journey):
            linear[p] += share

    return ShapleyResult(
        shapley={universe[i]: float(shap[i]) for i in range(len(universe))},
        linear_1_over_l=dict(linear),
        universe=universe,
        n_permutations=n_done,
        grand_value=grand,
    )


# ═══════════════════════════════════════════════════════════════════════
# Module 4 — Inference causale (controle synthetique / CausalImpact)
# ═══════════════════════════════════════════════════════════════════════


@dataclass
class CausalResult:
    path: str
    intervention: date
    label: str
    pre_days: int
    post_days: int
    observed: float
    counterfactual: float
    abs_effect: float
    rel_effect: float
    ci_lower: float
    ci_upper: float
    p_value: float
    n_donors: int
    pre_fit_r2: float
    verdict: str


def _daily_series(rows: Iterable[dict], key: str = "clicks") -> dict[str, dict[date, float]]:
    out: dict[str, dict[date, float]] = defaultdict(dict)
    for r in rows:
        d = r["day"]
        d = date.fromisoformat(d[:10]) if isinstance(d, str) else d
        out[r["path"]][d] = float(r.get(key) or 0)
    return out


def _dense(series: dict[date, float], days: list[date]) -> np.ndarray:
    """GSC ne renvoie pas les jours sans impression : absence = 0 clic."""
    return np.array([series.get(d, 0.0) for d in days], dtype=float)


def _synth_weights(y_pre: np.ndarray, x_pre: np.ndarray) -> np.ndarray:
    """
    Poids du controle synthetique : w >= 0 et somme(w) = 1 (Abadie).

    Ces deux contraintes sont ce qui empeche le contrefactuel de sortir de
    l'enveloppe convexe des temoins. Une regression libre, elle, extrapole :
    testee sur `/post/la-garde-a-vue-...`, elle predisait 1 231 clics pour une
    page qui en fait 82 (facteur 15). Le prix a payer est un biais quand la
    cible n'est pas representable par ses temoins — c'est visible dans le
    R² pre-periode, qu'on rapporte systematiquement.
    """
    from scipy.optimize import nnls

    # Contrainte de somme imposee par une ligne de penalite lourde.
    big = 1e6
    a = np.vstack([x_pre, np.full((1, x_pre.shape[1]), big)])
    b = np.concatenate([y_pre, [big]])
    w, _ = nnls(a, b)
    s = w.sum()
    return w / s if s > 0 else np.full(x_pre.shape[1], 1.0 / x_pre.shape[1])


def _synth_fit(
    y: np.ndarray, x: np.ndarray, pre_mask: np.ndarray
) -> tuple[np.ndarray, float, float]:
    """
    Ajuste un controle synthetique sur des series normalisees en indice
    (base = moyenne pre-periode), puis remet a l'echelle de la cible.

    Travailler en indice permet de comparer des pages de volumes tres
    differents : ce qui est transpose, c'est la FORME de la trajectoire.
    Retourne (contrefactuel en clics, rmspe pre, r2 pre).
    """
    base_y = y[pre_mask].mean()
    if base_y <= 0:
        return np.zeros_like(y), float("inf"), 0.0

    base_x = x[pre_mask].mean(axis=0)
    ok = base_x > 0
    if ok.sum() < 3:
        return np.zeros_like(y), float("inf"), 0.0
    xi = x[:, ok] / base_x[ok]
    yi = y / base_y

    w = _synth_weights(yi[pre_mask], xi[pre_mask])
    synth_i = xi @ w
    counterfactual = synth_i * base_y

    resid_pre = yi[pre_mask] - synth_i[pre_mask]
    rmspe = float(np.sqrt((resid_pre**2).mean()))
    ss_res = float((resid_pre**2).sum())
    ss_tot = float(((yi[pre_mask] - yi[pre_mask].mean()) ** 2).sum())
    r2 = 1.0 - ss_res / ss_tot if ss_tot > 0 else 0.0
    return counterfactual, rmspe, r2


def run_causal_impact(
    gsc_rows: Sequence[dict],
    target_path: str,
    intervention: date,
    label: str = "",
    pre_days: int = 90,
    post_days: int = 28,
    min_donor_clicks: float = 90.0,
    exclude_paths: Sequence[str] = (),
    max_donors: int = 20,
    min_r2: float = 0.30,
    min_donor_rate: float = 0.8,
    shock_ratio: float = 3.0,
) -> CausalResult | None:
    """
    Controle synthetique : on reconstruit la trajectoire qu'aurait suivie la
    page SANS l'intervention, a partir d'un panier de pages temoins non
    touchees. La maree commune du site (saisonnalite, updates Google, demande)
    est portee par les temoins, donc soustraite de l'effet mesure.

    Ce n'est pas un BSTS bayesien complet (pas de spike-and-slab MCMC) : c'est
    le controle synthetique contraint d'Abadie, dont l'inference repose sur des
    PLACEBOS — on rejoue l'analyse en faisant passer chaque temoin pour la page
    traitee, et on regarde ou se situe la cible dans cette distribution. Sur
    des series aussi courtes et bruitees, c'est plus robuste qu'un intervalle
    parametrique.
    """
    series = _daily_series(gsc_rows)
    if target_path not in series:
        return None

    # GSC accuse un lag de 2-3 jours : au-dela du dernier jour livre, il n'y a
    # pas "zero clic", il n'y a PAS DE DONNEE. Densifier ces jours a zero
    # fabriquerait un effondrement. Mesure du 13/07/2026 avant ce garde-fou :
    # -65 % sur `/post/la-garde-a-vue-...`, dont 15 jours de zeros inventes.
    data_end = max(d for s in series.values() for d in s)
    post_end = min(intervention + timedelta(days=post_days - 1), data_end)
    if (post_end - intervention).days + 1 < 7:
        return None

    pre_start = intervention - timedelta(days=pre_days)
    all_days = [pre_start + timedelta(days=i)
                for i in range((post_end - pre_start).days + 1)]
    pre_mask = np.array([d < intervention for d in all_days])

    y = _dense(series[target_path], all_days)
    if y[pre_mask].sum() < 20:
        return None

    # Selection des temoins. Deux garde-fous, tous deux appris a la dure sur
    # le cas `/post/la-garde-a-vue-...` du 13/07/2026 :
    #
    #  (a) volume minimum. En indice (serie / moyenne pre), une page a 0,2
    #      clic/j produit des ratios explosifs : le bruit devient le signal.
    #
    #  (b) temoin non choque. `/post/affaire-christophe-b-gironde...` affichait
    #      un indice post de 73 (pic d'actualite judiciaire). Avec un poids de
    #      0,016 il apportait a lui seul 59 % du contrefactuel, qui montait a
    #      237 clics la ou le rythme observe en promettait 118. Un donneur qui
    #      subit son propre choc ne mesure plus la maree commune — c'est
    #      l'hypothese centrale du controle synthetique (Abadie), pas un
    #      ajustement opportuniste.
    banned = set(exclude_paths) | {target_path}
    donors: list[str] = []
    n_pre = int(pre_mask.sum())
    for p, s in series.items():
        if p in banned:
            continue
        v = _dense(s, all_days)
        base = v[pre_mask].mean()
        if v[pre_mask].sum() < min_donor_clicks or v[pre_mask].std() == 0:
            continue
        if base < min_donor_rate:
            continue
        post_index = v[~pre_mask].mean() / base if base > 0 else float("inf")
        if not (1.0 / shock_ratio <= post_index <= shock_ratio):
            continue
        donors.append(p)
    if len(donors) < 5:
        return None

    x_all = np.column_stack([_dense(series[p], all_days) for p in donors])

    # Temoins retenus : les mieux correles a la cible en pre-periode.
    y_pre = y[pre_mask]
    corrs = np.array([
        (lambda c: 0.0 if np.isnan(c) else c)(
            np.corrcoef(y_pre, x_all[pre_mask, j])[0, 1])
        for j in range(x_all.shape[1])
    ])
    keep = list(np.argsort(corrs)[::-1][:max_donors])
    x = x_all[:, keep]
    donors_kept = [donors[j] for j in keep]

    counterfactual_series, rmspe_pre, r2 = _synth_fit(y, x, pre_mask)
    y_post = y[~pre_mask]
    observed = float(y_post.sum())
    counterfactual = float(counterfactual_series[~pre_mask].sum())
    abs_effect = observed - counterfactual
    rel = abs_effect / counterfactual if counterfactual > 0 else float("nan")

    # --- inference par placebo : chaque temoin joue le role de la cible ---
    def rmspe_ratio(yy: np.ndarray, xx: np.ndarray) -> float:
        cf, rm_pre, _ = _synth_fit(yy, xx, pre_mask)
        if not np.isfinite(rm_pre) or rm_pre <= 0:
            return float("nan")
        base = yy[pre_mask].mean()
        if base <= 0:
            return float("nan")
        post_res = (yy[~pre_mask] - cf[~pre_mask]) / base
        rm_post = float(np.sqrt((post_res**2).mean()))
        return rm_post / rm_pre

    target_ratio = rmspe_ratio(y, x)
    placebo: list[float] = []
    for j in range(x_all.shape[1]):
        if donors[j] in banned:
            continue
        yy = x_all[:, j]
        others = [k for k in range(x_all.shape[1]) if k != j]
        if len(others) < 5:
            continue
        xo = x_all[:, others]
        cj = np.array([
            (lambda c: 0.0 if np.isnan(c) else c)(
                np.corrcoef(yy[pre_mask], xo[pre_mask, k])[0, 1])
            for k in range(xo.shape[1])
        ])
        xo = xo[:, list(np.argsort(cj)[::-1][:max_donors])]
        r = rmspe_ratio(yy, xo)
        if np.isfinite(r):
            placebo.append(r)

    if placebo and np.isfinite(target_ratio):
        p_val = float((np.array(placebo) >= target_ratio).mean())
    else:
        p_val = float("nan")

    # IC : dispersion des ecarts placebo, remise a l'echelle de la cible.
    if placebo:
        base = y[pre_mask].mean()
        spread = float(np.percentile(placebo, 90)) * rmspe_pre * base * len(y_post)
    else:
        spread = float("nan")

    if r2 < min_r2:
        verdict = (f"NON INTERPRETABLE — les temoins ne reproduisent pas la "
                   f"pre-periode (R²={r2:.2f} < {min_r2})")
    elif np.isnan(p_val):
        verdict = "non concluant (pas de placebo exploitable)"
    elif p_val < 0.10 and abs_effect > 0:
        verdict = "effet positif significatif"
    elif p_val < 0.10 and abs_effect < 0:
        verdict = "effet negatif significatif"
    else:
        verdict = "non concluant (effet indistinguable du bruit)"

    return CausalResult(
        path=target_path,
        intervention=intervention,
        label=label,
        pre_days=int(pre_mask.sum()),
        post_days=len(y_post),
        observed=observed,
        counterfactual=counterfactual,
        abs_effect=abs_effect,
        rel_effect=rel,
        ci_lower=abs_effect - spread if np.isfinite(spread) else float("nan"),
        ci_upper=abs_effect + spread if np.isfinite(spread) else float("nan"),
        p_value=p_val,
        n_donors=len(donors_kept),
        pre_fit_r2=r2,
        verdict=verdict,
    )


# ═══════════════════════════════════════════════════════════════════════
# Module 5 — Decomposition temporelle : STL + filtre de Kalman
# ═══════════════════════════════════════════════════════════════════════


@dataclass
class TrendResult:
    path: str
    n_days: int
    total_clicks: float
    recent_clicks: float
    trend_slope: float
    slope_se: float
    slope_z: float
    seasonal_amp: float
    trend_change_pct: float
    verdict: str


def run_stl_kalman(
    gsc_rows: Sequence[dict],
    min_clicks: int = 60,
    horizon_days: int = 400,
    recent_window: int = 28,
    min_recent_clicks: int = 15,
    min_recent_rate: float = 0.4,
) -> list[TrendResult]:
    """
    Deux lectures complementaires de la meme serie :

      - STL (periode 7 j, robuste) isole la tendance de fond du cycle
        hebdomadaire et des pics ponctuels (un passage media, un vendredi
        creux). C'est la composante `trend` qui porte le signal.
      - Un modele local linear trend estime par filtre de Kalman fournit la
        PENTE courante *avec son erreur standard* — donc un test : la pente
        est-elle significativement negative, ou est-ce du bruit ?

    L'interet est de detecter un declin AVANT qu'il ne devienne visible dans
    le volume brut, la ou la comparaison 28 j vs 28 j arrive trop tard.
    """
    from statsmodels.tsa.seasonal import STL
    from statsmodels.tsa.statespace.structural import UnobservedComponents

    series = _daily_series(gsc_rows)
    if not series:
        return []

    last_day = max(d for s in series.values() for d in s)
    first_day = max(min(d for s in series.values() for d in s),
                    last_day - timedelta(days=horizon_days))
    days = [first_day + timedelta(days=i) for i in range((last_day - first_day).days + 1)]
    if len(days) < 60:
        return []

    out: list[TrendResult] = []
    for path, s in series.items():
        y = _dense(s, days)
        if y.sum() < min_clicks:
            continue
        # Sans plancher de volume RECENT, le classement se remplit de pages a
        # 1 ou 2 clics/28 j ou un z de -6 ne signifie rien de decidable
        # (piege n°6 du playbook : petits volumes = pas de verdict).
        recent_total = float(y[-recent_window:].sum())
        if recent_total < min_recent_clicks or recent_total / recent_window < min_recent_rate:
            continue

        try:
            stl = STL(y, period=7, robust=True).fit()
            trend = np.asarray(stl.trend, dtype=float)
            seasonal_amp = float(np.percentile(stl.seasonal, 95)
                                 - np.percentile(stl.seasonal, 5))
        except Exception:
            continue

        try:
            mod = UnobservedComponents(y, level="local linear trend", seasonal=7)
            fit = mod.fit(disp=False, maxiter=150)
            # Etat filtre : [niveau, pente, saisonnalite...] -> pente = index 1
            slope = float(fit.filtered_state[1, -1])
            slope_var = float(fit.filtered_state_cov[1, 1, -1])
            slope_se = math.sqrt(max(slope_var, 1e-12))
        except Exception:
            slope, slope_se = float("nan"), float("nan")

        z = slope / slope_se if slope_se and slope_se > 0 else float("nan")

        recent = trend[-recent_window:]
        earlier = trend[-2 * recent_window : -recent_window]
        base = earlier.mean() if len(earlier) else float("nan")
        # Une tendance STL peut passer sous zero sur une page quasi morte :
        # le ratio devient ininterpretable (-104 %, 208 %). On ne calcule la
        # variation que sur une base positive et franche.
        change = (
            (recent.mean() - base) / base * 100
            if np.isfinite(base) and base > 0.05
            else float("nan")
        )

        # Pente exprimee en % du niveau courant sur 28 j : lisible, comparable
        # entre pages ("cette page perd 12 % de ses clics par mois").
        level = max(recent.mean(), 1e-6)
        slope_pct_28 = slope / level * recent_window * 100 if np.isfinite(slope) else float("nan")

        strong = np.isfinite(change) and change < -10
        if not np.isnan(z) and z <= -2 and strong:
            verdict = "declin de tendance confirme"
        elif not np.isnan(z) and z <= -2:
            verdict = "declin naissant (a surveiller)"
        elif not np.isnan(z) and z >= 2 and np.isfinite(change) and change > 10:
            verdict = "croissance"
        else:
            verdict = "stable"

        out.append(
            TrendResult(
                path=path,
                n_days=len(days),
                total_clicks=float(y.sum()),
                recent_clicks=float(y[-recent_window:].sum()),
                trend_slope=slope_pct_28,
                slope_se=slope_se,
                slope_z=z,
                seasonal_amp=seasonal_amp,
                trend_change_pct=change,
                verdict=verdict,
            )
        )

    # Trier par enjeu : un declin significatif sur une page a fort trafic passe
    # devant un declin plus net sur une page confidentielle.
    def priority(r: TrendResult) -> float:
        if np.isnan(r.slope_z) or r.slope_z > -1.0:
            return 1e9
        return -abs(r.slope_z) * math.log1p(r.recent_clicks)

    out.sort(key=priority)
    return out


# ═══════════════════════════════════════════════════════════════════════
# Croisement final — pages ponts invisibles
# ═══════════════════════════════════════════════════════════════════════


def bridge_pages(
    markov: MarkovResult,
    graph: GraphResult,
    shapley: ShapleyResult,
    direct_contacts: dict[str, int] | None = None,
    top: int = 10,
) -> list[dict]:
    """
    Une "page pont invisible" pese dans les parcours qui menent au contact
    sans jamais porter le contact elle-meme. Les trois methodes la voient
    differemment ; on ne retient que les pages vues par plusieurs d'entre
    elles (rang moyen), pour ne pas promouvoir un artefact d'une seule.
    """
    direct_contacts = direct_contacts or {}
    pages = set(markov.removal) | set(shapley.shapley)
    if not pages:
        return []

    def ranks(d: dict[str, float]) -> dict[str, int]:
        ordered = sorted(d.items(), key=lambda kv: -kv[1])
        return {p: i + 1 for i, (p, _) in enumerate(ordered)}

    r_mark = ranks(markov.removal)
    r_shap = ranks({p: v for p, v in shapley.shapley.items()})
    r_betw = ranks({p: graph.betweenness.get(p, 0.0) for p in pages})

    rows = []
    n = len(pages)
    for p in pages:
        rm = r_mark.get(p, n)
        rs = r_shap.get(p, n)
        rb = r_betw.get(p, n)
        rows.append(
            {
                "path": p,
                "removal_effect": markov.removal.get(p, 0.0),
                "removal_contacts": markov.removal_abs.get(p, 0.0),
                "shapley": shapley.shapley.get(p, 0.0),
                "linear_1_over_l": shapley.linear_1_over_l.get(p, 0.0),
                "betweenness": graph.betweenness.get(p, 0.0),
                "to_business_clicks": graph.to_business.get(p, 0),
                "direct_contacts": direct_contacts.get(p, 0),
                "visits": markov.support.get(p, 0),
                "conv_visits": markov.conv_support.get(p, 0),
                "rank_markov": rm,
                "rank_shapley": rs,
                "rank_betweenness": rb,
                "rank_mean": (rm + rs + rb) / 3.0,
                "ci": markov.ci.get(p),
            }
        )

    # Part des parcours convertis passant par la page ou le contact est
    # effectivement pris SUR la page. Faible => la page fait passer, elle ne
    # conclut pas : c'est la definition operationnelle du "pont invisible".
    for r in rows:
        cv = r["conv_visits"]
        r["assist_ratio"] = (
            1.0 - min(r["direct_contacts"], cv) / cv if cv > 0 else float("nan")
        )

    rows.sort(key=lambda r: r["rank_mean"])
    return rows[:top]


def invisible_bridges(
    markov: MarkovResult,
    graph: GraphResult,
    shapley: ShapleyResult,
    direct_contacts: dict[str, int],
    min_conv_visits: int = 3,
    max_assist_ratio: float = 0.5,
    top: int = 10,
) -> list[dict]:
    """
    Les pages ponts INVISIBLES : celles qui pesent dans les parcours qui
    convertissent alors que le contact se prend ailleurs. Elles n'apparaissent
    dans aucun classement par contacts — c'est precisement ce qui les rend
    invisibles au pilotage habituel.
    """
    out = []
    for p, rem in markov.removal.items():
        cv = markov.conv_support.get(p, 0)
        if cv < min_conv_visits:
            continue
        direct = direct_contacts.get(p, 0)
        assist = 1.0 - min(direct, cv) / cv
        if assist < max_assist_ratio:
            continue
        out.append({
            "path": p,
            "removal_effect": rem,
            "removal_contacts": markov.removal_abs.get(p, 0.0),
            "shapley": shapley.shapley.get(p, 0.0),
            "betweenness": graph.betweenness.get(p, 0.0),
            "to_business_clicks": graph.to_business.get(p, 0),
            "direct_contacts": direct,
            "conv_visits": cv,
            "visits": markov.support.get(p, 0),
            "assist_ratio": assist,
            "ci": markov.ci.get(p),
        })
    out.sort(key=lambda r: -r["removal_contacts"])
    return out[:top]


# ═══════════════════════════════════════════════════════════════════════
# Rendu texte
# ═══════════════════════════════════════════════════════════════════════


def _p(s: str = "") -> None:
    print(s)


def report_markov(res: MarkovResult, window: int, top: int = 15) -> None:
    _p(f"\n{'='*78}\nMODULE 1 — CHAINES DE MARKOV (removal effect) — fenetre {window} j\n{'='*78}")
    _p(f"Visites recousues       : {res.n_visits:,}".replace(",", " "))
    _p(f"Visites converties      : {res.n_conversions}")
    _p(f"P(conversion) du modele : {res.p_conversion*100:.3f} %")
    if not res.removal:
        _p("\nAucune page n'atteint le seuil de support : removal effect non calculable.")
        return
    _p(f"\n{'page':<58}{'removal':>9}{'contacts':>10}{'visites':>9}")
    _p("-" * 78)
    for p, v in sorted(res.removal.items(), key=lambda kv: -kv[1])[:top]:
        ci = res.ci.get(p)
        ci_s = f"  [{ci[0]*100:.1f} ; {ci[1]*100:.1f}]" if ci else ""
        _p(f"{p[:57]:<58}{v*100:>8.1f}%{res.removal_abs[p]:>10.1f}"
           f"{res.conv_support.get(p,0):>9}{ci_s}")


def report_graph(res: GraphResult, top: int = 15) -> None:
    _p(f"\n{'='*78}\nMODULE 2 — BETWEENNESS CENTRALITY\n{'='*78}")
    _p(f"Noeuds : {res.n_nodes}   Aretes : {res.n_edges}   "
       f"Cibles de clic reecrites (URL accentuees redirigees) : {res.resolved_edges}")
    _p(f"\n{'page':<58}{'betweenness':>13}{'->business':>11}")
    _p("-" * 78)
    for p, v in sorted(res.betweenness.items(), key=lambda kv: -kv[1])[:top]:
        if v <= 0:
            break
        _p(f"{p[:57]:<58}{v:>13.5f}{res.to_business.get(p,0):>11}")


def report_shapley(res: ShapleyResult, top: int = 15) -> None:
    _p(f"\n{'='*78}\nMODULE 3 — VALEUR DE SHAPLEY (vs attribution 1/L du CPI)\n{'='*78}")
    if not res.shapley:
        _p("Univers vide : pas assez de pages avec conversions.")
        return
    _p(f"Univers : {len(res.universe)} pages   Permutations : {res.n_permutations}   "
       f"v(univers) = {res.grand_value*100:.3f} %")
    _p(f"\n{'page':<52}{'shapley':>11}{'1/L':>9}{'ecart':>9}")
    _p("-" * 78)
    for p, v in sorted(res.shapley.items(), key=lambda kv: -kv[1])[:top]:
        lin = res.linear_1_over_l.get(p, 0.0)
        _p(f"{p[:51]:<52}{v*100:>10.4f}%{lin:>9.1f}{'':>9}")


def report_causal(results: Sequence[CausalResult]) -> None:
    _p(f"\n{'='*78}\nMODULE 4 — INFERENCE CAUSALE (controle synthetique)\n{'='*78}")
    if not results:
        _p("Aucune intervention mesurable (pas d'annotation exploitable).")
        return
    for r in results:
        _p(f"\n▸ {r.path}")
        _p(f"  Intervention   : {fr_date(r.intervention)} — {r.label[:90]}")
        _p(f"  Fenetres       : {r.pre_days} j avant / {r.post_days} j apres")
        _p(f"  Temoins        : {r.n_donors} pages   (R² pre-periode : {r.pre_fit_r2:.3f})")
        _p(f"  Observe        : {r.observed:.0f} clics")
        _p(f"  Contrefactuel  : {r.counterfactual:.0f} clics")
        _p(f"  Effet          : {r.abs_effect:+.0f} clics ({r.rel_effect*100:+.1f} %)"
           f"   IC90 [{r.ci_lower:+.0f} ; {r.ci_upper:+.0f}]")
        _p(f"  p-value        : {r.p_value:.3f}")
        _p(f"  VERDICT        : {r.verdict}")


def report_trends(results: Sequence[TrendResult], top: int = 15) -> None:
    _p(f"\n{'='*78}\nMODULE 5 — STL / KALMAN (signaux precoces de declin)\n{'='*78}")
    if not results:
        _p("Series trop courtes ou trop peu de clics.")
        return
    declining = [r for r in results if "declin" in r.verdict]
    _p(f"{len(results)} pages retenues (volume suffisant)   —   "
       f"{len(declining)} en declin de tendance\n")
    _p(f"{'page':<50}{'pente/28j':>10}{'z':>7}{'Δtend':>8}{'clics28':>8}")
    _p("-" * 78)
    shown = [r for r in results if "declin" in r.verdict][:top]
    for r in shown:
        ch = f"{r.trend_change_pct:>7.0f}%" if np.isfinite(r.trend_change_pct) else "      —"
        _p(f"{r.path[:49]:<50}{r.trend_slope:>9.0f}%{r.slope_z:>7.1f}"
           f"{ch}{r.recent_clicks:>8.0f}")
    if not shown:
        _p("Aucune page en declin significatif sur la fenetre analysee.")


def report_bridges(rows: Sequence[dict], window: int) -> None:
    _p(f"\n{'='*78}\nSYNTHESE — TOP PAGES PONTS INVISIBLES (fenetre {window} j)\n{'='*78}")
    if not rows:
        _p("Aucune page ne reunit assez de signal sur les trois methodes.")
        return
    _p("Classement par rang moyen des trois methodes. 'direct' = contacts pris")
    _p("SUR la page ; 'assist' = part des parcours convertis ou le contact est")
    _p("pris AILLEURS.\n")
    _p(f"{'#':<3}{'page':<44}{'remov':>7}{'shap':>8}{'betw':>8}{'direct':>7}{'assist':>7}")
    _p("-" * 78)
    for i, r in enumerate(rows, 1):
        ar = r.get("assist_ratio")
        ar_s = f"{ar*100:>6.0f}%" if ar is not None and np.isfinite(ar) else "     —"
        _p(f"{i:<3}{r['path'][:43]:<44}{r['removal_effect']*100:>6.1f}%"
           f"{r['shapley']*100:>7.3f}%{r['betweenness']:>8.4f}"
           f"{r['direct_contacts']:>7}{ar_s}")


def report_invisible(rows: Sequence[dict], window: int) -> None:
    _p(f"\n{'='*78}\nPAGES PONTS INVISIBLES — contribution reelle, contact pris "
       f"ailleurs ({window} j)\n{'='*78}")
    if not rows:
        _p("Aucune page ne remplit les criteres (>=3 parcours convertis, "
           ">=50 % de contacts pris ailleurs).")
        return
    _p(f"{'page':<46}{'perte si retiree':>17}{'assist':>8}{'direct':>7}")
    _p("-" * 78)
    for r in rows:
        _p(f"{r['path'][:45]:<46}{r['removal_contacts']:>13.1f} ct"
           f"{r['assist_ratio']*100:>7.0f}%{r['direct_contacts']:>7}")


# ═══════════════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════════════


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="Framework d'analyse mathematique avancee Cooked",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--module", default="all",
                    choices=["all", "markov", "graph", "shapley", "causal", "trend"])
    ap.add_argument("--window", type=int, default=28,
                    help="fenetre en jours pour les modules 1-3 (defaut 28)")
    ap.add_argument("--source", default="supabase", choices=["supabase", "cache"])
    ap.add_argument("--cache-dir", type=Path, default=None)
    ap.add_argument("--dump-cache", type=Path, default=None,
                    help="exporte les donnees brutes en JSON (reproductibilite)")
    ap.add_argument("--bootstrap", type=int, default=200,
                    help="tirages bootstrap pour l'IC du removal effect (0 = aucun)")
    ap.add_argument("--permutations", type=int, default=3000)
    ap.add_argument("--min-support", type=int, default=3,
                    help="visites converties minimales pour scorer une page")
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--json-out", type=Path, default=None)
    return ap.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)

    if args.source == "cache":
        if not args.cache_dir:
            sys.exit("--source cache exige --cache-dir")
        src: DataSource = CacheSource(args.cache_dir)
    else:
        src = SupabaseSource.from_env()

    want = args.module
    payload: dict[str, Any] = {"window_days": args.window,
                               "generated_at": datetime.now().isoformat(timespec="seconds")}

    sequences: list[VisitSequence] = []
    if want in ("all", "markov", "shapley", "graph"):
        sequences = src.visit_sequences(args.window)

    markov = graph = shapley = None

    if want in ("all", "markov"):
        markov = run_markov(sequences, min_support=args.min_support,
                            bootstrap=args.bootstrap)
        report_markov(markov, args.window)
        payload["markov"] = {
            "p_conversion": markov.p_conversion,
            "n_visits": markov.n_visits,
            "n_conversions": markov.n_conversions,
            "removal": markov.removal,
        }

    if want in ("all", "graph"):
        edges = src.internal_edges(args.window)
        graph = run_graph(edges, sequences)
        report_graph(graph)
        payload["graph"] = {"n_nodes": graph.n_nodes, "n_edges": graph.n_edges,
                            "betweenness": graph.betweenness}

    if want in ("all", "shapley"):
        shapley = run_shapley(sequences, n_perm=args.permutations)
        report_shapley(shapley)
        payload["shapley"] = {"shapley": shapley.shapley,
                              "linear_1_over_l": shapley.linear_1_over_l}

    if want in ("all", "causal"):
        gsc = src.gsc_daily()
        anns = src.annotations()
        results: list[CausalResult] = []
        for a in anns:
            if a.get("kind") != "site_change" or not a.get("paths"):
                continue
            if is_measurement_change(a.get("label")):
                _p(f"  (ignore) {fr_date(a['day'])} — changement de mesure, "
                   f"pas d'intervention site : {(a.get('label') or '')[:60]}")
                continue
            day = a["day"]
            day = date.fromisoformat(day[:10]) if isinstance(day, str) else day
            for p in a["paths"]:
                r = run_causal_impact(gsc, p, day, label=a.get("label", ""),
                                      exclude_paths=a["paths"])
                if r:
                    results.append(r)
        report_causal(results)
        payload["causal"] = [r.__dict__ | {"intervention": fr_date(r.intervention)}
                             for r in results]

    if want in ("all", "trend"):
        gsc = src.gsc_daily()
        trends = run_stl_kalman(gsc)
        report_trends(trends)
        payload["trend"] = [t.__dict__ for t in trends[:40]]

    if want == "all" and markov and graph and shapley:
        try:
            contacts = src.macro_contacts(args.window)
        except Exception:
            contacts = {}
        rows = bridge_pages(markov, graph, shapley, direct_contacts=contacts,
                            top=args.top)
        report_bridges(rows, args.window)
        inv = invisible_bridges(markov, graph, shapley, contacts, top=args.top)
        report_invisible(inv, args.window)
        payload["bridges"] = rows
        payload["invisible_bridges"] = inv

    if args.json_out:
        args.json_out.write_text(json.dumps(payload, indent=2, default=str))
        _p(f"\nResultats JSON : {args.json_out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
