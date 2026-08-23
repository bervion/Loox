"""Generate 'Loox App Store Screenshots v4.dc.html' from one source of truth.

Every frame is the same three-part composition (headline / stage / caption), so
the deck is emitted rather than hand-maintained: 8 iPhone frames + 8 iPad frames
stay in lockstep, and re-running this after dropping in new screenshots is a
one-liner.
"""
import pathlib
import re

HERE = pathlib.Path(__file__).parent
DECK = pathlib.Path("/Users/pham.nhu.chinh/Developer/Personal/Vaultify/App Store Screenshots")
ICONS = pathlib.Path(
    "/Users/pham.nhu.chinh/Developer/Personal/Vaultify/Vaultify/Assets.xcassets/PolarisIcons"
)

INK = "#0F0F0F"
MUTED = "rgba(15,15,15,0.55)"
SANS = ('-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", '
        '"Helvetica Neue", "Hiragino Sans", sans-serif')
MONO = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace'

# ── frames ────────────────────────────────────────────────────────────────────
# slug, copy key, capture note (shown while the slot is empty), asset key stem
FRAMES = [
    ("private", "hPrivate", None, None),
    ("autofill", "hAutofill", "AutoFill sheet in Safari", "Autofill"),
    ("vault", "hVault", "Space item list", "Vault"),
    ("codes", "hCodes", "2FA codes sheet", "Codes"),
    ("watchtower", "hWatchtower", "Watchtower score", "Watchtower"),
    ("share", "hShare", "Share access sheet", "Share"),
    ("generator", "hGenerator", "Password generator", "Generator"),
    ("features", "hAll", None, None),
]

# last frame — label key + the app's own Polaris glyph for that feature
FEATURES = [
    ("f1", "ic_enter"),
    ("f2", "ic_passkey"),
    ("f3", "ic_clock"),
    ("f4", "ic_shield_check_mark"),
    ("f5", "ic_shield_person"),
    ("f6", "ic_link"),
    ("f7", "ic_email"),
    ("f8", "ic_identity_card"),
]


def polaris(name, px):
    """Inline an app icon straight from the asset catalog, sized in frame px."""
    svg = (ICONS / f"{name}.imageset" / f"{name}.svg").read_text().strip()
    svg = svg.replace(
        "<svg ",
        f'<svg style="width:{px}px;height:{px}px;flex:none;display:block;fill:{INK}" ',
        1,
    )
    return re.sub(r'\s*xmlns="[^"]*"', "", svg, count=1).replace(
        "<svg ", '<svg xmlns="http://www.w3.org/2000/svg" ', 1
    )


LAUREL = (HERE / "laurel.svg").read_text().strip()

# Which captures made it into loox-assets.js — a frame with no capture yet keeps
# its hatched "drop screenshot" slot instead of pointing at an undefined key.
AVAILABLE = set(re.findall(r"^  (\w+):", (DECK / "loox-assets.js").read_text(), re.M))


def laurel(width):
    return LAUREL.replace(
        "<svg ",
        f'<svg style="width:{width}px;height:auto;display:block" ',
        1,
    )


# ── device stages ─────────────────────────────────────────────────────────────
# Screen slots carry the REAL App Store aspect (1320×2868 / 2064×2752), so a
# capture dropped in is never stretched: slot height = slot width ÷ device ratio.
PHONE_W, PHONE_PAD = 1020, 23                      # bezel 13 + black 10
PHONE_SCREEN_W = PHONE_W - PHONE_PAD * 2           # 974
PHONE_SCREEN_H = round(PHONE_SCREEN_W * 2868 / 1320)
PHONE_H = PHONE_SCREEN_H + PHONE_PAD * 2

PAD_W, PAD_PAD = 1500, 42                          # bezel 14 + black 28
PAD_SCREEN_W = PAD_W - PAD_PAD * 2                 # 1416
PAD_SCREEN_H = round(PAD_SCREEN_W * 2752 / 2064)
PAD_H = PAD_SCREEN_H + PAD_PAD * 2


