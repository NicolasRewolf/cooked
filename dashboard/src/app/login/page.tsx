"use client";

import { useState } from "react";
import { createBrowserClient } from "@supabase/ssr";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [message, setMessage] = useState("");

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setStatus("sending");
    setMessage("");
    const supabase = createBrowserClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    );
    const next = new URLSearchParams(window.location.search).get("next") ?? "/";
    const redirect = `${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`;
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: { emailRedirectTo: redirect },
    });
    if (error) {
      setStatus("error");
      setMessage(error.message);
    } else {
      setStatus("sent");
    }
  }

  return (
    <main className="flex min-h-dvh items-center justify-center p-6">
      <div className="w-full max-w-sm">
        <div className="mb-8 flex items-center gap-3">
          <span
            className="inline-flex h-7 w-7 items-center justify-center border-[1.5px] border-accent font-mono text-sm font-bold text-accent"
            style={{ transform: "scaleX(-1)" }}
            aria-hidden
          >
            R
          </span>
          <div>
            <p className="font-mono text-[10px] uppercase tracking-[0.14em] text-faint">Cooked</p>
            <h1 className="text-lg font-semibold tracking-[-0.01em] text-ink">Tableau de bord</h1>
          </div>
        </div>

        {status === "sent" ? (
          <div className="border border-line bg-panel p-4 text-sm text-muted">
            Lien de connexion envoyé à <strong className="text-ink">{email}</strong>. Ouvre-le sur cet
            appareil pour accéder au dashboard.
          </div>
        ) : (
          <form onSubmit={onSubmit} className="space-y-3">
            <label htmlFor="email" className="block text-sm text-muted">
              Adresse e-mail autorisée
            </label>
            <input
              id="email"
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="prenom@exemple.fr"
              className="w-full border border-line-strong bg-white px-3 py-2 text-sm text-ink outline-none focus-visible:border-accent focus-visible:ring-2 focus-visible:ring-accent/30"
            />
            <button
              type="submit"
              disabled={status === "sending"}
              className="w-full bg-ink px-3 py-2 text-sm font-medium text-white transition-colors hover:bg-accent disabled:opacity-50"
            >
              {status === "sending" ? "Envoi…" : "Recevoir un lien de connexion"}
            </button>
            {status === "error" && <p className="text-sm text-down">{message}</p>}
          </form>
        )}
      </div>
    </main>
  );
}
