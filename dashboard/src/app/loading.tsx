export default function Loading() {
  return (
    <main className="mx-auto max-w-[1440px] px-4 py-8 sm:px-8 lg:px-10" aria-busy="true">
      <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Pages du site</h1>
      <p role="status" className="mt-2 text-sm text-muted">Chargement des données…</p>
      <div aria-hidden="true" className="mt-8 overflow-hidden rounded-xl border border-line bg-panel">
        <div className="flex gap-3 border-b border-line px-5 py-5">
          <span className="h-8 w-24 rounded-md bg-paper" />
          <span className="h-8 w-24 rounded-md bg-paper" />
          <span className="h-8 w-24 rounded-md bg-paper" />
        </div>
        <div className="h-11 border-b border-line bg-paper" />
        {Array.from({ length: 6 }, (_, index) => (
          <div key={index} className="grid grid-cols-[2fr_1fr_1fr] gap-8 border-b border-line px-5 py-7 last:border-0 sm:grid-cols-[3fr_1fr_1fr_1fr_1fr]">
            <span className="h-3 w-4/5 rounded bg-paper" />
            <span className="ml-auto h-3 w-12 rounded bg-paper" />
            <span className="ml-auto h-3 w-12 rounded bg-paper" />
            <span className="ml-auto hidden h-3 w-12 rounded bg-paper sm:block" />
            <span className="ml-auto hidden h-3 w-12 rounded bg-paper sm:block" />
          </div>
        ))}
      </div>
    </main>
  );
}