def slot(caption, asset, font_size):
    """Screenshot if one has been captured, hatched capture note otherwise."""
    if asset:
        return (f'<img src="{{{{ a.{asset} }}}}" alt="" '
                'style="width:100%;height:100%;display:block;object-fit:cover" />')
    return ('<div style="position:relative;width:100%;height:100%;border-radius:inherit;overflow:hidden;'
            'background:repeating-linear-gradient(135deg,#FFFFFF 0 16px,#F1F2F4 16px 32px);'
            'display:grid;place-items:center">'
            f'<div style="font-family:{MONO};font-size:{font_size}px;letter-spacing:0.14em;'
            'text-transform:uppercase;color:rgba(15,15,15,0.3);text-align:center;line-height:1.9">'
            f'{caption}<br />drop screenshot</div></div>')


def phone_stage(caption, asset=None):
    """iPhone bezel with a screenshot slot."""
    return f"""<div style="position:absolute;left:150px;top:960px;width:{PHONE_W}px;height:{PHONE_H}px">
            <div style="position:absolute;left:-9px;top:280px;width:9px;height:64px;border-radius:5px 0 0 5px;background:linear-gradient(90deg,#17181B,#43474D)"></div>
            <div style="position:absolute;left:-9px;top:410px;width:9px;height:128px;border-radius:5px 0 0 5px;background:linear-gradient(90deg,#17181B,#43474D)"></div>
            <div style="position:absolute;left:-9px;top:572px;width:9px;height:128px;border-radius:5px 0 0 5px;background:linear-gradient(90deg,#17181B,#43474D)"></div>
            <div style="position:absolute;right:-9px;top:464px;width:9px;height:196px;border-radius:0 5px 5px 0;background:linear-gradient(270deg,#17181B,#43474D)"></div>
            <div style="width:100%;height:100%;border-radius:131px;padding:13px;background:linear-gradient(150deg,#3A3D42 0%,#131417 26%,#4A4E55 52%,#141518 74%,#33363B 100%);box-shadow:0 60px 110px -50px rgba(15,15,15,0.5)">
              <div style="width:100%;height:100%;border-radius:118px;background:#000000;padding:10px">
                <div style="position:relative;width:100%;height:100%;border-radius:108px;overflow:hidden">
                  {slot(caption, asset, 32)}
                  <div style="position:absolute;top:28px;left:50%;transform:translateX(-50%);width:258px;height:74px;border-radius:37px;background:#000000"></div>
                </div>
              </div>
            </div>
          </div>"""


def pad_stage(caption, asset=None):
    """iPad bezel with a screenshot slot."""
    return f"""<div style="position:absolute;left:282px;top:1000px;width:{PAD_W}px;height:{PAD_H}px">
            <div style="position:absolute;left:300px;top:-11px;width:160px;height:11px;border-radius:6px 6px 0 0;background:linear-gradient(180deg,#43474D,#17181B)"></div>
            <div style="position:absolute;right:-9px;top:240px;width:9px;height:120px;border-radius:0 5px 5px 0;background:linear-gradient(270deg,#17181B,#43474D)"></div>
            <div style="position:absolute;right:-9px;top:400px;width:9px;height:120px;border-radius:0 5px 5px 0;background:linear-gradient(270deg,#17181B,#43474D)"></div>
            <div style="width:100%;height:100%;border-radius:82px;padding:14px;background:linear-gradient(150deg,#3A3D42 0%,#131417 26%,#4A4E55 52%,#141518 74%,#33363B 100%);box-shadow:0 60px 110px -50px rgba(15,15,15,0.5)">
              <div style="position:relative;width:100%;height:100%;border-radius:68px;background:#000000;padding:28px">
                <div style="position:relative;width:100%;height:100%;border-radius:42px;overflow:hidden">
                  {slot(caption, asset, 36)}
                </div>
                <div style="position:absolute;left:50%;top:13px;transform:translateX(-50%);width:14px;height:14px;border-radius:50%;background:#1B1D21"></div>
              </div>
            </div>
          </div>"""


