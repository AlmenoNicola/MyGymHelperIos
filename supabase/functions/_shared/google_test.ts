// Test: deno test supabase/functions/_shared/google_test.ts
import { deepStrictEqual as assertEquals, ok as assert } from "node:assert";
import { exportPKCS8, generateKeyPair, SignJWT } from "npm:jose@5";
import { mapSubscription, playAccessToken, type SubscriptionPurchaseV2, verifyPubSubToken } from "./google.ts";

const USER = "22222222-2222-2222-2222-222222222222";
const NOW = Date.parse("2026-10-20T12:00:00Z");

function purchase(state: string, opts: Partial<{ product: string; offer: string; start: string; expiry: string; test: boolean }> = {}): SubscriptionPurchaseV2 {
  return {
    subscriptionState: state,
    startTime: opts.start ?? "2026-10-18T12:00:00Z",
    testPurchase: opts.test ? {} : undefined,
    externalAccountIdentifiers: { obfuscatedExternalAccountId: USER },
    lineItems: [{ productId: opts.product ?? "mygymhelper_full", expiryTime: opts.expiry ?? "2026-11-18T12:00:00Z",
      offerDetails: { basePlanId: "monthly", offerId: opts.offer } }],
  };
}

Deno.test("attivo, prova e ambiente di test", () => {
  const e = mapSubscription(purchase("SUBSCRIPTION_STATE_ACTIVE", { offer: "free-trial", test: true }), NOW);
  assertEquals([e.tier, e.status, e.inTrial, e.userId, e.environment], ["full", "trial", true, USER, "sandbox"]);
  const later = mapSubscription(purchase("SUBSCRIPTION_STATE_ACTIVE", { offer: "free-trial", start: "2026-09-01T00:00:00Z" }), NOW);
  assertEquals([later.status, later.inTrial, later.environment], ["active", false, "production"]);
  assertEquals(mapSubscription(purchase("SUBSCRIPTION_STATE_ACTIVE", { product: "mygymhelper_mid" }), NOW).tier, "mid");
});

Deno.test("annullato: accesso fino alla scadenza", () => {
  assertEquals(mapSubscription(purchase("SUBSCRIPTION_STATE_CANCELED"), NOW).status, "active");
  const past = mapSubscription(purchase("SUBSCRIPTION_STATE_CANCELED", { expiry: "2026-10-19T00:00:00Z" }), NOW);
  assertEquals([past.tier, past.status], ["free", "expired"]);
});

Deno.test("tolleranza, sospensione, scadenza, revoca", () => {
  assertEquals(mapSubscription(purchase("SUBSCRIPTION_STATE_IN_GRACE_PERIOD"), NOW).status, "grace");
  for (const s of ["SUBSCRIPTION_STATE_ON_HOLD", "SUBSCRIPTION_STATE_PAUSED", "SUBSCRIPTION_STATE_EXPIRED", "SUBSCRIPTION_STATE_PENDING"]) {
    const e = mapSubscription(purchase(s), NOW);
    assertEquals([e.tier, e.status], ["free", "expired"]);
  }
  const r = mapSubscription(purchase("SUBSCRIPTION_STATE_ACTIVE"), NOW, true);
  assertEquals([r.tier, r.status], ["free", "revoked"]);
});

Deno.test("id account non valido: nessun utente", () => {
  const p = purchase("SUBSCRIPTION_STATE_ACTIVE");
  p.externalAccountIdentifiers = { obfuscatedExternalAccountId: "not-a-uuid" };
  assertEquals(mapSubscription(p, NOW).userId, null);
});

Deno.test("token Pub/Sub: pubblico ed e-mail dell'account di servizio", async () => {
  const { privateKey, publicKey } = await generateKeyPair("RS256");
  const keys = async () => publicKey;
  const make = (aud: string, email: string, verified = true) =>
    new SignJWT({ email, email_verified: verified }).setProtectedHeader({ alg: "RS256" })
      .setIssuer("https://accounts.google.com").setAudience(aud).setIssuedAt().setExpirationTime("1h").sign(privateKey);
  const opts = { audience: "https://x.supabase.co/functions/v1/google-play-notifications", email: "push@p.iam.gserviceaccount.com", keys };
  assert(await verifyPubSubToken(`Bearer ${await make(opts.audience, opts.email)}`, opts));
  assert(!await verifyPubSubToken(`Bearer ${await make("https://altro", opts.email)}`, opts));
  assert(!await verifyPubSubToken(`Bearer ${await make(opts.audience, "altro@x.com")}`, opts));
  assert(!await verifyPubSubToken(`Bearer ${await make(opts.audience, opts.email, false)}`, opts));
  assert(!await verifyPubSubToken(null, opts));
});

Deno.test("token di accesso dell'account di servizio (JWT bearer)", async () => {
  const { privateKey } = await generateKeyPair("RS256", { extractable: true });
  let form: URLSearchParams | null = null;
  const fakeFetch = (async (_input: string | URL | Request, init?: RequestInit) => {
    form = new URLSearchParams(String(init?.body));
    return new Response(JSON.stringify({ access_token: "ya29.test", expires_in: 3600 }), { status: 200 });
  }) as typeof fetch;
  const token = await playAccessToken({ client_email: "sa@p.iam.gserviceaccount.com", private_key: await exportPKCS8(privateKey) }, fakeFetch, NOW);
  assertEquals(token, "ya29.test");
  assertEquals(form!.get("grant_type"), "urn:ietf:params:oauth:grant-type:jwt-bearer");
  const claims = JSON.parse(atob(form!.get("assertion")!.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
  assertEquals(claims.scope, "https://www.googleapis.com/auth/androidpublisher");
  assertEquals(claims.iss, "sa@p.iam.gserviceaccount.com");
  assertEquals(claims.aud, "https://oauth2.googleapis.com/token");
});
