"""Frame geometry and markup for the Loox App Store screenshot deck (v5, dark).

Every frame is the same composition: eyebrow / headline / subline over the
halo background, then a device holding a REAL app capture that bleeds off the
bottom edge so the UI reads large in search results. render-deck.py feeds this
module the copy and the capture paths; nothing here touches the disk except
the Polaris icons.
"""
import html
import pathlib
import re

ICONS = (pathlib.Path(__file__).resolve().parents[2]
         / "Vaultify" / "Assets.xcassets" / "PolarisIcons")

SANS = ('-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", '
        '"Helvetica Neue", "Hiragino Sans", sans-serif')
BASE = "#050A2A"                                  # under the halo art
SUB = "rgba(226,234,255,0.80)"
EYEBROW = "#94D5FF"                                # Loox dot highlight
HIGHLIGHT = "linear-gradient(90deg,#7CC8FF 0%,#B69CFF 55%,#F59BD6 100%)"

# slug -> capture slug (shots/<locale>/<device>-<capture>.png)
FRAMES = [
    ("hero", "home"),
    ("autofill", "autofill"),
    ("codes", "detail"),
    ("private-email", "private-email"),
    ("share", "share-fields"),
    ("watchtower", "watchtower"),
    ("membership", "membership"),
    ("features", "vault"),
]

# Feature grid on the last frame: the app's own Polaris glyphs, in label order.
FEATURE_ICONS = ["ic_enter", "ic_passkey", "ic_clock", "ic_shield_check_mark",
                 "ic_email", "ic_link", "ic_shield_person", "ic_identity_card"]

# Device geometry, in frame px. The screen slot keeps the real capture aspect
# (1320x2868 / 2064x2752), so a capture is never stretched.
DEVICES = {
    "iphone": dict(
        w=1320, h=2868, pad_x=110, text_top=150,
        eyebrow=44, headline=124, sub=50,
        dev_w=1080, metal=14, black=12, screen_ratio=2868 / 1320,
        radius=(140, 126, 114), dev_top=740, dev_top_features=1420,
        island=(272, 78, 30), grid_cols=2,
    ),
    "ipad": dict(
        w=2064, h=2752, pad_x=200, text_top=150,
        eyebrow=50, headline=146, sub=58,
        dev_w=1640, metal=14, black=30, screen_ratio=2752 / 2064,
        radius=(92, 78, 50), dev_top=800, dev_top_features=1330,
        island=None, grid_cols=4,
    ),
}


def rich(text):
    """Escape copy, turn *word* into the gradient highlight and \\n into <br>."""
    out = html.escape(text)
    out = re.sub(r"\*(.+?)\*", r'<span class="hl">\1</span>', out)
    return out.replace("\n", "<br>")


def polaris(name, px, color="#FFFFFF"):
    """Inline an app icon straight from the asset catalog."""
    svg = (ICONS / f"{name}.imageset" / f"{name}.svg").read_text().strip()
    return svg.replace(
        "<svg ", f'<svg style="width:{px}px;height:{px}px;display:block;fill:{color}" ', 1)


def screen(capture_uri, d):
    """The capture, or a hatched slot naming the capture still missing."""
    if capture_uri:
        return (f'<img src="{capture_uri}" alt="" '
                'style="width:100%;height:100%;display:block;object-fit:cover">')
    return ('<div style="width:100%;height:100%;display:grid;place-items:center;'
            'background:repeating-linear-gradient(135deg,#1A2050 0 18px,#141A44 18px 36px);'
            f'color:rgba(255,255,255,0.45);font:600 {d["eyebrow"]}px/1.6 {SANS};'
            'letter-spacing:0.1em;text-transform:uppercase">capture pending</div>')


def device(kind, capture_uri, top):
    """A titanium-edged device holding the capture, positioned at `top`."""
    d = DEVICES[kind]
    inset = d["metal"] + d["black"]
    sw = d["dev_w"] - inset * 2
    sh = round(sw * d["screen_ratio"])
    dh = sh + inset * 2
    r_outer, r_black, r_screen = d["radius"]
    island = ""
    if d["island"]:
        iw, ih, it = d["island"]
        island = (f'<div style="position:absolute;top:{it}px;left:50%;transform:translateX(-50%);'
                  f'width:{iw}px;height:{ih}px;border-radius:{ih // 2}px;background:#000"></div>')
    buttons = ""
    if kind == "iphone":
        btn = ("position:absolute;width:10px;border-radius:{r};"
               "background:linear-gradient(90deg,#2A2E38,#7A808E,#2A2E38)")
        buttons = "".join(
            f'<div style="{btn.format(r=r)};{side}:-8px;top:{t}px;height:{h}px"></div>'
            for side, r, t, h in [("left", "5px 0 0 5px", 300, 70), ("left", "5px 0 0 5px", 430, 140),
                                  ("left", "5px 0 0 5px", 600, 140), ("right", "0 5px 5px 0", 480, 210)])
    return f"""<div style="position:absolute;left:50%;top:{top}px;transform:translateX(-50%);width:{d['dev_w']}px;height:{dh}px">
  <div style="position:absolute;inset:-60px;border-radius:{r_outer + 60}px;background:radial-gradient(closest-side,rgba(88,120,255,0.38),rgba(150,90,255,0.16) 60%,transparent);filter:blur(30px)"></div>
  {buttons}
  <div style="position:relative;width:100%;height:100%;border-radius:{r_outer}px;padding:{d['metal']}px;background:linear-gradient(150deg,#8A90A0 0%,#3A3F4B 18%,#9DA3B2 46%,#2C3039 72%,#7C8290 100%);box-shadow:0 90px 160px -50px rgba(0,0,0,0.75),inset 0 0 0 2px rgba(255,255,255,0.14)">
    <div style="width:100%;height:100%;border-radius:{r_black}px;background:#000;padding:{d['black']}px">
      <div style="position:relative;width:100%;height:100%;border-radius:{r_screen}px;overflow:hidden;background:#F2F3F7">
        {screen(capture_uri, d)}
        {island}
      </div>
    </div>
  </div>
</div>"""


