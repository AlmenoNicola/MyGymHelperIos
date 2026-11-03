#!/usr/bin/env python3
"""
Genera i testi legali di MyGymHelper da un'unica fonte (cartella legal/ nella radice del progetto).

Uscite:
  - App/Legal/*.md                          testi dentro l'app iPhone   (blocchi <!--ios-->)
  - android/app/src/main/assets/legal/*.md  testi dentro l'app Android  (blocchi <!--android-->)
  - site/                                   sito statico per GitHub Pages (blocchi <!--web-->)

Nei modelli:
  - <!--android-->...<!--/android-->, <!--ios-->...<!--/ios-->, <!--web-->...<!--/web-->: testo solo per quella uscita;
  - {{TITOLARE}}, {{EMAIL}}, {{DATA}}, {{SITO}}: sostituiti con i valori qui sotto;
  - [nome dell'app]: nelle app lo sostituisce l'app stessa, nel sito diventa APP_NAME.

Uso (dalla radice del progetto):  python tools/build_legal.py
Dopo aver cambiato un testo legale, modificare SOLO i file in legal/ e rilanciare lo script.
"""
import html
import pathlib
import re
import sys

# ---------------------------------------------------------------- valori da compilare
APP_NAME = "MyGymHelper"
TITOLARE = "Nicola Gabriele Almeno"
INDIRIZZO = ""          # indirizzo del titolare (lo stesso di Play Console); vuoto = non mostrato
EMAIL = "mygymhelper@gmail.com"
SITO = "https://mygymhelper-site.github.io/"
DATA = {"it": "3 novembre 2026", "en": "3 November 2026"}

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "legal"
OUT_IOS = ROOT / "App" / "Legal"
OUT_ANDROID = ROOT / "android" / "app" / "src" / "main" / "assets" / "legal"
OUT_SITE = ROOT / "site"

PLATFORMS = ("android", "ios", "web")
DOCS = ("privacy", "disclaimer", "consent")
LANGS = ("it", "en")


def for_platform(text: str, platform: str, lang: str) -> str:
    """Tiene i blocchi della piattaforma, toglie gli altri e sostituisce i segnaposto."""
    for p in PLATFORMS:
        pattern = re.compile(rf"<!--{p}-->(.*?)<!--/{p}-->", re.S)
        text = pattern.sub((lambda m: m.group(1)) if p == platform else "", text)
    titolare = TITOLARE + (f", {INDIRIZZO}" if INDIRIZZO else "")
    text = (text.replace("{{TITOLARE}}", titolare).replace("{{EMAIL}}", EMAIL)
                .replace("{{DATA}}", DATA[lang]).replace("{{SITO}}", SITO))
    if platform == "web":
        text = text.replace("[nome dell'app]", APP_NAME)
    if "{{" in text or "<!--" in text:
        sys.exit(f"Segnaposto o blocco non chiuso in un testo ({platform}, {lang})")
    return text


