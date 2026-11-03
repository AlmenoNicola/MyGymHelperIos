#!/usr/bin/env python3
"""
Crea gli screenshot della scheda Google Play (1080×1920, verticali) dalle catture del telefono.

Catture di partenza (fatte sul telefono, senza ritocchi):
    android/store/raw/it/01.png ... 08.png   (telefono in italiano)
    android/store/raw/en/01.png ... 08.png   (telefono in inglese)
Risultato:
    android/store/screenshots/it/01.png ... e android/store/screenshots/en/01.png ...

Ogni immagine ha in alto una frase breve (CAPTIONS) e sotto la cattura in una cornice arrotondata, sullo sfondo
scuro dei colori dell'icona. Le catture mancanti vengono saltate.

Uso (dalla radice del progetto):  python tools/store_screenshots.py
Serve Pillow (pip install pillow).
"""
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "android" / "store" / "raw"
OUT = ROOT / "android" / "store" / "screenshots"

W, H = 1080, 1920
TOP_TEXT = 300            # spazio in alto per la frase
MARGIN_BOTTOM = 60
RADIUS = 56

# Una frase per cattura, nello stesso ordine della lista in docs/STORE_TEXTS_PLAY.md.
CAPTIONS = {
    "it": [
        ("Il telefono conta", "ogni ripetizione"),
        ("Pause guidate:", "ti dice cosa viene dopo"),
        ("Il tuo allenamento", "di oggi, a colpo d'occhio"),
        ("Scegli i muscoli", "da allenare"),
        ("Impara come si esegue", "ogni esercizio"),
        ("Schede pronte da 3 o 4", "allenamenti a settimana"),
        ("Consigli su pesi,", "serie e pause"),
        ("Free, Mid o Full:", "scegli il tuo piano"),
    ],
    "en": [
        ("Your phone counts", "every rep"),
        ("Guided rests that tell", "you what's next"),
        ("Today's workout", "at a glance"),
        ("Pick the muscles", "you want to train"),
        ("Learn how to perform", "every exercise"),
        ("Ready-made plans, 3 or 4", "workouts a week"),
        ("Suggestions on weights,", "sets and rest"),
        ("Free, Mid or Full:", "choose your plan"),
    ],
}

FONT_CANDIDATES = [
    "C:/Windows/Fonts/segoeuib.ttf",                       # Windows: Segoe UI Bold
    "/usr/share/fonts/truetype/lato/Lato-Bold.ttf",
    "/usr/share/fonts/truetype/lato/Lato-Black.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def font(size: int) -> ImageFont.FreeTypeFont:
    for f in FONT_CANDIDATES:
        if pathlib.Path(f).exists():
            return ImageFont.truetype(f, size)
    sys.exit("Nessun font trovato: aggiungi un percorso a FONT_CANDIDATES")


def background() -> Image.Image:
    """Sfondo scuro con un alone caldo, come l'icona."""
    bg = Image.new("RGB", (W, H), (18, 15, 36))
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(glow)
    d.ellipse((-300, -200, 900, 900), fill=(70, 30, 45))
    d.ellipse((500, 1100, 1500, 2200), fill=(45, 22, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    return Image.blend(bg, glow, 0.85)


def rounded(img: Image.Image, r: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), r, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def compose(shot: Image.Image, lines: tuple[str, str]) -> Image.Image:
    canvas = background().convert("RGBA")
    d = ImageDraw.Draw(canvas)

    # frase: prima riga bianca, seconda arancione
    f = font(64)
    y = 95
    for text, color in ((lines[0], (255, 255, 255)), (lines[1], (255, 165, 49))):
        w = d.textlength(text, font=f)
        d.text(((W - w) / 2, y), text, font=f, fill=color)
        y += 82

    # cattura ridimensionata nello spazio rimasto
    max_h = H - TOP_TEXT - MARGIN_BOTTOM
    max_w = W - 160
    scale = min(max_w / shot.width, max_h / shot.height)
    sw, sh = int(shot.width * scale), int(shot.height * scale)
    shot = rounded(shot.convert("RGB").resize((sw, sh), Image.LANCZOS), RADIUS)
    x = (W - sw) // 2
    top = TOP_TEXT

    # ombra e bordo sottile
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, top + 18, x + sw, top + sh + 18), RADIUS, fill=(0, 0, 0, 150))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(28)))
    canvas.alpha_composite(shot, (x, top))
    ImageDraw.Draw(canvas).rounded_rectangle((x, top, x + sw - 1, top + sh - 1), RADIUS, outline=(255, 255, 255, 40), width=3)
    return canvas.convert("RGB")


def main():
    made = 0
    for lang, captions in CAPTIONS.items():
        for i, lines in enumerate(captions, start=1):
            src = RAW / lang / f"{i:02d}.png"
            if not src.exists():
                continue
            dst = OUT / lang / f"{i:02d}.png"
            dst.parent.mkdir(parents=True, exist_ok=True)
            compose(Image.open(src), lines).save(dst, optimize=True)
            made += 1
            print(f"{dst.relative_to(ROOT)}")
    print(f"Screenshot creati: {made}" if made else f"Nessuna cattura trovata in {RAW}")


if __name__ == "__main__":
    main()
