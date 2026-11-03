// Google Play: verifica delle notifiche in tempo reale (Pub/Sub push autenticato), accesso alla
// Google Play Developer API con un account di servizio e conversione dello stato dell'abbonamento.
//
// Segreti: GOOGLE_PLAY_PACKAGE (es. app.mygymhelper), GOOGLE_PLAY_SERVICE_ACCOUNT (JSON della chiave
// dell'account di servizio con accesso all'app in Play Console), GOOGLE_PUBSUB_AUDIENCE (pubblico indicato
// nella sottoscrizione push; se manca si usa l'URL della funzione), GOOGLE_PUBSUB_SERVICE_ACCOUNT (e-mail
// dell'account di servizio scelto per l'autenticazione della sottoscrizione push).
import { createRemoteJWKSet, importPKCS8, type JWTVerifyGetKey, jwtVerify, SignJWT } from "npm:jose@5";

export const GOOGLE_CERTS = "https://www.googleapis.com/oauth2/v3/certs";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/androidpublisher";
export const TRIAL_OFFER_ID = "free-trial";

let googleKeys: JWTVerifyGetKey | null = null;

/** Verifica il token OIDC che Pub/Sub allega alle richieste push (firma Google, pubblico, account di servizio). */
export async function verifyPubSubToken(
  authorization: string | null,
  opts: { audience: string; email: string; keys?: JWTVerifyGetKey; currentDate?: Date },
): Promise<boolean> {
  const token = (authorization ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return false;
  const keys = opts.keys ?? (googleKeys ??= createRemoteJWKSet(new URL(GOOGLE_CERTS)));
  try {
    const { payload } = await jwtVerify(token, keys, {
      audience: opts.audience,
      issuer: ["https://accounts.google.com", "accounts.google.com"],
      currentDate: opts.currentDate,
    });
    return payload.email === opts.email && payload.email_verified === true;
  } catch {
    return false;
  }
}

export type ServiceAccount = { client_email: string; private_key: string; token_uri?: string };

let cachedToken: { value: string; expiresAt: number } | null = null;

/** Token OAuth2 dell'account di servizio per la Google Play Developer API (JWT RS256 scambiato con Google). */
export async function playAccessToken(sa: ServiceAccount, fetcher: typeof fetch = fetch, now = Date.now()): Promise<string> {
  if (cachedToken && cachedToken.expiresAt - 60_000 > now) return cachedToken.value;
  const iat = Math.floor(now / 1000);
  const key = await importPKCS8(sa.private_key.replace(/\\n/g, "\n"), "RS256");
  const assertion = await new SignJWT({ scope: SCOPE })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience(sa.token_uri ?? TOKEN_URL)
    .setIssuedAt(iat)
    .setExpirationTime(iat + 3600)
    .sign(key);
  const res = await fetcher(sa.token_uri ?? TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`token Google: ${res.status} ${await res.text()}`);
  const body = await res.json() as { access_token: string; expires_in?: number };
  cachedToken = { value: body.access_token, expiresAt: now + (body.expires_in ?? 3600) * 1000 };
  return body.access_token;
}

/** Legge lo stato attuale di un abbonamento (purchases.subscriptionsv2.get). */
export async function fetchSubscription(
  packageName: string,
  purchaseToken: string,
  accessToken: string,
  fetcher: typeof fetch = fetch,
): Promise<SubscriptionPurchaseV2> {
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}` +
    `/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const res = await fetcher(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!res.ok) throw new Error(`Play API: ${res.status} ${await res.text()}`);
  return await res.json() as SubscriptionPurchaseV2;
}

// Solo i campi usati (https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2).
export type SubscriptionPurchaseV2 = {
  subscriptionState?: string;
  startTime?: string;
  linkedPurchaseToken?: string;
  testPurchase?: Record<string, unknown>;
  externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string };
  lineItems?: { productId?: string; expiryTime?: string; offerDetails?: { basePlanId?: string; offerId?: string } }[];
};

export type Entitlement = {
  tier: "free" | "mid" | "full";
  status: "active" | "trial" | "grace" | "expired" | "revoked";
  inTrial: boolean;
  productId: string | null;
  periodEnd: string | null;
  userId: string | null;
  environment: "production" | "sandbox";
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function tierForProduct(productId: string | undefined | null): "free" | "mid" | "full" {
  if (productId === "mygymhelper_full") return "full";
  if (productId === "mygymhelper_mid") return "mid";
  return "free";
}

/**
 * Converte lo stato Google Play nello stato del diritto (stessa tabella dell'app iOS).
 * - ACTIVE: attivo (o prova, se l'offerta è "free-trial" e non sono passati 7 giorni dall'inizio);
 * - CANCELED: annullato ma pagato fino alla scadenza → attivo fino a expiryTime;
 * - IN_GRACE_PERIOD: tolleranza (accesso mantenuto);
 * - ON_HOLD, PAUSED, EXPIRED: nessun accesso; PENDING: nessun accesso finché non è pagato.
 * `revoked`: notifica di revoca o rimborso (voided purchase).
 */
export function mapSubscription(p: SubscriptionPurchaseV2, now = Date.now(), revoked = false): Entitlement {
  const item = [...(p.lineItems ?? [])].sort((a, b) =>
    Date.parse(b.expiryTime ?? "0") - Date.parse(a.expiryTime ?? "0")
  )[0];
  const productId = item?.productId ?? null;
  const expiry = item?.expiryTime ? Date.parse(item.expiryTime) : NaN;
  const account = p.externalAccountIdentifiers?.obfuscatedExternalAccountId?.toLowerCase() ?? "";
  const base = {
    productId,
    periodEnd: Number.isFinite(expiry) ? new Date(expiry).toISOString() : null,
    userId: UUID_RE.test(account) ? account : null,
    environment: p.testPurchase ? "sandbox" as const : "production" as const,
  };
  const none = (status: Entitlement["status"]): Entitlement => ({ ...base, tier: "free", status, inTrial: false });
  if (revoked) return none("revoked");

  const tier = tierForProduct(productId);
  const start = p.startTime ? Date.parse(p.startTime) : NaN;
  const inTrial = item?.offerDetails?.offerId === TRIAL_OFFER_ID && Number.isFinite(start) && now < start + 7 * 86_400_000;
  switch (p.subscriptionState) {
    case "SUBSCRIPTION_STATE_ACTIVE":
      return { ...base, tier, status: inTrial ? "trial" : "active", inTrial };
    case "SUBSCRIPTION_STATE_CANCELED":
      return Number.isFinite(expiry) && expiry > now
        ? { ...base, tier, status: inTrial ? "trial" : "active", inTrial }
        : none("expired");
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      return { ...base, tier, status: "grace", inTrial: false };
    default: // ON_HOLD, PAUSED, EXPIRED, PENDING, PENDING_PURCHASE_CANCELED, sconosciuto
      return none("expired");
  }
}

/** Nomi dei tipi di notifica (developer notifications), per il registro. */
export const NOTIFICATION_TYPES: Record<number, string> = {
  1: "RECOVERED", 2: "RENEWED", 3: "CANCELED", 4: "PURCHASED", 5: "ON_HOLD", 6: "IN_GRACE_PERIOD",
  7: "RESTARTED", 8: "PRICE_CHANGE_CONFIRMED", 9: "DEFERRED", 10: "PAUSED", 11: "PAUSE_SCHEDULE_CHANGED",
  12: "REVOKED", 13: "EXPIRED", 17: "ITEMS_CHANGED", 18: "CANCELLATION_SCHEDULED", 19: "PRICE_CHANGE_UPDATED",
  20: "PENDING_PURCHASE_CANCELED",
};
