"use client";

import { useState, useRef, useEffect } from "react";
import { createPortal } from "react-dom";

// M1 — explication visible à UN CLIC (tactile d'abord, pas au survol). Aucune lib
// externe : useRef + calcul de position. Fermé par Escape, clic-dehors, scroll.
// Positionné en `fixed` (et non `absolute`) pour ÉCHAPPER au clipping du conteneur
// `overflow-auto` des tableaux — sinon le popover serait coupé. Rendu par PORTAIL
// sur <body> : depuis que les en-têtes de tableau sont `sticky` AVEC un z-index,
// chaque <th> ouvre un contexte d'empilement, et un `fixed` resté à l'intérieur
// verrait son z-index résolu DANS ce contexte (donc sous la colonne figée, z-7).
// Le portail le remet à la racine, où son z-index compte vraiment. Props plates
// (children = texte) : ce composant est client, rendu par un parent client
// (SortableTable) ou serveur (KpiHeader) avec du texte, jamais une fonction.
export function Info({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  const [style, setStyle] = useState<React.CSSProperties>({});
  const btnRef = useRef<HTMLButtonElement>(null);
  const popRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const close = () => setOpen(false);
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setOpen(false);
        btnRef.current?.focus();
      }
    }
    function onDown(e: MouseEvent) {
      const t = e.target as Node;
      if (btnRef.current?.contains(t) || popRef.current?.contains(t)) return;
      setOpen(false);
    }
    document.addEventListener("keydown", onKey);
    document.addEventListener("mousedown", onDown);
    window.addEventListener("scroll", close, true);
    window.addEventListener("resize", close);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("mousedown", onDown);
      window.removeEventListener("scroll", close, true);
      window.removeEventListener("resize", close);
    };
  }, [open]);

  function toggle(e: React.MouseEvent) {
    e.stopPropagation();
    e.preventDefault();
    if (open) {
      setOpen(false);
      return;
    }
    const r = btnRef.current!.getBoundingClientRect();
    const W = 280;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const openLeft = vw - r.left < W + 12; // proche du bord droit → ouvre vers la gauche
    let left = openLeft ? r.right - W : r.left;
    left = Math.max(8, Math.min(left, vw - W - 8)); // toujours dans le viewport
    const spaceBelow = vh - r.bottom;
    const spaceAbove = r.top;
    // dessous par défaut (cas des en-têtes de tableau) ; au-dessus seulement si
    // dessous est à l'étroit ET qu'il y a plus de place au-dessus. maxHeight borne
    // le popover à l'espace disponible (scroll interne) → jamais hors-écran.
    const below = spaceBelow >= 120 || spaceBelow >= spaceAbove;
    const s: React.CSSProperties = { position: "fixed", width: W, left, overflowY: "auto" };
    if (below) {
      s.top = Math.round(r.bottom + 6);
      s.maxHeight = Math.round(spaceBelow - 12);
    } else {
      s.bottom = Math.round(vh - r.top + 6);
      s.maxHeight = Math.round(spaceAbove - 12);
    }
    setStyle(s);
    setOpen(true);
  }

  return (
    <span className="inline-flex align-middle">
      <button
        ref={btnRef}
        type="button"
        onClick={toggle}
        aria-label="explication"
        aria-expanded={open}
        className="inline-flex h-[13px] w-[13px] items-center justify-center rounded-full border border-current text-[8px] font-bold not-italic leading-none text-dim transition-colors hover:text-accent focus-visible:text-accent focus-visible:outline-none"
      >
        i
      </button>
      {open
        ? createPortal(
            <div
              ref={popRef}
              role="tooltip"
              style={style}
              className="z-50 bg-panel px-3 py-2.5 text-left font-sans text-[11.5px] font-normal normal-case leading-snug tracking-normal text-muted shadow-overlay"
            >
              {children}
            </div>,
            document.body,
          )
        : null}
    </span>
  );
}
