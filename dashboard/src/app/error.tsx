"use client";

export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  return (
    <main className="mx-auto max-w-6xl px-4 py-10">
      <div className="rounded-xl border border-red-200 bg-red-50 p-5 dark:border-red-900 dark:bg-red-950/40">
        <h2 className="text-sm font-semibold text-red-800 dark:text-red-300">
          Erreur de chargement des données
        </h2>
        <p className="mt-1 text-xs text-red-700 dark:text-red-400">{error.message}</p>
        <button
          onClick={reset}
          className="mt-3 rounded-md bg-red-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-red-700"
        >
          Réessayer
        </button>
      </div>
    </main>
  );
}
