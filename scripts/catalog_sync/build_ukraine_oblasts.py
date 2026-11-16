"""Карта областей України для довідника («Де поширений» — рішення PO 2026-11-16).

Джерело: Natural Earth, Admin 1 – States, Provinces (1:10m), суспільне надбання (public domain):
  https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson

Області беремо за кодом ISO 3166-2 «UA-*» — тож Крим (UA-43) і Севастополь (UA-40) входять в
Україну незалежно від того, якій країні їх приписує набір даних. Київ (UA-30) малюється разом із
Київською областю, Севастополь — разом із Кримом (зони видів у каталозі — ці 25 кодів).

Результат: flutter_client/assets/catalog/ukraine_oblasts.json — спрощені контури (Дуглас–Пекер,
≈2 км), координати до 0.01°: {"source": …, "oblasts": {"zhytomyrska": [[[lon, lat], …], …], …}}.

Запуск: python3 scripts/catalog_sync/build_ukraine_oblasts.py ne_10m_admin_1_states_provinces.geojson
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "flutter_client/assets/catalog/ukraine_oblasts.json"
TOLERANCE = 0.02  # градуси (~2 км): контур упізнаваний, файл малий

# ISO 3166-2 → код області в каталозі (mushroom_catalog.zones).
ISO_TO_SLUG = {
    "UA-05": "vinnytska", "UA-07": "volynska", "UA-09": "luhanska", "UA-12": "dnipropetrovska",
    "UA-14": "donetska", "UA-18": "zhytomyrska", "UA-21": "zakarpatska", "UA-23": "zaporizka",
    "UA-26": "ivano-frankivska", "UA-30": "kyivska", "UA-32": "kyivska", "UA-35": "kirovohradska",
    "UA-40": "krym", "UA-43": "krym", "UA-46": "lvivska", "UA-48": "mykolaivska", "UA-51": "odeska",
    "UA-53": "poltavska", "UA-56": "rivnenska", "UA-59": "sumska", "UA-61": "ternopilska",
    "UA-63": "kharkivska", "UA-65": "khersonska", "UA-68": "khmelnytska", "UA-71": "cherkaska",
    "UA-74": "chernihivska", "UA-77": "chernivetska",
}


def _dist(p, a, b) -> float:
    (x, y), (x1, y1), (x2, y2) = p, a, b
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return ((x - x1) ** 2 + (y - y1) ** 2) ** 0.5
    t = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
    return ((x - x1 - t * dx) ** 2 + (y - y1 - t * dy) ** 2) ** 0.5


def simplify(points: list, tol: float) -> list:
    """Дуглас–Пекер без рекурсії."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        best, idx = 0.0, -1
        for k in range(i + 1, j):
            d = _dist(points[k], points[i], points[j])
            if d > best:
                best, idx = d, k
        if best > tol and idx > 0:
            keep[idx] = True
            stack += [(i, idx), (idx, j)]
    return [p for p, k in zip(points, keep) if k]


def main() -> None:
    src = Path(sys.argv[1])
    data = json.loads(src.read_text(encoding="utf-8"))
    oblasts: dict[str, list] = {}
    for f in data["features"]:
        slug = ISO_TO_SLUG.get(f["properties"].get("iso_3166_2", ""))
        if not slug:
            continue
        g = f["geometry"]
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        for poly in polys:
            ring = simplify(poly[0], TOLERANCE)  # лише зовнішній контур — дірок в областях немає
            if len(ring) < 4:
                continue  # дрібні острови
            oblasts.setdefault(slug, []).append([[round(x, 2), round(y, 2)] for x, y in ring])
    missing = set(ISO_TO_SLUG.values()) - set(oblasts)
    if missing:
        sys.exit(f"немає областей: {sorted(missing)}")
    out = {
        "source": "Natural Earth (public domain), Admin 1 1:10m; спрощено",
        "oblasts": dict(sorted(oblasts.items())),
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    pts = sum(len(r) for rings in oblasts.values() for r in rings)
    print(f"  області: {len(oblasts)}, точок: {pts}, {OUT.stat().st_size / 1e3:.0f} КБ → {OUT}")


if __name__ == "__main__":
    main()
