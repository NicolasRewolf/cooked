import "server-only";
import { createClient } from "@supabase/supabase-js";
import { env } from "@/env";

// Client de LECTURE des données, avec la clé service (service_role).
// `import "server-only"` => toute tentative d'import depuis un composant client
// casse le build : la clé ne peut physiquement pas finir dans le bundle navigateur.
// Singleton (réutilisé entre requêtes dans le même runtime serveur).
export const admin = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SECRET_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
