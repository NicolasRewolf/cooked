"use client";

// Ne pas rendre le message serveur brut.
export default function Error({ error }: { error: Error & { digest?: string } }) {
  return (
    <main className="mx-auto max-w-3xl px-6 py-16 sm:px-8">
      <h1 className="text-xl font-semibold">Impossible d’ouvrir Cooked</h1>
      <p className="mt-3 text-sm text-muted">
        Une erreur est survenue. Réessaie dans un moment.
        {error.digest ? ` (réf. ${error.digest})` : ""}
      </p>
      <button onClick={() => window.location.reload()} className="mt-6 bg-ink px-4 py-2 text-sm text-white hover:bg-accent">
        Réessayer
      </button>
    </main>
  );
}
