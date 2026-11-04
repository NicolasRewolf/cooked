"use client";

// Ne pas rendre le message serveur brut.
export default function Error({ error }: { error: Error & { digest?: string } }) {
  return (
    <main className="mx-auto max-w-[1440px] px-4 py-16 sm:px-8 lg:px-10">
      <div className="mx-auto max-w-lg rounded-xl border border-line bg-panel p-6 sm:p-8">
        <span aria-hidden="true" className="mb-5 flex size-10 items-center justify-center rounded-lg border border-line bg-paper text-muted">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" className="size-5">
            <circle cx="12" cy="12" r="9" /><path d="M12 7v6m0 4h.01" />
          </svg>
        </span>
        <h1 className="text-xl font-semibold tracking-tight">Impossible d’ouvrir Cooked</h1>
        <p className="mt-3 text-sm leading-relaxed text-muted">
          Une erreur est survenue. Réessaie dans un moment.
          {error.digest ? ` (réf. ${error.digest})` : ""}
        </p>
        <button onClick={() => window.location.reload()} className="mt-6 inline-flex min-h-10 items-center rounded-lg bg-ink px-4 py-2 text-sm font-medium text-white transition-colors duration-150 hover:bg-ink/85">
          Réessayer
        </button>
      </div>
    </main>
  );
}