def text_block(kind, copy, t):
    d = DEVICES[kind]
    size = round(d["headline"] * t["scale"])
    parts = []
    if copy.get("eyebrow"):
        parts.append(f'<div style="font-size:{d["eyebrow"]}px;font-weight:600;color:{EYEBROW};'
                     f'letter-spacing:0.01em;margin-bottom:{round(d["eyebrow"] * 0.55)}px">'
                     f'{rich(copy["eyebrow"])}</div>')
    parts.append(f'<div style="font-size:{size}px;font-weight:700;line-height:{t["lh"]};'
                 f'letter-spacing:{t["track"]};color:#FFFFFF">{rich(copy["h"])}</div>')
    if copy.get("sub"):
        parts.append(f'<div style="font-size:{d["sub"]}px;font-weight:500;line-height:1.34;color:{SUB};'
                     f'margin-top:{round(d["sub"] * 0.7)}px;text-wrap:balance">{rich(copy["sub"])}</div>')
    return (f'<div style="position:absolute;left:{d["pad_x"]}px;right:{d["pad_x"]}px;top:{d["text_top"]}px;'
            f'text-align:center">{"".join(parts)}</div>')


def feature_grid(kind, labels, t):
    """Last frame: the app's own glyphs against their feature names."""
    d = DEVICES[kind]
    assert len(labels) == len(FEATURE_ICONS), f"{len(labels)} feature labels for {len(FEATURE_ICONS)} icons"
    font = round(50 * t["scale"])                # CJK labels are one long word: shrink, never break
    if d["grid_cols"] == 2:
        tile, glyph, gap, top = 112, 60, "44px 40px", 640
        cell = "display:flex;align-items:center;gap:30px;text-align:left"
    else:
        tile, glyph, gap, top = 132, 72, "56px 40px", 620
        cell = "display:flex;flex-direction:column;align-items:center;gap:26px;text-align:center"
    cells = "".join(
        f'<div style="{cell}"><div style="flex:none;width:{tile}px;height:{tile}px;border-radius:{tile * 0.28:.0f}px;'
        'display:grid;place-items:center;background:linear-gradient(145deg,#2F7BFF,#7C3AED 70%,#C0389A);'
        f'box-shadow:inset 0 0 0 2px rgba(255,255,255,0.16)">{polaris(icon, glyph)}</div>'
        f'<span style="font-size:{font}px;font-weight:600;line-height:1.15;color:#FFFFFF">{html.escape(label)}</span></div>'
        for icon, label in zip(FEATURE_ICONS, labels))
    return (f'<div style="position:absolute;left:{d["pad_x"]}px;right:{d["pad_x"]}px;top:{top}px;'
            f'display:grid;grid-template-columns:repeat({d["grid_cols"]},1fr);gap:{gap}">{cells}</div>')


def frame_html(kind, slug, copy, t, lang, labels, capture_uri, bg_uri):
    """A full standalone page whose viewport IS the App Store frame."""
    d = DEVICES[kind]
    if slug == "features":
        body = feature_grid(kind, labels, t) + device(kind, capture_uri, d["dev_top_features"])
    else:
        body = device(kind, capture_uri, d["dev_top"])
    return f"""<!DOCTYPE html>
<html lang="{lang}"><head><meta charset="utf-8">
<style>
  *{{box-sizing:border-box}}
  html,body{{margin:0;width:{d['w']}px;height:{d['h']}px;overflow:hidden;background:{BASE}}}
  /* auto-phrase: Japanese wraps between phrases (BudouX), never inside a word. */
  body{{font-family:{SANS};-webkit-font-smoothing:antialiased;position:relative;word-break:auto-phrase;
        background:{BASE} url("{bg_uri}") center/cover no-repeat}}
  .hl{{background:{HIGHLIGHT};-webkit-background-clip:text;background-clip:text;color:transparent}}
</style></head>
<body>
{text_block(kind, copy, t)}
{body}
</body></html>"""