# ── frame bodies ──────────────────────────────────────────────────────────────
def hero_body(kind):
    """Frame 01 — headline, illustration, promise line, laurel seal."""
    if kind == "ios":
        return f"""<img src="{{{{ a.heroPrivacy }}}}" alt="" style="position:absolute;left:50%;top:1010px;transform:translateX(-50%);width:1090px;height:818px;display:block" />
          <div style="position:absolute;left:110px;right:110px;top:2092px;font-size:46px;line-height:1.45;font-weight:400;color:{MUTED};text-align:center;white-space:pre-line;text-wrap:pretty">{{{{ t.foot }}}}</div>
          <div style="position:absolute;left:50%;top:2430px;transform:translateX(-50%)">{laurel(560)}</div>"""
    return f"""<img src="{{{{ a.heroPrivacy }}}}" alt="" style="position:absolute;left:50%;top:900px;transform:translateX(-50%);width:1300px;height:975px;display:block" />
          <div style="position:absolute;left:180px;right:180px;top:2080px;font-size:54px;line-height:1.45;font-weight:400;color:{MUTED};text-align:center;white-space:pre-line;text-wrap:pretty">{{{{ t.foot }}}}</div>
          <div style="position:absolute;left:50%;top:2350px;transform:translateX(-50%)">{laurel(620)}</div>"""


def features_body(kind):
    """Frame 08 — the app's own icons against their feature names."""
    if kind == "ios":
        top, gap, icon, size, pad = 1060, 76, 100, 100, 110
    else:
        top, gap, icon, size, pad = 1120, 96, 124, 118, 180
    rows = []
    for key, glyph in FEATURES:
        rows.append(
            f"""<div style="display:flex;align-items:center;gap:{'50' if kind == 'ios' else '62'}px">
                {polaris(glyph, icon)}
                <span style="font-size:{size}px;font-weight:600;letter-spacing:-0.03em;color:{INK};line-height:1.15">{{{{ t.{key} }}}}</span>
              </div>"""
        )
    return (f'<div style="position:absolute;left:{pad}px;right:{pad}px;top:{top}px;'
            f'display:grid;gap:{gap}px">\n              ' + "\n              ".join(rows) + "\n          </div>")


def frame(kind, index, slug, key, caption, asset_stem):
    w, h, scale = (1320, 2868, 0.25) if kind == "ios" else (2064, 2752, 0.16)
    tile_w, tile_h = (330, 717) if kind == "ios" else (331, 441)
    pad, top = (110, 170) if kind == "ios" else (180, 190)
    size_var = "tPhone" if kind == "ios" else "tPad"
    device = "iphone" if kind == "ios" else "ipad"
    num = f"{index:02d}"
    asset = None
    if asset_stem:
        candidate = ("shot" if kind == "ios" else "pad") + asset_stem
        asset = candidate if candidate in AVAILABLE else None

    if slug == "private":
        body = hero_body(kind)
    elif slug == "features":
        body = features_body(kind)
    else:
        body = (phone_stage if kind == "ios" else pad_stage)(f"{num} · {caption}", asset)

    return f"""      <div style="display:grid;gap:10px;justify-items:stretch">
        <div style="position:relative;width:{tile_w}px;height:{tile_h}px;overflow:hidden;border-radius:16px;box-shadow:0 18px 40px -26px rgba(15,15,15,0.45), inset 0 0 0 1px rgba(15,15,15,0.08)">
          <div data-frame="{kind}-{index}" data-w="{w}" data-h="{h}" style="position:absolute;top:0;left:0;width:{w}px;height:{h}px;transform:scale({scale});transform-origin:top left;background:#FFFFFF;overflow:hidden">
            <div style="position:absolute;left:{pad}px;right:{pad}px;top:{top}px;font-size:{{{{ t.{size_var} }}}};line-height:{{{{ t.lh }}}};font-weight:700;color:{INK};white-space:pre-line;letter-spacing:{{{{ t.track }}}}">{{{{ t.{key} }}}}</div>
          {body}
          </div>
        </div>
        <div style="display:flex;align-items:center;justify-content:space-between;gap:8px">
          <span style="font-family:{MONO};font-size:10.5px;letter-spacing:0.08em;text-transform:uppercase;color:#6B6F76">{num} · {slug}</span>
          <button data-export="{kind}-{index}" data-name="loox-{device}-{num}-{slug}" style="padding:6px 12px;border-radius:8px;background:#FFFFFF;color:{INK};font-size:11px;font-weight:600;letter-spacing:0.02em;box-shadow:inset 0 0 0 1px #CFD2D8">PNG</button>
        </div>
      </div>"""


