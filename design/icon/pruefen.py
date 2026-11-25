#!/usr/bin/env python3
"""Prüft die Icon-Entwürfe gegen die Vorgaben der Karte und Apples Richtlinien (HIG „App icons“).

Aufruf: python3 -I design/icon/pruefen.py   (nach erzeugen.py und tafeln.swift; Exit 0 = alles erfüllt)
Geprüft je Entwurf: Icon-Composer-Paket mit vorhandenen SVG-Ebenen (quadratisch 1024, ohne Text, Rasterbilder, Filter
oder eigene Unschärfen), Renderings hell/dunkel/getönt in 1024 px, die sich unterscheiden, Kleingrößen und Tafel.
"""
import hashlib
import json
import math
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RENDERS = ["hell", "dunkel", "getoent-hell", "getoent-dunkel", "klar-hell"]
SMALL = [180, 120, 87, 60, 40]
RAND = 20  # Mindestabstand Gel–Naht in Punkten auf 1024
FORBIDDEN = ["<text", "<image", "<filter", "<mask", "<foreignObject", "blur("]


def png_size(path):
    head = path.read_bytes()[:24]
    return struct.unpack(">II", head[16:24]) if head[:8] == b"\x89PNG\r\n\x1a\n" else None


def image_names(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "image-name":
                yield value
            elif key == "image-name-specializations":
                yield from (v["value"] for v in value)
            else:
                yield from image_names(value)
    elif isinstance(node, list):
        for value in node:
            yield from image_names(value)


def check(design):
    problems = []
    meta = design / "CarbStock.icon" / "icon.json"
    if not meta.exists():
        return [f"{design.name}: CarbStock.icon/icon.json fehlt"]
    data = json.loads(meta.read_text())
    names = sorted(set(image_names(data)))
    if len(names) < 2:
        problems.append(f"{design.name}: weniger als 2 Vordergrund-Ebenen")
    for name in names:
        asset = design / "CarbStock.icon" / "Assets" / name
        if not asset.exists():
            problems.append(f"{design.name}: Ebene {name} fehlt")
            continue
        svg = asset.read_text()
        if not re.search(r'viewBox="0 0 1024 1024"', svg):
            problems.append(f"{design.name}/{name}: nicht 1024×1024")
        problems += [f"{design.name}/{name}: enthält {bad}" for bad in FORBIDDEN if bad in svg]
    digests = set()
    for render in RENDERS:
        png = design / "render" / f"{render}.png"
        if not png.exists() or png_size(png) != (1024, 1024):
            problems.append(f"{design.name}: render/{render}.png fehlt oder ist nicht 1024×1024")
        else:
            digests.add(hashlib.sha256(png.read_bytes()).hexdigest())
    if len(digests) < len(RENDERS):
        problems.append(f"{design.name}: Darstellungen sind nicht alle verschieden")
    for size in SMALL:
        for render in ["hell", "dunkel", "getoent-dunkel"]:
            png = design / "klein" / f"{render}-{size}.png"
            if not png.exists() or png_size(png) != (size, size):
                problems.append(f"{design.name}: klein/{render}-{size}.png fehlt")
    if not (design / "tafel.jpg").exists():
        problems.append(f"{design.name}: tafel.jpg fehlt")
    return problems


def taschen(design):
    """C: Jedes Gel sitzt in seiner eigenen Rückentasche und berührt keine Naht (Rückmeldung zum ersten Review)."""
    assets = design / "CarbStock.icon" / "Assets"
    naehte = sorted((float(x), float(x) + float(w)) for x, w, h in re.findall(
        r'<rect x="([-\d.]+)" y="[-\d.]+" width="([\d.]+)" height="([\d.]+)"', (assets / "naehte.svg").read_text())
        if float(h) > float(w))
    faecher = [(links[1], rechts[0]) for links, rechts in zip(naehte, naehte[1:])]
    if len(faecher) != 3:
        faecher = [(a, b) for a, b in zip([0] + [n[1] for n in naehte], [n[0] for n in naehte] + [1024])]
    belegt, problems = [], []
    for cx, angle, scale in re.findall(r'd="M-62 14[^"]*" fill="[^"]*" transform="translate\(([\d.]+) [\d.]+\) '
                                       r'rotate\(([-\d.]+)\) scale\(([\d.]+)\)"', (assets / "gele.svg").read_text()):
        a, s = math.radians(float(angle)), float(scale)
        xs = [float(cx) + s * (x * math.cos(a) - y * math.sin(a)) for x in (-100, 100) for y in (0, 460)]
        fach = [i for i, (von, bis) in enumerate(faecher) if von + RAND <= min(xs) and max(xs) <= bis - RAND]
        if not fach:
            problems.append(f"{design.name}: Gel bei x={cx} liegt auf oder zu nah an einer Naht ({min(xs):.0f}–{max(xs):.0f})")
        belegt += fach
    if sorted(belegt) != [0, 1, 2]:
        problems.append(f"{design.name}: nicht je ein Gel in drei Taschen (belegt: {sorted(belegt)})")
    return problems


def main():
    designs = sorted(p for p in ROOT.iterdir() if p.is_dir() and re.match(r"[a-d]-|[e-z]-", p.name))
    problems = [f"nur {len(designs)} Entwürfe (mindestens 4)"] if len(designs) < 4 else []
    for design in designs:
        problems += check(design)
        if design.name == "c-trikottasche":
            problems += taschen(design)
    if not (ROOT / "uebersicht.jpg").exists():
        problems.append("uebersicht.jpg fehlt")
    for problem in problems:
        print("FEHLT:", problem)
    print(f"{len(designs)} Entwürfe geprüft, {len(problems)} Befund(e).")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
