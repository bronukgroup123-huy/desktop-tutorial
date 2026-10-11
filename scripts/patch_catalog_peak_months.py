#!/usr/bin/env python3
"""
Патчить mushroom_catalog.json:
- Додає peak_months для 9 top20 видів (з §9 плану v6.0 + мікологія)
- Розширює months для pleurotus_ostreatus (варіант B)
Ідемпотентний: повторний запуск не змінить нічого.
Також оновлює mushroom_catalog.js.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JSON_PATH = ROOT / "mushroom_catalog.json"
JS_PATH = ROOT / "mushroom_catalog.js"

PATCHES = {
    "morchella_esculenta":     {"peak_months": [4, 5]},
    "lactarius_resimus":       {"peak_months": [7, 8]},
    "agaricus_campestris":     {"peak_months": [7, 8]},
    "xerocomus_subtomentosus": {"peak_months": [7, 8]},
    "suillus_bovinus":         {"peak_months": [7, 8]},
    "imleria_badia":           {"peak_months": [9, 10]},
    "lactarius_torminosus":    {"peak_months": [9, 10]},
    "flammulina_velutipes":    {"peak_months": [11, 12, 1, 2]},
    "pleurotus_ostreatus": {
        "peak_months": [11, 12, 1, 2],
        "months": [6, 7, 8, 9, 10, 11, 12, 1, 2],
    },
}


def main():
    if not JSON_PATH.exists():
        sys.exit(f"❌ Не знайдено {JSON_PATH}")

    with open(JSON_PATH, encoding="utf-8") as f:
        data = json.load(f)

    applied = 0
    skipped = 0
    for sp in data.get("species", []):
        sid = sp.get("id")
        if sid in PATCHES:
            for key, val in PATCHES[sid].items():
                if sp.get(key) != val:
                    sp[key] = val
                    applied += 1
                    print(f"  ✏️  {sid}: {key} = {val}")
                else:
                    skipped += 1

    print(f"\n✅ Застосовано {applied} змін, пропущено {skipped} (вже правильні)")

    with open(JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    js_content = (
        "// mushroom_catalog.js\n"
        "// Автогенеровано scripts/patch_catalog_peak_months.py. Не редагувати вручну.\n"
        "window.MUSHROOM_CATALOG = "
        + json.dumps(data, ensure_ascii=False, separators=(",", ":"))
        + ";\n"
    )
    with open(JS_PATH, "w", encoding="utf-8") as f:
        f.write(js_content)

    print(f"✅ Оновлено {JS_PATH}")


if __name__ == "__main__":
    main()
