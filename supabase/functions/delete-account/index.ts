// Edge Function "delete-account": POST /functions/v1/delete-account con il token dell'utente.
// Corpo facoltativo: { "apple_authorization_code": "..." } per chi e' entrato con "Accedi con Apple";
// dall'app Android: { "platform": "android" } (su Android non si puo' confermare con Apple).
//
// 1. Se l'utente ha un'identita' Apple, revoca i suoi token Apple (richiesto da Apple): l'app chiede
//    all'utente di confermare con Apple e invia il codice di autorizzazione appena ottenuto
//    (valido 5 minuti, nessun token Apple viene salvato sul server).
// 2. Elimina l'utente da Supabase Auth; profilo, elenchi e diritto si cancellano a cascata;
//    in licensing.store_events l'utente diventa null (registro contabile senza dati personali).
// Richiesto da Apple per le app che permettono di creare un account (linea guida 5.1.1(v)).
import { createClient } from "npm:@supabase/supabase-js@2";
import { appleConfigFromEnv, revokeWithAuthorizationCode } from "../_shared/apple.ts";
import { env, json } from "../_shared/http.ts";

const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "unauthorized" }, 401);

  // L'utente si ricava dal suo token: nessuno puo' eliminare l'account di un altro.
  const { data, error } = await admin.auth.getUser(jwt);
  if (error || !data.user) return json({ error: "unauthorized" }, 401);
  const user = data.user;

  let body: { apple_authorization_code?: unknown; platform?: unknown } = {};
  try {
    body = (await req.json()) ?? {};
  } catch {
    // corpo vuoto: va bene per chi non usa Apple
  }

  const usesApple = (user.identities ?? []).some((i) => i.provider === "apple");
  let appleRevoked: boolean | null = null;
  const fromAndroid = body.platform === "android";
  if (usesApple && fromAndroid) {
    // Account creato su iPhone con Apple ed eliminato da Android: niente codice Apple, quindi niente revoca.
    // L'account si elimina comunque; l'utente puo' scollegare l'app da Impostazioni > ID Apple > Accedi con Apple.
    console.warn("Eliminazione da Android di un account Apple: revoca non eseguita", user.id);
    appleRevoked = false;
  } else if (usesApple) {
    const code = typeof body.apple_authorization_code === "string" ? body.apple_authorization_code : "";
    if (!code) return json({ error: "apple_reauth_required" }, 400);
    const cfg = appleConfigFromEnv();
    if (!cfg) {
      console.error("Segreti Apple mancanti: impossibile revocare il token");
      appleRevoked = false;
    } else {
      try {
        appleRevoked = await revokeWithAuthorizationCode(cfg, code);
      } catch (err) {
        console.error("Revoca Apple non riuscita", err);
        appleRevoked = false;
      }
    }
    // Se la revoca non riesce l'account si elimina comunque (l'utente ha diritto alla cancellazione);
    // l'errore resta nei log per un controllo manuale.
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error(deleteError);
    return json({ error: "delete_failed" }, 500);
  }
  return json({ ok: true, apple_revoked: appleRevoked });
});
