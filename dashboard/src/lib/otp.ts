// Magic-link réservé aux comptes existants. L'allowlist est contrôlée après
// authentification par le proxy et la page serveur.

export type OtpPayload = {
  email: string;
  options: { emailRedirectTo: string; shouldCreateUser: false };
};

export function otpSignInPayload(email: string, redirectTo: string): OtpPayload {
  return {
    email: email.trim(),
    options: { emailRedirectTo: redirectTo, shouldCreateUser: false },
  };
}
