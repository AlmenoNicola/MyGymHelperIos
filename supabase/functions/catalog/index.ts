// Edge Function "catalog": GET /functions/v1/catalog?lang=it
// Costruisce il catalogo esercizi dall'API MuscleWiki (chiave nel segreto MUSCLEWIKI_API_KEY, mai nell'app),
// lo tiene in public.catalog_cache al massimo 30 giorni (condizioni MuscleWiki) e lo restituisce
// nel formato del DTO `Exercise` dell'app (Core/Sources/MyGymHelperCore/Exercises.swift).
// Non salva ne' restituisce video o immagini: le condizioni MuscleWiki lo vietano.
import { createClient } from "npm:@supabase/supabase-js@2";
import { env, json } from "../_shared/http.ts";

const MW_BASE = "https://api.musclewiki.com";
const MAX_CACHE_DAYS = 30;
// Giorni di validita' della cache (<= 30). Meno giorni = dati piu' freschi ma piu' chiamate a MuscleWiki.
const CACHE_DAYS = Math.min(Number(Deno.env.get("CATALOG_CACHE_DAYS") ?? "14"), MAX_CACHE_DAYS);
// Numero massimo di esercizi (ogni esercizio costa una chiamata di dettaglio).
const MAX_EXERCISES = Number(Deno.env.get("CATALOG_MAX_EXERCISES") ?? "300");
const CONCURRENCY = 5;

type AppExercise = {
  id: number;
  name: string;
  primary_muscles: string[];
  secondary_muscles: string[] | null;
  category: string | null;
  difficulty: string | null;
  force: string | null;
  mechanic: string | null;
  steps: string[];
};

const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

async function mw(path: string, params: Record<string, string>, attempt = 0): Promise<unknown> {
  const url = new URL(path, MW_BASE);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  const res = await fetch(url, { headers: { "X-API-Key": env("MUSCLEWIKI_API_KEY"), Accept: "application/json" } });
  if (res.status === 429 && attempt < 4) {
    await new Promise((r) => setTimeout(r, 1000 * 2 ** attempt)); // troppe richieste: attesa crescente
    return mw(path, params, attempt + 1);
  }
  if (!res.ok) throw new Error(`MuscleWiki ${path}: HTTP ${res.status}`);
  return res.json();
}

/** "it" -> codice MuscleWiki (es. "it-it" se esiste), altrimenti "en-us". */
let languagesCache: { code: string }[] | null = null;
async function resolveLanguage(lang: string): Promise<string> {
  const base = lang.toLowerCase().split(/[-_]/)[0];
  if (base === "en") return "en-us";
  try {
    languagesCache ??= (await mw("/languages", {})) as { code: string }[];
    const exact = languagesCache.find((l) => l.code.toLowerCase() === lang.toLowerCase());
    const byBase = languagesCache.find((l) => l.code.toLowerCase().split("-")[0] === base);
    return (exact ?? byBase)?.code ?? "en-us";
  } catch {
    return "en-us";
  }
}

async function buildCatalog(lang: string): Promise<AppExercise[]> {
  // 1) elenco (solo id e nome), a pagine da 100
  const ids: number[] = [];
  for (let offset = 0; ids.length < MAX_EXERCISES; offset += 100) {
    const page = (await mw("/exercises", { limit: "100", offset: String(offset), lang })) as {
      results?: { id: number }[];
      total?: number;
    };
    const results = page.results ?? [];
    ids.push(...results.map((r) => r.id));
    if (results.length < 100 || (page.total !== undefined && offset + 100 >= page.total)) break;
  }
  const wanted = ids.slice(0, MAX_EXERCISES);

  // 2) dettaglio di ogni esercizio, poche richieste alla volta
  const out: AppExercise[] = [];
  for (let i = 0; i < wanted.length; i += CONCURRENCY) {
    const chunk = wanted.slice(i, i + CONCURRENCY);
    const details = await Promise.allSettled(chunk.map((id) => mw(`/exercises/${id}`, { lang })));
    for (const d of details) {
      if (d.status !== "fulfilled") continue;
      const e = d.value as Record<string, unknown>;
      const primary = Array.isArray(e.primary_muscles) ? (e.primary_muscles as string[]) : [];
      if (typeof e.id !== "number" || typeof e.name !== "string" || primary.length === 0) continue;
      out.push({
        id: e.id,
        name: e.name,
        primary_muscles: primary,
        secondary_muscles: Array.isArray(e.secondary_muscles) ? (e.secondary_muscles as string[]) : null,
        category: typeof e.category === "string" ? e.category : null,
        difficulty: typeof e.difficulty === "string" ? e.difficulty : null,
        force: typeof e.force === "string" ? e.force : null,
        mechanic: typeof e.mechanic === "string" ? e.mechanic : null,
        steps: Array.isArray(e.steps) ? (e.steps as string[]) : [],
        // videos, bodymap_*: volutamente esclusi (non si salvano ne' si inoltrano)
      });
    }
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method !== "GET") return json({ error: "method_not_allowed" }, 405);
  const requested = (new URL(req.url).searchParams.get("lang") ?? "en").slice(0, 12);
  try {
    let lang = await resolveLanguage(requested);

    const { data: cached } = await admin
      .from("catalog_cache")
      .select("exercises, expires_at")
      .eq("language", lang)
      .maybeSingle();
    if (cached && new Date(cached.expires_at) > new Date()) {
      return json(cached.exercises, 200, { "Cache-Control": "private, max-age=3600" });
    }

    let exercises: AppExercise[];
    try {
      exercises = await buildCatalog(lang);
    } catch (err) {
      // Lingue diverse dall'inglese richiedono il piano GROWTH: in caso di rifiuto si ripiega sull'inglese.
      if (lang === "en-us") throw err;
      lang = "en-us";
      exercises = await buildCatalog(lang);
    }

    const now = new Date();
    const expires = new Date(now.getTime() + CACHE_DAYS * 86_400_000);
    await admin.from("catalog_cache").upsert({
      language: lang,
      exercises,
      fetched_at: now.toISOString(),
      expires_at: expires.toISOString(),
    });
    return json(exercises, 200, { "Cache-Control": "private, max-age=3600" });
  } catch (err) {
    // Mai restituire un catalogo scaduto: l'app continua con l'elenco incluso.
    console.error(err);
    return json({ error: "catalog_unavailable" }, 503);
  }
});
