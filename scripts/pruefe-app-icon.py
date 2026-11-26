#!/usr/bin/env python3
"""Prüft, dass die gebaute App das abgenommene Icon trägt (design/icon/c-trikottasche).

Aufruf nach einem Build:  scripts/pruefe-app-icon.py <Pfad zur CarbStock.app>
Prüft Quelle (App/Resources/AppIcon.icon = abgenommener Entwurf, kein Platzhalter daneben) und Ergebnis (Info.plist nennt
AppIcon, der kompilierte Katalog enthält die Ebenen auch in den getönten Varianten). Exit 0 = alles erfüllt.
"""
import json
import plistlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUELLE = ROOT / "App/Resources/AppIcon.icon"
ENTWURF = ROOT / "design/icon/c-trikottasche/CarbStock.icon"
PLATZHALTER = ROOT / "App/Resources/Assets.xcassets/AppIcon.appiconset"
EBENEN = ["gele", "taschen", "naehte"]


def dateien(ordner):
    return {str(p.relative_to(ordner)): p.read_bytes() for p in sorted(ordner.rglob("*"))
            if p.is_file() and p.name != ".DS_Store"}


def main(app):
    befunde = []
    if not QUELLE.is_dir() or dateien(QUELLE) != dateien(ENTWURF):
        befunde.append("App/Resources/AppIcon.icon fehlt oder weicht vom abgenommenen Entwurf ab")
    if PLATZHALTER.exists():
        befunde.append("Platzhalter AppIcon.appiconset ist noch da")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    name = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {}).get("CFBundleIconName")
    if name != "AppIcon":
        befunde.append(f"Info.plist: CFBundleIconName ist {name!r}")
    katalog = json.loads(subprocess.run(["xcrun", "assetutil", "--info", str(app / "Assets.car")],
                                        check=True, capture_output=True, text=True).stdout)
    namen = [str(e.get(key, "")) for e in katalog for key in ("Name", "RenditionName")]
    for ebene in EBENEN:
        for variante in (ebene, f"{ebene}-getoent"):
            if not any(variante in n for n in namen):
                befunde.append(f"Katalog enthält die Ebene {variante} nicht")
    for befund in befunde:
        print("FEHLT:", befund)
    print(f"{len(befunde)} Befund(e).")
    return 1 if befunde else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(Path(sys.argv[1])))
