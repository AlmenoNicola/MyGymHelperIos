// Test: deno test supabase/functions/_shared/apple_test.ts
import { deepStrictEqual as assertEquals, ok as assert } from "node:assert";
import { exportPKCS8, exportSPKI, generateKeyPair, importSPKI, jwtVerify } from "npm:jose@5";
import { type AppleConfig, makeClientSecret, revokeWithAuthorizationCode } from "./apple.ts";

async function testConfig(): Promise<{ cfg: AppleConfig; publicPem: string }> {
  const { privateKey, publicKey } = await generateKeyPair("ES256", { extractable: true });
  return {
    cfg: { teamId: "TEAM123456", keyId: "KEY1234567", privateKey: await exportPKCS8(privateKey), clientId: "app.mygymhelper" },
    publicPem: await exportSPKI(publicKey),
  };
}

Deno.test("client secret: JWT ES256 con i campi richiesti da Apple", async () => {
  const { cfg, publicPem } = await testConfig();
  const jwt = await makeClientSecret(cfg, 1_800_000_000);
  const { payload, protectedHeader } = await jwtVerify(jwt, await importSPKI(publicPem, "ES256"), {
    audience: "https://appleid.apple.com",
    issuer: "TEAM123456",
    currentDate: new Date(1_800_000_010 * 1000),
  });
  assertEquals(protectedHeader.alg, "ES256");
  assertEquals(protectedHeader.kid, "KEY1234567");
  assertEquals(payload.sub, "app.mygymhelper");
  assertEquals(payload.exp! - payload.iat!, 300);
});

Deno.test("scambio del codice e revoca del refresh token", async () => {
  const { cfg } = await testConfig();
  const calls: { url: string; form: URLSearchParams }[] = [];
  const fakeFetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const form = new URLSearchParams(String(init?.body));
    calls.push({ url: String(input), form });
    if (String(input).endsWith("/auth/token")) {
      return new Response(JSON.stringify({ refresh_token: "r-123", access_token: "a-123" }), { status: 200 });
    }
    return new Response("", { status: 200 });
  }) as typeof fetch;

  const ok = await revokeWithAuthorizationCode(cfg, "code-abc", fakeFetch);
  assert(ok);
  assertEquals(calls.length, 2);
  assertEquals(calls[0].url, "https://appleid.apple.com/auth/token");
  assertEquals(calls[0].form.get("grant_type"), "authorization_code");
  assertEquals(calls[0].form.get("code"), "code-abc");
  assertEquals(calls[1].url, "https://appleid.apple.com/auth/revoke");
  assertEquals(calls[1].form.get("token"), "r-123");
  assertEquals(calls[1].form.get("token_type_hint"), "refresh_token");
  assertEquals(calls[1].form.get("client_id"), "app.mygymhelper");
});

Deno.test("codice rifiutato da Apple: nessuna revoca, risultato false", async () => {
  const { cfg } = await testConfig();
  let revokeCalled = false;
  const fakeFetch = (async (input: string | URL | Request) => {
    if (String(input).endsWith("/auth/revoke")) revokeCalled = true;
    return new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 });
  }) as typeof fetch;
  assertEquals(await revokeWithAuthorizationCode(cfg, "scaduto", fakeFetch), false);
  assert(!revokeCalled);
});
