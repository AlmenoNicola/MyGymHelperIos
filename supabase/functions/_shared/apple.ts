// "Accedi con Apple": scambio del codice di autorizzazione e revoca dei token, come richiesto da Apple
// quando l'utente elimina l'account (https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens).
//
// Segreti: APPLE_TEAM_ID, APPLE_SIGNIN_KEY_ID, APPLE_SIGNIN_PRIVATE_KEY (contenuto del file .p8 della chiave
// "Sign in with Apple"), APPLE_BUNDLE_ID (client_id dell'accesso nativo dall'app).
import { importPKCS8, SignJWT } from "npm:jose@5";

const APPLE_AUTH = "https://appleid.apple.com";

export type AppleConfig = { teamId: string; keyId: string; privateKey: string; clientId: string };

export function appleConfigFromEnv(): AppleConfig | null {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_SIGNIN_KEY_ID");
  const privateKey = Deno.env.get("APPLE_SIGNIN_PRIVATE_KEY");
  const clientId = Deno.env.get("APPLE_BUNDLE_ID");
  if (!teamId || !keyId || !privateKey || !clientId) return null;
  // Nei segreti gli a-capo possono arrivare come "\n" letterali.
  return { teamId, keyId, privateKey: privateKey.replace(/\\n/g, "\n"), clientId };
}

/** client_secret per le API di Apple: JWT ES256 firmato con la chiave .p8 (valido 5 minuti). */
export async function makeClientSecret(cfg: AppleConfig, now = Math.floor(Date.now() / 1000)): Promise<string> {
  const key = await importPKCS8(cfg.privateKey, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: cfg.keyId })
    .setIssuer(cfg.teamId)
    .setIssuedAt(now)
    .setExpirationTime(now + 300)
    .setAudience(APPLE_AUTH)
    .setSubject(cfg.clientId)
    .sign(key);
}

async function post(path: string, form: Record<string, string>, fetcher: typeof fetch): Promise<Response> {
  return await fetcher(`${APPLE_AUTH}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form),
  });
}

/** Scambia il codice di autorizzazione (valido 5 minuti, usabile una volta) e revoca il token ottenuto.
 *  Restituisce true se Apple conferma la revoca. */
export async function revokeWithAuthorizationCode(
  cfg: AppleConfig,
  authorizationCode: string,
  fetcher: typeof fetch = fetch,
): Promise<boolean> {
  const clientSecret = await makeClientSecret(cfg);
  const tokenRes = await post("/auth/token", {
    client_id: cfg.clientId,
    client_secret: clientSecret,
    code: authorizationCode,
    grant_type: "authorization_code",
  }, fetcher);
  if (!tokenRes.ok) {
    console.error("Apple /auth/token", tokenRes.status, await tokenRes.text());
    return false;
  }
  const tokens = await tokenRes.json() as { refresh_token?: string; access_token?: string };
  const token = tokens.refresh_token ?? tokens.access_token;
  if (!token) return false;
  const revokeRes = await post("/auth/revoke", {
    client_id: cfg.clientId,
    client_secret: clientSecret,
    token,
    token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
  }, fetcher);
  if (!revokeRes.ok) console.error("Apple /auth/revoke", revokeRes.status, await revokeRes.text());
  return revokeRes.ok;
}
