#!/usr/bin/env python3
"""Prüft das CloudKit-Schema gegen `cloudkit/schema.ckdb` (Gate G1, docs/G1-SCHEMA-REVIEW.md).

Nur lesend: `xcrun cktool export-schema`, kein Import, kein Deploy. Verglichen werden alle CD_-Satztypen mit jedem Feld
und Feldtyp (Indizes und Berechtigungen nicht: die sind auch in Production änderbar). Satztypen für Training oder
Imports sind ein Fehler. Dass die Datei zum SwiftData-Modell passt, prüft `AppTests/CloudKitSchemaFileTests`.

Nutzung:
  scripts/pruefe-cloudkit-schema.py                 # exportiert Development mit dem gespeicherten cktool-Token
  scripts/pruefe-cloudkit-schema.py --environment production
  scripts/pruefe-cloudkit-schema.py --file export.ckdb
  scripts/pruefe-cloudkit-schema.py --selftest
Exit 0 = stimmt überein, 1 = Abweichung, 2 = Export nicht möglich.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEAM = "J2DU2P47XW"
CONTAINER = "iCloud.de.linolaske.carbstock"
REFERENCE = ROOT / "cloudkit/schema.ckdb"
EXPECTED_TYPES = ["CD_Batch", "CD_Product", "CD_PurchaseEvaluation", "CD_ShoppingListItem", "CD_StockMovement"]


def parse(schema_text):
    """{Satztyp: {Feld: Typ}} aus einer .ckdb; Systemfelder ("___…") und GRANT-Zeilen werden übergangen."""
    out, current = {}, None
    for line in schema_text.splitlines():
        m = re.match(r"\s*RECORD TYPE (\w+) \(", line)
        if m:
            current = out.setdefault(m.group(1), {})
            continue
        if re.match(r"\s*\);", line):
            current = None
        m = re.match(r'\s*"?(\w+)"?\s+([A-Z][A-Z0-9_<>]*)(?: QUERYABLE| SORTABLE| SEARCHABLE)*,?\s*$', line)
        if m and current is not None and not m.group(1).startswith("___"):
            current[m.group(1)] = m.group(2)
    return out


def check(schema_text, reference_text):
    want = {k: v for k, v in parse(reference_text).items() if k.startswith("CD_")}
    have = {k: v for k, v in parse(schema_text).items() if k.startswith("CD_")}
    problems = []
    for rt in sorted(want.keys() - have.keys()):
        problems.append(f"Satztyp {rt} fehlt")
    for rt in sorted(have.keys() - want.keys()):
        problems.append(f"Satztyp {rt} ist unerwartet (nur Inventory gehört in CloudKit)")
    for rt in sorted(want.keys() & have.keys()):
        for field, typ in sorted(want[rt].items()):
            if field not in have[rt]:
                problems.append(f"{rt}: Feld {field} fehlt")
            elif have[rt][field] != typ:
                problems.append(f"{rt}: Feld {field} hat Typ {have[rt][field]} statt {typ}")
        for field in sorted(have[rt].keys() - want[rt].keys()):
            problems.append(f"{rt}: Feld {field} ist unerwartet")
    return problems, {k: len(v) for k, v in sorted(have.items())}


def selftest():
    ref = REFERENCE.read_text()
    assert sorted(k for k in parse(ref) if k.startswith("CD_")) == EXPECTED_TYPES
    assert check(ref, ref)[0] == [], check(ref, ref)[0]

    def edit(pattern, replacement):
        changed, n = re.subn(pattern, replacement, ref, count=1)
        assert n == 1, pattern
        return check(changed, ref)[0]

    assert edit(r"\n +CD_deviceID +STRING[^\n]*", "") == ["CD_StockMovement: Feld CD_deviceID fehlt"]
    assert edit(r"(CD_delta +)INT64", r"\1DOUBLE") == ["CD_StockMovement: Feld CD_delta hat Typ DOUBLE statt INT64"]
    assert edit(r"(\n +)(CD_delta )", r"\1CD_extra STRING,\1\2") == ["CD_StockMovement: Feld CD_extra ist unerwartet"]
    assert "Satztyp CD_Product fehlt" in check("DEFINE SCHEMA\n", ref)[0]
    extra = ref + "\n    RECORD TYPE CD_PackList (\n        CD_title STRING,\n    );\n"
    assert any("CD_PackList" in p for p in check(extra, ref)[0])
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--environment", default="development", choices=["development", "production"])
    ap.add_argument("--file")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.file:
        text = Path(a.file).read_text()
    else:
        r = subprocess.run(["xcrun", "cktool", "export-schema", "--team-id", TEAM, "--container-id", CONTAINER,
                            "--environment", a.environment], capture_output=True, text=True)
        if r.returncode != 0:
            print("Export nicht möglich:", r.stderr.strip() or r.stdout.strip(), file=sys.stderr)
            sys.exit(2)
        text = r.stdout
    problems, found = check(text, REFERENCE.read_text())
    print(f"Umgebung: {a.file or a.environment}; CD_-Satztypen (Felder): {found or 'keine'}")
    for p in problems:
        print("ABWEICHUNG:", p)
    print("Schema stimmt überein." if not problems else f"{len(problems)} Abweichung(en).")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
