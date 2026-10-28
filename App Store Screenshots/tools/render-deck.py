"""Render the Loox App Store screenshot deck to upload-ready PNGs.

    python3 "App Store Screenshots/tools/render-deck.py" [--lang en,vi,ja] [--device iphone,ipad]

For every locale x device x frame this writes a standalone page (deck_layout.py),
screenshots it with headless Google Chrome at the exact App Store size
(iPhone 6.9" 1320x2868, iPad 13" 2064x2752), flattens it to RGB (App Store
rejects alpha) and saves export/<lang>/<device>-NN-<slug>.png, plus one
contact sheet per locale for review. Captures come from shots/<lang>/, falling
back to shots/en/ so a locale without its own captures still renders.
"""
import argparse
import concurrent.futures as futures
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw

import deck_layout as layout

DECK = pathlib.Path(__file__).resolve().parent.parent
SHOTS = DECK / "shots"
EXPORT = DECK / "export"
BACKGROUND = DECK / "assets" / "background-halo-source.png"
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

# Where the halo sits when the source art is cropped to each frame (0 top, 1 bottom).
BG_FOCUS = {"iphone": 0.5, "ipad": 0.62}


def cover(img, w, h, focus_y):
    """Scale to cover w x h, crop horizontally centred and vertically at focus_y."""
    k = max(w / img.width, h / img.height)
    scaled = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
    x = (scaled.width - w) // 2
    y = round((scaled.height - h) * focus_y)
    return scaled.crop((x, y, x + w, y + h))


def backgrounds(work):
    src = Image.open(BACKGROUND).convert("RGB")
    out = {}
    for kind, d in layout.DEVICES.items():
        path = work / f"bg-{kind}.png"
        cover(src, d["w"], d["h"], BG_FOCUS[kind]).save(path)
        out[kind] = path.as_uri()
    return out


def capture(shots, lang, kind, slug):
    for folder in (lang, "en"):
        path = shots / folder / f"{kind}-{slug}.png"
        if path.exists():
            return path.as_uri()
    return None


def chrome_shot(page, png, w, h, profile, attempts=3):
    """Headless Chrome screenshot; the throwaway profile is deleted right after
    (each one is tens of MB and this disk is often nearly full)."""
    for attempt in range(1, attempts + 1):
        try:
            run = subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--disable-gpu",
                                  "--no-first-run", "--no-default-browser-check", f"--user-data-dir={profile}",
                                  "--force-device-scale-factor=1", f"--window-size={w},{h}",
                                  "--virtual-time-budget=4000", f"--screenshot={png}", page.as_uri()],
                                 capture_output=True, text=True, timeout=120)
        finally:
            shutil.rmtree(profile, ignore_errors=True)
        if run.returncode == 0 and png.exists():
            return
        if attempt == attempts:
            raise RuntimeError(f"Chrome failed on {page.name} (exit {run.returncode}): {run.stderr[-600:]}")


def render_one(job):
    page, raw, final, w, h, profile = job
    chrome_shot(page, raw, w, h, profile)
    img = Image.open(raw)
    if img.size != (w, h):
        raise RuntimeError(f"{final.name}: Chrome gave {img.size}, expected {(w, h)}")
    img.convert("RGB").save(final, optimize=True)        # no alpha channel
    return final


def contact_sheet(lang, files):
    """One review image per locale: the iPhone row above the iPad row."""
    rows = [[f for f in files if f.name.startswith(k)] for k in ("iphone", "ipad")]
    rows = [row for row in rows if row]
    th = 640

    def thumb(f):
        img = Image.open(f).convert("RGB")
        return img.resize((round(th * img.width / img.height), th), Image.LANCZOS)

    tiles = [[thumb(f) for f in row] for row in rows]
    gap, label = 24, 40
    width = max(sum(t.width for t in row) + gap * (len(row) + 1) for row in tiles)
    sheet = Image.new("RGB", (width, (th + gap + label) * len(rows) + gap), "#0B0B0F")
    draw = ImageDraw.Draw(sheet)
    y = gap
    for row_files, row in zip(rows, tiles):
        x = gap
        for f, t in zip(row_files, row):
            sheet.paste(t, (x, y))
            draw.text((x, y + th + 8), f.stem, fill="#9AA3B5")
            x += t.width + gap
        y += th + gap + label
    out = EXPORT / f"contact-sheet-{lang}.jpg"
    sheet.save(out, quality=88)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", default=None, help="comma list, default: every locale in loox-strings.json")
    ap.add_argument("--device", default="iphone,ipad")
    ap.add_argument("--shots", type=pathlib.Path, default=SHOTS, help="captures root (<lang>/<device>-<slug>.png)")
    args = ap.parse_args()

    strings = json.loads((DECK / "loox-strings.json").read_text())
    langs = args.lang.split(",") if args.lang else strings["order"]
    kinds = args.device.split(",")

    with tempfile.TemporaryDirectory(prefix="loox-deck-") as tmp:
        work = pathlib.Path(tmp)
        bg = backgrounds(work)
        jobs, per_lang = [], {lang: [] for lang in langs}
        for lang in langs:
            loc = strings[lang]
            (EXPORT / lang).mkdir(parents=True, exist_ok=True)
            for kind in kinds:
                d = layout.DEVICES[kind]
                for i, (slug, shot) in enumerate(layout.FRAMES, 1):
                    name = f"{kind}-{i:02d}-{slug}"
                    page = work / f"{lang}-{name}.html"
                    page.write_text(layout.frame_html(kind, slug, loc["frames"][slug], loc["type"], lang,
                                                      loc["features"], capture(args.shots, lang, kind, shot), bg[kind]))
                    final = EXPORT / lang / f"{name}.png"
                    jobs.append((page, work / f"{lang}-{name}.raw.png", final, d["w"], d["h"],
                                 work / f"profile-{lang}-{name}"))
                    per_lang[lang].append(final)
                    if not capture(args.shots, lang, kind, shot):
                        print(f"  capture pending: shots/{lang}/{kind}-{shot}.png")
        # One throwaway Chrome profile per page, so parallel runs never share a lock.
        with futures.ThreadPoolExecutor(max_workers=4) as pool:
            for done in pool.map(render_one, jobs):
                print("wrote", done.relative_to(DECK))
    for lang in langs:
        print("sheet", contact_sheet(lang, per_lang[lang]).relative_to(DECK))


if __name__ == "__main__":
    main()
