"""Pack the deck's artwork into loox-assets.js as data URIs.

Simulator screenshots are downscaled to the exact width they occupy inside the
device bezel and re-encoded as WebP, so the design file stays a few hundred KB
instead of tens of megabytes, and the html-to-image export never has to fetch
anything (a cross-origin fetch would taint the canvas and kill the PNG export).
"""
import base64
import pathlib
import subprocess

DECK = pathlib.Path("/Users/pham.nhu.chinh/Developer/Personal/Vaultify/App Store Screenshots")
SHOTS = DECK / "shots"
WORK = pathlib.Path("/tmp/loox-shot-work")
WORK.mkdir(exist_ok=True)

# Slot widths inside the bezels (see render-deck.py geometry).
IPHONE_SLOT = 974
IPAD_SLOT = 1416

# asset key -> (source file, slot width)
SHOTS_MAP = {
    "shotAutofill": ("iphone-autofill.png", IPHONE_SLOT),
    "shotVault": ("iphone-vault.png", IPHONE_SLOT),
    "shotCodes": ("iphone-codes.png", IPHONE_SLOT),
    "shotWatchtower": ("iphone-watchtower.png", IPHONE_SLOT),
    "shotShare": ("iphone-share.png", IPHONE_SLOT),
    "shotGenerator": ("iphone-generator.png", IPHONE_SLOT),
    "padAutofill": ("ipad-autofill.png", IPAD_SLOT),
    "padVault": ("ipad-vault.png", IPAD_SLOT),
    "padCodes": ("ipad-codes.png", IPAD_SLOT),
    "padWatchtower": ("ipad-watchtower.png", IPAD_SLOT),
    "padShare": ("ipad-share.png", IPAD_SLOT),
    "padGenerator": ("ipad-generator.png", IPAD_SLOT),
}


def data_uri(path, mime):
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode()


def encode_shot(src, width, out):
    subprocess.run(["sips", "--resampleWidth", str(width), str(src), "--out", str(out)],
                   check=True, capture_output=True)
    webp = out.with_suffix(".webp")
    subprocess.run(["cwebp", "-q", "84", "-m", "6", str(out), "-o", str(webp)],
                   check=True, capture_output=True)
    return webp


entries = {"heroPrivacy": data_uri(DECK / "assets/loox-hero-privacy.webp", "image/webp")}
missing = []
for key, (name, width) in SHOTS_MAP.items():
    src = SHOTS / name
    if not src.exists():
        missing.append(name)
        continue
    webp = encode_shot(src, width, WORK / name)
    entries[key] = data_uri(webp, "image/webp")
    print(f"{key:16} {name:24} {webp.stat().st_size / 1024:6.1f} KB")

body = ",\n".join(f'  {k}: "{v}"' for k, v in entries.items())
(DECK / "loox-assets.js").write_text(
    "/* Loox App Store screenshots — artwork inlined as data URIs.\n"
    "   Inlined (not linked) so the html-to-image PNG export never taints the\n"
    "   canvas and never depends on how this file is served.\n"
    "   Regenerate after dropping new captures into shots/ (see build-assets.py).  */\n\n"
    "window.LOOX_ASSETS = {\n" + body + "\n};\n"
)
size = (DECK / "loox-assets.js").stat().st_size
print(f"\nloox-assets.js {size / 1024:.0f} KB · {len(entries)} assets")
if missing:
    print("missing (frame keeps its placeholder):", ", ".join(missing))
