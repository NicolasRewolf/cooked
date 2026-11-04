import { requireUser } from "@/lib/auth";

export const dynamic = "force-dynamic";

export default async function Page() {
  await requireUser();

  return (
    <main className="mx-auto max-w-3xl px-6 py-16 sm:px-8 sm:py-24">
      <p className="font-mono text-xs uppercase tracking-[0.12em] text-muted">
        Cooked · jplouton-avocat.fr
      </p>
      <h1 className="mt-5 max-w-xl text-3xl font-semibold leading-tight tracking-tight sm:text-4xl">
        Les anciens indicateurs ont été retirés.
      </h1>
      <p className="mt-6 max-w-xl text-base leading-relaxed text-muted">
        La nouvelle interface sera traitée séparément. Les données sources sont conservées.
      </p>
    </main>
  );
}