def row(kind):
    return "\n\n".join(
        frame(kind, i + 1, slug, key, caption, stem)
        for i, (slug, key, caption, stem) in enumerate(FRAMES)
    )


DC_SCRIPT = (HERE / "dc-script.js").read_text().rstrip()

html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<script src="https://unpkg.com/html-to-image@1.11.11/dist/html-to-image.js"></script>
<script src="loox-strings.js"></script>
<script src="loox-assets.js"></script>
<style>
  body {{ margin:0; background:#F1F2F4; font-family:{SANS}; -webkit-font-smoothing:antialiased; }}
  /* Frames carry the family explicitly: the PNG export clones a frame on its
     own, so it must not depend on inheriting anything from <body>. */
  [data-frame] {{ font-family:{SANS}; }}
  a {{ color:{INK}; text-decoration:underline; }}
  a:hover {{ color:#5A5A5A; }}
  button {{ font-family:inherit; cursor:pointer; border:0; }}
</style>
</helmet>

<div style="min-height:100vh;padding:36px 40px 80px;display:grid;gap:44px;align-content:start">

  <div style="display:flex;align-items:flex-end;justify-content:space-between;gap:24px;flex-wrap:wrap;border-bottom:1px solid #DEE0E4;padding-bottom:22px">
    <div style="display:grid;gap:8px">
      <div style="font-size:24px;font-weight:600;letter-spacing:-0.02em;color:{INK}">Loox App Store screenshots v4</div>
      <div style="font-family:{MONO};font-size:11.5px;letter-spacing:0.04em;color:#6B6F76">Copy lives in loox-strings.js · art in loox-assets.js · SF Pro throughout</div>
    </div>
    <div style="display:flex;align-items:center;gap:10px">
      <div data-langbar="" style="display:flex;gap:4px;padding:4px;border-radius:11px;background:#E3E5E9"></div>
      <button data-exportall="ios" style="padding:10px 18px;border-radius:10px;background:{INK};color:#FFFFFF;font-size:12.5px;font-weight:600;letter-spacing:0.01em">Export iPhone ↓</button>
      <button data-exportall="ipad" style="padding:10px 18px;border-radius:10px;background:#FFFFFF;color:{INK};font-size:12.5px;font-weight:600;letter-spacing:0.01em;box-shadow:inset 0 0 0 1px #CFD2D8">Export iPad ↓</button>
    </div>
  </div>

  <div style="display:grid;gap:18px">
    <div style="font-family:{MONO};font-size:11px;letter-spacing:0.12em;text-transform:uppercase;color:#8B9099">iPhone 6.9″ · 1320 × 2868</div>
    <div data-iosrow="" style="display:flex;flex-wrap:wrap;gap:24px">
{row('ios')}
    </div>
  </div>

  <div style="display:grid;gap:18px">
    <div style="font-family:{MONO};font-size:11px;letter-spacing:0.12em;text-transform:uppercase;color:#8B9099">iPad 13″ · 2064 × 2752</div>
    <div data-ipadrow="" style="display:flex;flex-wrap:wrap;gap:24px">
{row('ipad')}
    </div>
  </div>

</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props="{{&quot;$preview&quot;:{{&quot;width&quot;:1440,&quot;height&quot;:1000}}}}">
{DC_SCRIPT}
</script>
</body>
</html>
"""

target = DECK / "Loox App Store Screenshots v4.dc.html"
target.write_text(html)
print(f"wrote {target.name}: {len(html):,} bytes")
