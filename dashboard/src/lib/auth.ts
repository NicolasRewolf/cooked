import "server-only";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { redirect } from "next/navigation";
import { allowedEmails } from "@/env";

// Défense en profondeur (M2) : en plus du gate proxy.ts, chaque page serveur
// re-vérifie la session + l'allowlist avant de lire des données. Si le proxy
// régressait, les pages resteraient fermées.
export async function requireUser() {
  const cookieStore = await cookies();
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        // RSC ne peut pas écrire les cookies ; le refresh de session est géré par proxy.ts.
        setAll() {},
      },
    },
  );
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const email = user?.email?.toLowerCase();
  if (!email || !allowedEmails.includes(email)) redirect("/login");
  return user;
}
