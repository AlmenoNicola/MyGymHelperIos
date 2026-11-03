// Edge Function "apple-notifications": URL da inserire in App Store Connect > App > Informazioni app >
// App Store Server Notifications (versione 2), sia Production sia Sandbox:
//   https://<progetto>.supabase.co/functions/v1/apple-notifications
// Verifica la firma JWS con la libreria ufficiale Apple e i certificati radice Apple, registra la notifica
// una sola volta (licensing.store_events) e aggiorna licensing.entitlements dell'utente indicato
// da appAccountToken (= id utente Supabase, impostato dall'app negli acquisti).
//
// Segreti richiesti: APPLE_BUNDLE_ID (es. app.mygymhelper), APPLE_APP_ID (Apple ID numerico dell'app,
// necessario per l'ambiente Production), SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY (gia' presenti).
import { Buffer } from "node:buffer";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  Environment,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@1";
import { env, json } from "../_shared/http.ts";

const ROOT_CERT_URLS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
  "https://www.apple.com/appleca/AppleIncRootCertificate.cer",
];

const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

let verifiers: { production: SignedDataVerifier; sandbox: SignedDataVerifier } | null = null;

async function getVerifiers() {
  if (verifiers) return verifiers;
  const roots = await Promise.all(
    ROOT_CERT_URLS.map(async (u) => Buffer.from(new Uint8Array(await (await fetch(u)).arrayBuffer()))),
  );
  const bundleId = env("APPLE_BUNDLE_ID");
  const appAppleId = Number(Deno.env.get("APPLE_APP_ID") ?? "0") || undefined;
  verifiers = {
    // enableOnlineChecks: controllo di revoca dei certificati (OCSP)
    production: new SignedDataVerifier(roots, true, Environment.PRODUCTION, bundleId, appAppleId),
    sandbox: new SignedDataVerifier(roots, true, Environment.SANDBOX, bundleId),
  };
  return verifiers;
}

function tierFor(productId: string | undefined): "free" | "mid" | "full" {
  if (!productId) return "free";
  if (productId.includes(".full.")) return "full";
  if (productId.includes(".mid.")) return "mid";
  return "free";
}

/** Stato dell'abbonamento: usa data.status (1 attivo, 2 scaduto, 3 tentativo di addebito, 4 periodo di tolleranza,
 *  5 revocato); se manca, lo deduce dal tipo di notifica e dalla scadenza. */
function statusFor(
  n: ResponseBodyV2DecodedPayload,
  t: JWSTransactionDecodedPayload,
): "active" | "trial" | "grace" | "expired" | "revoked" {
  if (t.revocationDate) return "revoked";
  const inTrial = t.offerType === 1 && String(t.offerDiscountType ?? "") === "FREE_TRIAL";
  const s = n.data?.status as number | undefined;
  if (s === 5) return "revoked";
  if (s === 4) return "grace";
  if (s === 2 || s === 3) return "expired";
  if (s === 1) return inTrial ? "trial" : "active";
  const type = String(n.notificationType ?? "");
  if (type === "REFUND" || type === "REVOKE") return "revoked";
  if (type === "EXPIRED" || type === "GRACE_PERIOD_EXPIRED") return "expired";
  if (type === "DID_FAIL_TO_RENEW") return String(n.subtype ?? "") === "GRACE_PERIOD" ? "grace" : "expired";
  if (t.expiresDate && t.expiresDate < Date.now()) return "expired";
  return inTrial ? "trial" : "active";
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let signedPayload: string;
  try {
    ({ signedPayload } = await req.json());
    if (typeof signedPayload !== "string") throw new Error("payload mancante");
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const { production, sandbox } = await getVerifiers();
  let verifier = production;
  let notification: ResponseBodyV2DecodedPayload;
  try {
    notification = await production.verifyAndDecodeNotification(signedPayload);
  } catch {
    try {
      notification = await sandbox.verifyAndDecodeNotification(signedPayload);
      verifier = sandbox;
    } catch (err) {
      console.error("firma non valida", err);
      return json({ error: "invalid_signature" }, 400);
    }
  }

  const notificationId = notification.notificationUUID ?? crypto.randomUUID();
  const signedTx = notification.data?.signedTransactionInfo;
  let tx: JWSTransactionDecodedPayload | null = null;
  if (signedTx) {
    try {
      tx = await verifier.verifyAndDecodeTransaction(signedTx);
    } catch (err) {
      console.error("transazione non valida", err);
      return json({ error: "invalid_transaction" }, 400);
    }
  }

  const token = tx?.appAccountToken?.toLowerCase();
  const userId = token && UUID_RE.test(token) ? token : null;

  // Prima si aggiorna il diritto (operazione idempotente: rielaborare la stessa notifica da' lo stesso risultato),
  // poi si registra la notifica. Se qualcosa fallisce si risponde 500 e Apple ripete l'invio.
  if (tx) {
    const status = statusFor(notification, tx);
    const hasAccess = status === "active" || status === "trial" || status === "grace";
    const { error } = await admin.rpc("licensing_apply_entitlement", {
      p_user_id: userId,
      p_tier: hasAccess ? tierFor(tx.productId) : "free",
      p_status: status,
      p_in_trial: status === "trial",
      p_source: "apple",
      p_product_id: tx.productId ?? null,
      p_original_transaction_id: tx.originalTransactionId ?? null,
      p_environment: verifier === sandbox ? "sandbox" : "production",
      p_current_period_end: tx.expiresDate ? new Date(tx.expiresDate).toISOString() : null,
    });
    if (error) {
      console.error(error);
      return json({ error: "db_error" }, 500);
    }
  }

  const { error: eventError } = await admin.rpc("licensing_record_event", {
    p_source: "apple",
    p_notification_id: notificationId,
    p_notification_type: [notification.notificationType, notification.subtype].filter(Boolean).join("/"),
    p_original_transaction_id: tx?.originalTransactionId ?? null,
    p_user_id: userId,
    p_payload: { notification, transaction: tx },
  });
  if (eventError) {
    console.error(eventError);
    return json({ error: "db_error" }, 500);
  }
  return json({ ok: true });
});
