"""Довідник для застосунку (рішення PO 2026-11-15).

Джерела — ті самі, що й у вебверсії (web-guardian/public/landing.html):
  * web-guardian/public/mushroom_catalog.js     — види, атрибути, фото;
  * web-guardian/public/mushroom_descriptions.js — книжкові описи.

Результат:
  * flutter_client/assets/catalog/catalog.json.gz — види з фото (як показує веб-довідник):
    назва, латина, їстівність, Червона книга, Топ-20 / популярні, місяці, дерева, сезони,
    імена фото й опис. Вбудовується в застосунок — працює без інтернету.
  * --photos DIR — фото для телефону (WebP: до 1080 px і мініатюра 420 px для списку) з
    іменами <id>-<n>.webp / <id>-0-t.webp; їх викладає .github/workflows/catalog.yml у реліз
    «catalog-data», застосунок завантажує й зберігає на телефоні під час перегляду.

Запуск: python3 scripts/catalog_sync/build_app_catalog.py [--photos dist/catalog]
"""
from __future__ import annotations

import argparse
import gzip
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG_JS = ROOT / "web-guardian/public/mushroom_catalog.js"
DESC_JS = ROOT / "web-guardian/public/mushroom_descriptions.js"
OUT = ROOT / "flutter_client/assets/catalog/catalog.json.gz"

FULL_PX = 1080
THUMB_PX = 420


def load_js_object(path: Path) -> dict:
    s = path.read_text(encoding="utf-8")
    start = s.index("{")
    end = s.rstrip().rstrip(";").rindex("}") + 1
    return json.loads(s[start:end])


def photo_name(species_id: str, n: int, thumb: bool = False) -> str:
    return f"{species_id}-{n}{'-t' if thumb else ''}.webp"


def build() -> tuple[dict, list[tuple[Path, str, int]]]:
    catalog = load_js_object(CATALOG_JS)
    descriptions = load_js_object(DESC_JS)
    species, photos = [], []
    for s in catalog["species"]:
        if not s.get("photos"):
            continue  # як у веб-довіднику: показуємо види з фото
        sid = s["id"]
        names = []
        for n, rel in enumerate(s["photos"]):
            src = ROOT / rel
            if not src.exists():
                print(f"  ! немає файлу {rel}", file=sys.stderr)
                continue
            names.append(photo_name(sid, n))
            photos.append((src, photo_name(sid, n), FULL_PX))
            if n == 0:
                photos.append((src, photo_name(sid, 0, thumb=True), THUMB_PX))
        attrs = s.get("attrs") or {}
        lic = s.get("license") or {}
        species.append({
            "id": sid,
            "name": s["name"],
            "latin": s.get("latin", ""),
            "edibility": s.get("edibility") or "",
            "red_listed": bool(s.get("red_listed")),
            "rarity": s.get("rarity") or "",
            "top20": bool(s.get("top20")),
            "popular": bool(s.get("popular")),
            "months": s.get("months") or [],
            "peak_months": s.get("peak_months") or [],
            "tree": attrs.get("tree") or [],
            "season": attrs.get("season") or [],
            "photos": names,
            # Автор і ліцензія фото (CC BY — підпис обов'язковий).
            "license": {k: lic[k] for k in ("author", "type", "url") if lic.get(k)} or None,
            # Ключі описів — через дефіс (agaricus-arvensis), id видів — через підкреслення.
            "description": descriptions.get(sid.replace("_", "-")) or descriptions.get(sid) or "",
        })
    species.sort(key=lambda x: x["name"])
    return {"version": catalog["meta"].get("generated", ""), "species": species}, photos


def write_photos(photos: list[tuple[Path, str, int]], out_dir: Path) -> None:
    from PIL import Image  # pip install pillow

    out_dir.mkdir(parents=True, exist_ok=True)
    for src, name, px in photos:
        dst = out_dir / name
        with Image.open(src) as im:
            im = im.convert("RGB")
            im.thumbnail((px, px))
            im.save(dst, "WEBP", quality=78 if px == FULL_PX else 72, method=6)
    total = sum((out_dir / n).stat().st_size for _, n, _ in photos)
    print(f"  фото: {len(photos)} файлів, {total / 1e6:.1f} МБ → {out_dir}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--photos", type=Path, help="куди покласти фото для релізу catalog-data")
    args = ap.parse_args()
    data, photos = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    raw = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    # mtime=0 — однаковий вміст дає однаковий файл (без зайвих змін у git).
    with gzip.GzipFile(OUT, "wb", compresslevel=9, mtime=0) as f:
        f.write(raw)
    print(f"  довідник: {len(data['species'])} видів, {len(raw) / 1e3:.0f} КБ → {OUT.stat().st_size / 1e3:.0f} КБ gzip")
    if args.photos:
        write_photos(photos, args.photos)


if __name__ == "__main__":
    main()
