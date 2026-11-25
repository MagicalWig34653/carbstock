#!/usr/bin/env python3
"""Prüft das CloudKit-Development-Schema gegen die Inventory-Modelle (Gate G1, docs/G1-SCHEMA-REVIEW.md).

Nur lesend: `xcrun cktool export-schema`, kein Import, kein Deploy. Erwartet werden die fünf Satztypen CD_<Modell> mit je
einem Feld CD_<Attribut> für jedes gespeicherte Attribut und jede to-one-Beziehung. Zusätzliche Felder (System- und
Core-Data-Felder wie CD_entityName, ___…) sind in Ordnung; Satztypen für Training oder Imports sind ein Fehler.

Nutzung:
  scripts/pruefe-cloudkit-schema.py                 # exportiert Development mit dem gespeicherten cktool-Token
  scripts/pruefe-cloudkit-schema.py --environment production
  scripts/pruefe-cloudkit-schema.py --file schema.ckdb
  scripts/pruefe-cloudkit-schema.py --selftest
Exit 0 = vollständig, 1 = Abweichung, 2 = Export nicht möglich.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEAM = "J2DU2P47XW"
CONTAINER = "iCloud.de.linolaske.carbstock"
MODEL_FILE = ROOT / "App/Models/InventoryModels.swift"
LOCAL_ONLY = ["TrainingSession", "WeeklyTemplateRecord", "CarbRateOverride", "PackList", "PackListItem",
              "ImportedActivity", "ActivityPairDecision"]


def expected(source):
    """{Modell: {Attribute und to-one-Beziehungen}} aus dem Quelltext (Kommentare entfernt)."""
    text = re.sub(r"//[^\n]*", "", source)
    models = {}
    for block in text.split("@Model")[1:]:
        name = re.search(r"class (\w+)", block).group(1)
        body = block.split("\n    init(")[0]
        props = set()
        for m in re.finditer(r"^    (?:@\w+(?:\([^)]*\))?\s+)*var (\w+): ([^=\n{]+)", body, re.M):
            prop, typ = m.group(1), m.group(2).strip()
            if re.match(r"^\[.*\]\??$", typ) and typ.strip("[]?") in {"Batch", "StockMovement", "Product"}:
                continue  # to-many: liegt im Gegenstück
            props.add(prop)
        models[name] = props
    return models


def parse(schema_text):
    """{Satztyp: {Feld}} aus der .ckdb-Ausgabe von cktool."""
    out, current = {}, None
    for line in schema_text.splitlines():
        m = re.match(r"\s*RECORD TYPE (\w+) \(", line)
        if m:
            current = out.setdefault(m.group(1), set())
            continue
        m = re.match(r'\s*"?(\w+)"?\s+[A-Z][A-Z0-9_<>]*(?: QUERYABLE| SORTABLE| SEARCHABLE)*,?\s*$', line)
        if m and current is not None:
            current.add(m.group(1))
    return out


def check(schema_text, source):
    want, have = expected(source), parse(schema_text)
    problems = []
    for model, props in sorted(want.items()):
        rt = "CD_" + model
        if rt not in have:
            problems.append(f"Satztyp {rt} fehlt")
            continue
        for p in sorted(props):
            if "CD_" + p not in have[rt]:
                problems.append(f"{rt}: Feld CD_{p} fehlt")
    for model in LOCAL_ONLY:
        if "CD_" + model in have:
            problems.append(f"Satztyp CD_{model} darf nicht in CloudKit stehen (lokal)")
    return problems, {k: len(v) for k, v in have.items() if k.startswith("CD_")}


def selftest():
    src = MODEL_FILE.read_text()
    want = expected(src)
    assert sorted(want) == ["Batch", "Product", "PurchaseEvaluation", "ShoppingListItem", "StockMovement"], sorted(want)
    assert "deviceID" in want["StockMovement"] and "batch" in want["StockMovement"] and "batches" not in want["Product"]
    full = "DEFINE SCHEMA\n" + "".join(
        f"\n    RECORD TYPE CD_{m} (\n" + "".join(f"        CD_{p} STRING,\n" for p in sorted(ps)) + "        GRANT WRITE TO \"_creator\"\n    );\n"
        for m, ps in want.items())
    assert check(full, src)[0] == [], check(full, src)[0]
    missing = full.replace("        CD_deviceID STRING,\n", "")
    assert check(missing, src)[0] == ["CD_StockMovement: Feld CD_deviceID fehlt"], check(missing, src)[0]
    assert "Satztyp CD_Product fehlt" in check("DEFINE SCHEMA\n", src)[0]
    assert any("CD_PackList" in p for p in check(full + "\n    RECORD TYPE CD_PackList (\n        CD_title STRING,\n    );\n", src)[0])
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
    problems, found = check(text, MODEL_FILE.read_text())
    print(f"Umgebung: {a.file or a.environment}; CD_-Satztypen: {found or 'keine'}")
    for p in problems:
        print("FEHLT:", p)
    print("Schema vollständig." if not problems else f"{len(problems)} Abweichung(en).")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
