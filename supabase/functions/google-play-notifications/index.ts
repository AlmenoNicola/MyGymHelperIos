// Edge Function "google-play-notifications": riceve le notifiche in tempo reale di Google Play
// (Real-time developer notifications) tramite una sottoscrizione push Pub/Sub autenticata:
//   endpoint: https://<progetto>.supabase.co/functions/v1/google-play-notifications
// Da distribuire con --no-verify-jwt: l'autenticazione è il token OIDC di Pub/Sub, verificato qui.
//
// Per ogni notifica: verifica il token Pub/Sub, controlla il nome del pacchetto, rilegge lo stato
// dell'abbonamento dalla Google Play Developer API (la notifica da sola non basta), aggiorna
// licensing.entitlements dell'utente indicato da obfuscatedExternalAccountId (= id utente Supabase,
// impostato dall'app negli acquisti) e registra la notifica una sola volta (licensing.store_events).
//
// Segreti: vedi _shared/google.ts; SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY sono già presenti.
import { createClient } from "npm:@supabase/supabase-js@2";
import { env, json } from "../_shared/http.ts";
import {
  fetchSubscription,
  mapSubscription,
  NOTIFICATION_TYPES,
  playAccessToken,
  type ServiceAccount,
  verifyPubSubToken,
} from "../_shared/google.ts";

const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

type DeveloperNotification = {
  packageName?: string;
  eventTimeMillis?: string;
  subscriptionNotification?: { notificationType?: number; purchaseToken?: string; subscriptionId?: string };
  voidedPurchaseNotification?: { purchaseToken?: string; orderId?: string; productType?: number };
  testNotification?: { version?: string };
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const audience = Deno.env.get("GOOGLE_PUBSUB_AUDIENCE") || `${env("SUPABASE_URL")}/functions/v1/google-play-notifications`;
  const authorized = await verifyPubSubToken(req.headers.get("Authorization"), {
    audience,
    email: env("GOOGLE_PUBSUB_SERVICE_ACCOUNT"),
  });
  if (!authorized) return json({ error: "unauthorized" }, 401);

  let messageId: string;
  let n: DeveloperNotification;
  try {
    const body = await req.json() as { message?: { data?: string; messageId?: string } };
    messageId = String(body.message?.messageId ?? "");
    n = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(body.message?.data ?? ""), (c) => c.charCodeAt(0))));
    if (!messageId) throw new Error("messageId mancante");
  } catch {
    // Messaggio illeggibile: si risponde 200 per non farlo ripetere all'infinito (resta nei log).
    console.error("messaggio Pub/Sub non valido");
    return json({ ok: false, error: "bad_message" });
  }

  const packageName = env("GOOGLE_PLAY_PACKAGE");
  if (n.packageName !== packageName) {
    console.error("pacchetto inatteso", n.packageName);
    return json({ ok: false, error: "wrong_package" });
  }

  if (n.testNotification) {
    await admin.rpc("licensing_record_event", {
      p_source: "google", p_notification_id: messageId, p_notification_type: "TEST",
      p_original_transaction_id: null, p_user_id: null, p_payload: n,
    });
    return json({ ok: true, test: true });
  }

  const token = n.subscriptionNotification?.purchaseToken ?? n.voidedPurchaseNotification?.purchaseToken;
  if (!token) return json({ ok: true, ignored: true }); // acquisti singoli: l'app non ne vende
  const type = n.subscriptionNotification?.notificationType;
  const revoked = !!n.voidedPurchaseNotification || type === 12;

  let entitlement;
  let purchase;
  try {
    const sa = JSON.parse(env("GOOGLE_PLAY_SERVICE_ACCOUNT")) as ServiceAccount;
    purchase = await fetchSubscription(packageName, token, await playAccessToken(sa));
    entitlement = mapSubscription(purchase, Date.now(), revoked);
  } catch (err) {
    console.error("lettura abbonamento non riuscita", err);
    return json({ error: "play_api_error" }, 500); // Pub/Sub ripete l'invio
  }

  const { error } = await admin.rpc("licensing_apply_entitlement", {
    p_user_id: entitlement.userId,
    p_tier: entitlement.tier,
    p_status: entitlement.status,
    p_in_trial: entitlement.inTrial,
    p_source: "google",
    p_product_id: entitlement.productId,
    p_original_transaction_id: token,
    p_environment: entitlement.environment,
    p_current_period_end: entitlement.periodEnd,
  });
  if (error) {
    console.error(error);
    return json({ error: "db_error" }, 500);
  }

  const typeName = n.voidedPurchaseNotification ? "VOIDED" : (NOTIFICATION_TYPES[type ?? 0] ?? String(type));
  const { error: eventError } = await admin.rpc("licensing_record_event", {
    p_source: "google",
    p_notification_id: messageId,
    p_notification_type: typeName,
    p_original_transaction_id: token,
    p_user_id: entitlement.userId,
    p_payload: { notification: n, subscription: purchase },
  });
  if (eventError) {
    console.error(eventError);
    return json({ error: "db_error" }, 500);
  }
  return json({ ok: true });
});