# ---------------------------------------------------------------- Markdown semplice -> HTML
def inline(s: str) -> str:
    s = html.escape(s, quote=False)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(https://[^\s<]+[^\s<.,;:)])", r'<a href="\1">\1</a>', s)
    s = re.sub(r"(?<![\w/.])([\w.+-]+@[\w-]+\.[\w.]+[\w])", r'<a href="mailto:\1">\1</a>', s)
    return s


def md_to_html(md: str) -> str:
    out, in_list = [], False
    for line in md.splitlines():
        line = line.rstrip()
        if line.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(line[2:])}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if not line:
            continue
        if line.startswith("## "):
            out.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("# "):
            t = line[2:].strip()
            out.append(f"<h1>{inline(t.capitalize() if t.isupper() else t)}</h1>")
        else:
            out.append(f"<p>{inline(line)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


# ---------------------------------------------------------------- pagine del sito
PAGES = {  # chiave -> nome del file per lingua e voce del menu
    "privacy": {"it": ("privacy.html", "Privacy"), "en": ("privacy.html", "Privacy")},
    "disclaimer": {"it": ("disclaimer.html", "Avvertenze"), "en": ("disclaimer.html", "Disclaimer")},
    "delete": {"it": ("elimina-account.html", "Elimina account"), "en": ("delete-account.html", "Delete account")},
}

DELETE_PAGE = {
    "it": f"""# Eliminare l'account {APP_NAME}
L'account di {APP_NAME} è facoltativo: chi usa l'app senza accedere non ha dati sul nostro server.
## Dall'app (consigliato)
- Apri {APP_NAME} e vai in **Area personale > Account**.
- Tocca **Elimina account** e conferma.
Vengono cancellati subito l'account e i dati collegati sul server: profilo, elenchi di esercizi e stato della licenza. I dati salvati sul telefono (allenamenti, misure, impostazioni) restano finché non li elimini da **Area personale > Elimina tutti i dati locali** o finché non disinstalli l'app.
## Se non hai più l'app
Scrivi a {EMAIL} dall'indirizzo e-mail collegato al tuo account (quello dell'account Google o Apple con cui hai fatto l'accesso), con oggetto "Eliminazione account". Elimineremo l'account e i dati collegati entro 30 giorni e ti confermeremo l'avvenuta cancellazione.
## Abbonamenti
Eliminare l'account non annulla l'abbonamento, che è gestito dallo store:
- **Android**: Google Play Store > icona del profilo > Pagamenti e abbonamenti > Abbonamenti.
- **iPhone**: Impostazioni > [il tuo nome] > Abbonamenti.
## Dati che non conserviamo
Non conserviamo dati di pagamento né dati sulla salute: restano rispettivamente allo store e sul tuo telefono. Per maggiori dettagli leggi l'informativa sulla privacy: {SITO}it/privacy.html
""",
    "en": f"""# Deleting your {APP_NAME} account
A {APP_NAME} account is optional: if you use the app without signing in, we hold no data about you on our server.
## From the app (recommended)
- Open {APP_NAME} and go to **My area > Account**.
- Tap **Delete account** and confirm.
The account and the related server data are deleted immediately: profile, exercise lists and licence status. Data stored on your phone (workouts, measurements, settings) stays until you delete it from **My area > Delete all local data** or uninstall the app.
## If you no longer have the app
Write to {EMAIL} from the e-mail address linked to your account (the Google or Apple account you signed in with), with the subject "Account deletion". We will delete the account and the related data within 30 days and confirm the deletion to you.
## Subscriptions
Deleting the account does not cancel your subscription, which is managed by the store:
- **Android**: Google Play Store > profile icon > Payments & subscriptions > Subscriptions.
- **iPhone**: Settings > [your name] > Subscriptions.
## Data we do not keep
We keep neither payment data nor health data: they stay with the store and on your phone respectively. For more details read the privacy policy: {SITO}en/privacy.html
""",
}

HOME = {
    "it": f"""# {APP_NAME}
App per l'allenamento in palestra: conta le ripetizioni con i sensori del telefono, guida serie e pause e suggerisce come progredire.
{APP_NAME} non sostituisce il parere di medici, personal trainer o nutrizionisti: leggi le avvertenze prima dell'uso.
## Documenti
- Informativa sulla privacy: {SITO}it/privacy.html
- Avvertenze: {SITO}it/disclaimer.html
- Eliminazione dell'account: {SITO}it/elimina-account.html
## Contatti
Per domande, assistenza o richieste sulla privacy: {EMAIL}
""",
    "en": f"""# {APP_NAME}
A gym training app: it counts repetitions with the phone's sensors, guides sets and rests and suggests how to progress.
{APP_NAME} does not replace the advice of doctors, personal trainers or nutritionists: read the disclaimer before use.
## Documents
- Privacy policy: {SITO}en/privacy.html
- Disclaimer: {SITO}en/disclaimer.html
- Account deletion: {SITO}en/delete-account.html
## Contact
For questions, support or privacy requests: {EMAIL}
""",
}

CSS = """
:root{color-scheme:light dark;--fg:#1d1d1f;--muted:#6e6e73;--bg:#fff;--line:#e5e5ea;--accent:#2f6fde}
@media (prefers-color-scheme:dark){:root{--fg:#f5f5f7;--muted:#a1a1a6;--bg:#111113;--line:#2c2c2e;--accent:#6ea0ff}}
*{box-sizing:border-box}
body{margin:0;font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:var(--fg);background:var(--bg)}
header,main,footer{max-width:760px;margin:0 auto;padding:0 20px}
header{display:flex;flex-wrap:wrap;gap:6px 18px;align-items:center;padding-top:18px;padding-bottom:14px;border-bottom:1px solid var(--line)}
header .brand{font-weight:700;margin-right:auto;color:var(--fg);text-decoration:none}
header a{color:var(--muted);text-decoration:none;font-size:15px}
header a[aria-current]{color:var(--fg);font-weight:600}
main{padding-top:8px;padding-bottom:40px}
h1{font-size:28px;line-height:1.25;margin:28px 0 12px}
h2{font-size:19px;margin:28px 0 8px}
a{color:var(--accent);overflow-wrap:anywhere}
li{margin:4px 0}
footer{border-top:1px solid var(--line);padding-top:14px;padding-bottom:28px;color:var(--muted);font-size:14px}
"""

UI = {
    "it": {"other": ("en", "English"), "home": "index.html", "footer": "Contatti"},
    "en": {"other": ("it", "Italiano"), "home": "index.html", "footer": "Contact"},
}


def page(lang: str, key: str, title: str, body_md: str, other_file: str) -> str:
    ui = UI[lang]
    nav = []
    for k, per_lang in PAGES.items():
        fname, label = per_lang[lang]
        cur = ' aria-current="page"' if k == key else ""
        nav.append(f'<a href="{fname}"{cur}>{html.escape(label)}</a>')
    olang, olabel = ui["other"]
    nav.append(f'<a href="../{olang}/{other_file}" hreflang="{olang}">{olabel}</a>')
    return f"""<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} – {APP_NAME}</title>
<style>{CSS}</style>
</head>
<body>
<header><a class="brand" href="index.html">{APP_NAME}</a>{''.join(nav)}</header>
<main>
{md_to_html(body_md)}
</main>
<footer>{ui['footer']}: <a href="mailto:{EMAIL}">{EMAIL}</a> · {html.escape(TITOLARE)}</footer>
</body>
</html>
"""


def redirect(target: str) -> str:
    """Pagina nella radice che porta alla lingua del browser (italiano o inglese)."""
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{APP_NAME}</title>
<script>
var l=(navigator.language||"en").toLowerCase().indexOf("it")===0?"it":"en";
var p={{"it":"{target['it']}","en":"{target['en']}"}};
location.replace(l+"/"+p[l]);
</script>
</head><body>
<p><a href="it/{target['it']}">Italiano</a> · <a href="en/{target['en']}">English</a></p>
</body></html>
"""


def first_heading(md: str) -> str:
    m = re.search(r"^# (.+)$", md, re.M)
    return m.group(1).strip().capitalize() if m else APP_NAME


def main():
    # 1) testi dentro le app
    for out, platform in ((OUT_IOS, "ios"), (OUT_ANDROID, "android")):
        out.mkdir(parents=True, exist_ok=True)
        for doc in DOCS:
            for lang in LANGS:
                src = (SRC / f"{doc}.{lang}.md").read_text(encoding="utf-8")
                (out / f"{doc}.{lang}.md").write_text(for_platform(src, platform, lang), encoding="utf-8", newline="\n")

    # 2) sito
    for lang in LANGS:
        d = OUT_SITE / lang
        d.mkdir(parents=True, exist_ok=True)
        other = "en" if lang == "it" else "it"
        for key in ("privacy", "disclaimer"):
            md = for_platform((SRC / f"{key}.{lang}.md").read_text(encoding="utf-8"), "web", lang)
            fname = PAGES[key][lang][0]
            (d / fname).write_text(page(lang, key, first_heading(md), md, PAGES[key][other][0]), encoding="utf-8", newline="\n")
        (d / PAGES["delete"][lang][0]).write_text(
            page(lang, "delete", PAGES["delete"][lang][1], DELETE_PAGE[lang], PAGES["delete"][other][0]),
            encoding="utf-8", newline="\n")
        (d / "index.html").write_text(page(lang, "home", APP_NAME, HOME[lang], "index.html"), encoding="utf-8", newline="\n")

    # pagine nella radice: indirizzi brevi che scelgono la lingua del browser
    OUT_SITE.joinpath("index.html").write_text(redirect({"it": "index.html", "en": "index.html"}), encoding="utf-8", newline="\n")
    OUT_SITE.joinpath("privacy.html").write_text(redirect({"it": "privacy.html", "en": "privacy.html"}), encoding="utf-8", newline="\n")
    OUT_SITE.joinpath("delete-account.html").write_text(
        redirect({"it": "elimina-account.html", "en": "delete-account.html"}), encoding="utf-8", newline="\n")
    OUT_SITE.joinpath(".nojekyll").write_text("", encoding="utf-8")
    print("Testi legali generati: App/Legal, android assets/legal, site/")


if __name__ == "__main__":
    main()
