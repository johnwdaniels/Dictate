"""Writes the six Dictator app icons as Icon Composer documents next to this script.

Run `python3 design/app-icons/build_icons.py`, then copy Dictator-G2-Poster.icon to Dictate/AppIcon.icon and re-export the
picker images in Dictate/Assets.xcassets/AppIcons with Icon Composer's ictool (macOS platform, Default and Dark, 512 px).
"""
import json, math, pathlib

OUT = pathlib.Path(__file__).resolve().parent

# Inworld tokens
BG, BG2, INK, INK2, INK3 = "#0f100e", "#151613", "#eeeae0", "#b4afa3", "#89857c"
CREAM, LINK = "#f3efe6", "#151613"
STT, STT_L, FAST, FAST_L, ROLE = "#a6c193", "#4f6e3a", "#f0b24a", "#8f5908", "#d7805a"
OLIVE, OLIVE_D, RED = "#4b573a", "#3c4630", "#c8102e"


def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{body}</svg>'


def c(hex_):
    r, g, b = (int(hex_[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def star(cx, cy, r, fill):
    pts = " ".join(f"{cx + (r if i % 2 == 0 else r * .42) * math.cos(math.radians(-90 + i * 36)):.1f},"
                   f"{cy + (r if i % 2 == 0 else r * .42) * math.sin(math.radians(-90 + i * 36)):.1f}" for i in range(10))
    return f'<polygon points="{pts}" fill="{fill}"/>'


def layer(name, glass=True, dark=None, tinted=None):
    d = {"glass": glass, "hidden": False, "image-name": f"{name}.svg", "name": name,
         "position": {"scale": 1, "translation-in-points": [0, 0]}}
    if dark:
        d["fill-specializations"] = [{"appearance": "dark", "value": {"solid": c(dark)}}]
    if tinted:
        d.setdefault("fill-specializations", []).append({"appearance": "tinted", "value": {"solid": c(tinted)}})
    return d


def group(*ls, glass=True):
    g = {"layers": list(ls), "shadow": {"kind": "neutral" if glass else "none", "opacity": 0.5}}
    if glass:
        g["translucency"] = {"enabled": True, "value": 0.35}
    return g


def write_icon(name, fill, fill_dark, layers, groups):
    d = OUT / f"{name}.icon"
    (d / "Assets").mkdir(parents=True, exist_ok=True)
    for f in (d / "Assets").glob("*.svg"):
        f.unlink()
    for lname, body in layers.items():
        (d / "Assets" / f"{lname}.svg").write_text(svg(body))
    doc = {"fill": {"automatic-gradient": c(fill)},
           "fill-specializations": [{"appearance": "dark", "value": {"automatic-gradient": c(fill_dark)}}],
           "groups": groups,
           "supported-platforms": {"circles": ["watchOS"], "squares": "shared"}}
    (d / "icon.json").write_text(json.dumps(doc, indent=2))


# ---------- G2 Poster ----------
def g2(name, ground, ground_dark, ray, ray_op, ray_dark, line, line_dark):
    rays = "".join(
        f'<polygon points="512,560 {512 + 1000 * math.cos(math.radians(a - 7.5)):.0f},{560 + 1000 * math.sin(math.radians(a - 7.5)):.0f} '
        f'{512 + 1000 * math.cos(math.radians(a + 7.5)):.0f},{560 + 1000 * math.sin(math.radians(a + 7.5)):.0f}" fill="{ray}" fill-opacity="{ray_op}"/>'
        for a in range(0, 360, 30))
    head = (f'<rect x="362" y="330" width="300" height="430" rx="150" fill="{INK}"/>'
            + "".join(f'<line x1="400" y1="{y}" x2="624" y2="{y}" stroke="{INK3}" stroke-width="18" stroke-linecap="round"/>'
                      for y in (650, 700)))
    ep = "".join(
        f'<rect x="{x - 46}" y="572" width="92" height="34" rx="6" fill="{line}"/>'
        + "".join(f'<rect x="{x + dx - 8}" y="600" width="16" height="34" rx="8" fill="{line}"/>' for dx in (-28, 0, 28))
        for x in (288, 736))
    holder = (f'<path d="M332 600 v30 a180 180 0 0 0 360 0 v-30" fill="none" stroke="{line}" stroke-width="34" stroke-linecap="round"/>'
              f'<rect x="495" y="800" width="34" height="70" fill="{line}"/>'
              f'<rect x="412" y="858" width="200" height="38" rx="10" fill="{line}"/>' + ep)
    lens = "M388 448 h116 q14 0 12 16 q-8 64 -68 64 q-56 0 -70 -64 q-2 -16 10 -16 z"
    face = (f'<path d="{lens}" fill="{LINK}"/><path d="{lens}" fill="{LINK}" transform="translate(1024 0) scale(-1 1)"/>'
            f'<rect x="498" y="456" width="28" height="14" rx="7" fill="{LINK}"/>'
            f'<path d="M512 558 C468 524 392 532 366 594 C410 580 444 610 512 590 C580 610 614 580 658 594 C632 532 556 524 512 558 Z" fill="{LINK}"/>')
    rot = 'transform="rotate(-8 512 360)"'
    cap = (f'<g {rot}><path d="M296 262 C300 300 350 338 380 352 L644 352 C674 338 724 300 728 262 Z" fill="{OLIVE_D}"/>'
           f'<ellipse cx="512" cy="262" rx="216" ry="74" fill="{OLIVE}"/>'
           f'<rect x="370" y="340" width="284" height="56" rx="4" fill="{LINK}"/>'
           f'<rect x="370" y="356" width="284" height="14" fill="{RED}"/>'
           f'<path d="M352 390 Q512 478 672 390 Q512 430 352 390 Z" fill="{LINK}"/></g>')
    badge = f'<g {rot}><circle cx="512" cy="290" r="50" fill="{INK}"/>{star(512, 293, 36, RED)}</g>'
    write_icon(name, ground, ground_dark,
               {"rays": rays, "head": head, "holder": holder, "face": face, "cap": cap, "badge": badge},
               [group(layer("badge"), layer("cap")), group(layer("face")),
                group(layer("head"), layer("holder", dark=line_dark, tinted="#d8d2c4")),
                group(layer("rays", glass=False, dark=ray_dark), glass=False)])


g2("Dictator-G2-Light", CREAM, "#2a2116", FAST, .75, "#4a3420", LINK, "#d8d2c4")
g2("Dictator-G2-Poster", FAST, "#2a2116", ROLE, .55, "#4a3420", LINK, "#d8d2c4")
g2("Dictator-G2-Dark", BG2, BG2, FAST, .22, "#4a3420", "#d8d2c4", "#d8d2c4")


# ---------- L2 Laurel ----------
def laurel_branch(cx, cy, R, start, end, side, color):
    out = []
    a0, a1 = math.radians(start), math.radians(end)
    x0, y0 = cx + R * math.cos(a0), cy + R * math.sin(a0)
    x1, y1 = cx + R * math.cos(a1), cy + R * math.sin(a1)
    out.append(f'<path d="M{x0:.1f} {y0:.1f} A{R} {R} 0 0 {1 if side < 0 else 0} {x1:.1f} {y1:.1f}" '
               f'fill="none" stroke="{color}" stroke-width="16" stroke-linecap="round"/>')
    n = 8
    for i in range(n):
        t = (i + 0.5) / n
        th = a0 + (a1 - a0) * t
        px, py = cx + R * math.cos(th), cy + R * math.sin(th)
        tx, ty = (-math.sin(th), math.cos(th)) if side < 0 else (math.sin(th), -math.cos(th))
        tang = math.degrees(math.atan2(ty, tx))
        nx, ny = math.cos(th), math.sin(th)
        size = 1.0 - 0.3 * t
        for k in (1, -1):
            lx = px + nx * 32 * k * size + tx * 18
            ly = py + ny * 32 * k * size + ty * 18
            rot = tang + (-34 if k == 1 else 34) * (-side)
            out.append(f'<ellipse cx="{lx:.1f}" cy="{ly:.1f}" rx="{52 * size:.1f}" ry="{21 * size:.1f}" '
                       f'transform="rotate({rot:.1f} {lx:.1f} {ly:.1f})" fill="{color}"/>')
    return "".join(out)


def l2(name, ground, ground_dark, leaf, leaf_dark, mic, mic_dark, grille, star_c, star_dark):
    R = 318
    laurel = (laurel_branch(512, 520, R, 102, 248, -1, leaf) + laurel_branch(512, 520, R, 78, -68, 1, leaf)
              + f'<rect x="488" y="{520 + R - 6}" width="48" height="26" rx="6" fill="{leaf}"/>')
    x, top, w, h = 512 - 87, 282, 174, 268
    hb, r = top + h - 70, 87 + 42
    mic_body = (f'<rect x="{x}" y="{top}" width="{w}" height="{h}" rx="{w / 2}" fill="{mic}"/>'
                f'<path d="M{512 - r} {hb} v18 a{r} {r} 0 0 0 {2 * r} 0 v-18" fill="none" stroke="{mic}" stroke-width="32" stroke-linecap="round"/>'
                f'<rect x="496" y="{hb + 18 + r}" width="32" height="64" fill="{mic}"/>'
                f'<rect x="420" y="{hb + 18 + r + 58}" width="184" height="34" rx="10" fill="{mic}"/>')
    grille_l = "".join(f'<rect x="{x + 30}" y="{y}" width="{w - 60}" height="18" rx="9" fill="{grille}"/>'
                       for y in range(top + 66, top + h - 60, 40))
    crest = star(512, 520 - R - 4, 50, star_c)
    write_icon(name, ground, ground_dark,
               {"crest": crest, "grille": grille_l, "mic": mic_body, "laurel": laurel},
               [group(layer("crest", dark=star_dark)),
                group(layer("grille"), layer("mic", dark=mic_dark, tinted=INK)),
                group(layer("laurel", dark=leaf_dark))])


l2("Dictator-L2-Light", CREAM, BG2, STT_L, STT, LINK, INK, CREAM, FAST_L, FAST)
l2("Dictator-L2-Olive", OLIVE, BG2, STT, STT, INK, INK, OLIVE, FAST, FAST)
l2("Dictator-L2-Dark", BG2, BG2, STT, STT, INK, INK, BG2, FAST, FAST)
