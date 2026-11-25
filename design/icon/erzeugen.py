#!/usr/bin/env python3
"""Erzeugt die vier Icon-Entwürfe (SVG-Ebenen + icon.json), rendert sie mit Apples `ictool` und baut die Tafeln.

Aufruf: python3 -I design/icon/erzeugen.py   (braucht Xcode; kein Simulator)
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
RENDERS = {"hell": "Default", "dunkel": "Dark", "getoent-hell": "TintedLight", "getoent-dunkel": "TintedDark",
           "klar-hell": "ClearLight"}
SMALL = [180, 120, 87, 60, 40]

def zacken(von, bis, rand, spitze, n):
    """Gezackte Siegelkante von x=von nach x=bis."""
    schritt = (bis - von) / n
    return "".join(f"L{von + schritt * (i + .5):.1f} {spitze}L{von + schritt * (i + 1):.1f} {rand}" for i in range(n))


# Gel-Beutel, 200×460, Ursprung oben Mitte: gezackte Abreißkante, kurzer Hals, Körper, gezackte Siegelnaht.
GEL = ("M-62 14" + zacken(-62, 62, 14, 0, 6) + "V58C62 98 100 100 100 148V446"
       + zacken(100, -100, 446, 460, 9) + "V148C-100 100-62 98-62 58Z")
DROP = "M0-62C20-34 44-8 44 18A44 44 0 1 1-44 18C-44-8-20-34 0-62Z"


def svg(*shapes):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n  '
            + "\n  ".join(shapes) + "\n</svg>\n")


def path(d, fill, transform=""):
    t = f' transform="{transform}"' if transform else ""
    return f'<path d="{d}" fill="{fill}"{t}/>'


def rect(x, y, w, h, r, fill, transform=""):
    t = f' transform="{transform}"' if transform else ""
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"{t}/>'


def gel(cx, top, scale, angle, body, label, mark):
    """Ein Gel: Körper, Abreißlinie, Etikett mit Tropfen, Siegellinie."""
    t = f"translate({cx} {top}) rotate({angle}) scale({scale})"
    return [path(GEL, body, t), rect(-62, 38, 124, 11, 0, label, t), rect(-100, 190, 200, 164, 0, label, t),
            rect(-100, 408, 200, 11, 0, label, t), path(DROP, mark, f"{t} translate(0 278)")]


# Jeder Entwurf: Ebenen von vorn nach hinten, Verlauf hell, Verlauf dunkel, Grautöne für „getönt“.
def beutel():
    """A: Papiertüte mit gezacktem Rand, zwei Gels schauen heraus (Linos Idee)."""
    hinten = svg(*gel(386, 118, 1.04, -12, "#2D63D8", "#FFFFFF", "#2D63D8"),
                 *gel(640, 138, 1.04, 13, "#0FA38C", "#FFFFFF", "#0FA38C"))
    tuete = svg(path("M258 482" + zacken(258, 766, 482, 452, 8) + "L806 820Q814 896 736 896H288Q210 896 218 820Z",
                     "#FFF6EA"), rect(250, 530, 524, 22, 0, "#E8C9A4"))
    zeichen = svg(path(DROP, "#E4580B", "translate(512 738) scale(1.75)"))
    grau = {"#2D63D8": "#A0A0A0", "#0FA38C": "#848484", "#E4580B": "#4A4A4A", "#E8C9A4": "#9A9A9A"}
    return ([("zeichen", zeichen), ("tuete", tuete), ("gele", hinten)], ("#FF9E33", "#E4580B"),
            ("#3A1D0A", "#140A04"), grau)


def musette():
    """B: Musette (Verpflegungsbeutel im Rennen), hängt schräg am langen Gurt."""
    gurt = svg(path("M298 610L612-40H668L362 610Z", "#E9DCC3"), path("M718 610L650-40H708L774 610Z", "#CDBB9A"))
    gele = svg(*gel(398, 286, 0.88, -22, "#FF7A1A", "#FFFFFF", "#FF7A1A"),
               *gel(668, 250, 0.88, 8, "#E5385F", "#FFFFFF", "#E5385F"),
               *gel(530, 220, 0.94, -7, "#FFC21F", "#FFFFFF", "#D98E00"))
    t = "rotate(-6 512 700)"
    tasche = svg(path("M232 512H792L768 876Q764 922 716 922H308Q260 922 256 876Z", "#FBF4E6", t),
                 rect(240, 616, 544, 96, 0, "#FF7A1A", t), rect(248, 740, 528, 30, 0, "#0E4C66", t))
    grau = {"#FF7A1A": "#8C8C8C", "#E5385F": "#9E9E9E", "#FFC21F": "#D0D0D0", "#D98E00": "#6A6A6A",
            "#0E4C66": "#4A4A4A", "#E9DCC3": "#B0B0B0", "#CDBB9A": "#808080"}
    return ([("tasche", tasche), ("gele", gele), ("gurt", gurt)], ("#2388A8", "#0C3E57"), ("#12303F", "#05121A"),
            grau)


def trikot():
    """C: Rückentaschen eines Trikots, drei Gels stecken bereit."""
    gele = svg(*gel(282, 226, 1.0, -6, "#FFC21F", "#FFFFFF", "#D98E00"),
               *gel(742, 226, 1.0, 6, "#22C3AA", "#FFFFFF", "#12907D"),
               *gel(512, 160, 1.04, 0, "#F7F8FA", "#FF6A13", "#FFFFFF"))
    taschen = svg(path("M-20 524Q172 576 342 540Q512 594 682 540Q852 576 1044 524V1044H-20Z", "#FF6A13"))
    naehte = svg(rect(332, 570, 20, 454, 10, "#C94A00"), rect(672, 570, 20, 454, 10, "#C94A00"),
                 rect(-20, 862, 1064, 34, 0, "#FFD7BC"))
    grau = {"#FFC21F": "#C4C4C4", "#D98E00": "#5A5A5A", "#22C3AA": "#A4A4A4", "#12907D": "#606060",
            "#F7F8FA": "#FFFFFF", "#FF6A13": "#787878", "#C94A00": "#4A4A4A", "#FFD7BC": "#E0E0E0"}
    return ([("naehte", naehte), ("taschen", taschen), ("gele", gele)], ("#2C3A5E", "#121A30"),
            ("#171D2E", "#05070E"), grau)


def einzelgel():
    """D: Ein einzelnes Gel, groß und schräg, mit Tropfen – am ruhigsten, klein am besten lesbar."""
    t = "translate(642 138) rotate(32) scale(1.62)"
    koerper = svg(path(GEL, "#EE5D0A", t), rect(-62, 38, 124, 12, 0, "#FFE3CC", t),
                  rect(-100, 408, 200, 12, 0, "#FFE3CC", t))
    etikett = svg(rect(-100, 186, 200, 184, 0, "#FFF8F0", t),
                  path(DROP, "#EE5D0A", f"{t} translate(0 285) scale(1.15)"))
    tropfen = svg(path(DROP, "#EE5D0A", "translate(784 232) rotate(32) scale(1.3)"))
    grau = {"#EE5D0A": "#848484", "#FFE3CC": "#FFFFFF", "#FFF8F0": "#FFFFFF"}
    return ([("etikett", etikett), ("koerper", koerper), ("tropfen", tropfen)], ("#FFF4E4", "#FFD3A1"),
            ("#2B211B", "#0F0B08"), grau)


DESIGNS = {"a-beutel": beutel, "b-musette": musette, "c-trikottasche": trikot, "d-einzelgel": einzelgel}


def color(hex_value):
    parts = [int(hex_value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return "srgb:" + ",".join(f"{p:.5f}" for p in parts) + ",1.00000"


def gradient(pair):
    return {"linear-gradient": [color(pair[0]), color(pair[1])],
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}}


def write(name, build):
    layers, light, dark, grau = build()
    icon = ROOT / name / "CarbStock.icon"
    (icon / "Assets").mkdir(parents=True, exist_ok=True)
    groups = []
    for layer, content in layers:  # erste Gruppe liegt vorn
        (icon / "Assets" / f"{layer}.svg").write_text(content)
        getoent = content
        for farbe, ton in grau.items():  # Platzhalter, damit keine Ersetzung eine andere trifft
            getoent = getoent.replace(f'"{farbe}"', f'"@{ton[1:]}"')
        getoent = getoent.replace('"@', '"#')
        image = {"image-name": f"{layer}.svg"}
        if getoent != content:  # eigene Graustufen, sonst verschwinden dunkle Flächen beim Tönen
            (icon / "Assets" / f"{layer}-getoent.svg").write_text(getoent)
            image = {"image-name-specializations": [{"value": f"{layer}.svg"},
                                                    {"appearance": "tinted", "value": f"{layer}-getoent.svg"}]}
        groups.append({"layers": [{**image, "name": layer, "glass": True}],
                       "shadow": {"kind": "neutral", "opacity": 0.5},
                       "translucency": {"enabled": False, "value": 0.5}})
    meta = {"fill-specializations": [{"value": gradient(light)}, {"appearance": "dark", "value": gradient(dark)}],
            "groups": groups, "supported-platforms": {"squares": ["iOS"]}}
    (icon / "icon.json").write_text(json.dumps(meta, indent=2) + "\n")
    return icon


def render(icon, out, rendition, size):
    out.parent.mkdir(parents=True, exist_ok=True)
    args = [ICTOOL, str(icon), "--export-image", "--output-file", str(out), "--platform", "iOS",
            "--rendition", rendition, "--width", str(size), "--height", str(size), "--scale", "1"]
    if rendition.startswith("Tinted"):
        args += ["--tint-color", "0.58", "--tint-strength", "0.6"]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not out.exists():
        raise SystemExit(f"ictool {out.name}: {result.stdout}{result.stderr}")


def main():
    for name, build in DESIGNS.items():
        icon = write(name, build)
        for label, rendition in RENDERS.items():
            render(icon, ROOT / name / "render" / f"{label}.png", rendition, 1024)
        for size in SMALL:
            for label in ["hell", "dunkel", "getoent-dunkel"]:
                render(icon, ROOT / name / "klein" / f"{label}-{size}.png", RENDERS[label], size)
        print("gerendert:", name)


if __name__ == "__main__":
    main()
