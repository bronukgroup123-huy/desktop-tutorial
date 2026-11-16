"""Довідник для застосунку (рішення PO 2026-11-15).

Джерела — ті самі, що й у вебверсії (web-guardian/public/landing.html):
  * web-guardian/public/mushroom_catalog.js     — види, атрибути, фото;
  * web-guardian/public/mushroom_descriptions.js — книжкові описи.

Результат:
  * flutter_client/assets/catalog/catalog.json.gz — види з фото (як показує веб-довідник):
    назва, латина, їстівність, Червона книга, Топ-20 / популярні, місяці, дерева, сезони,
    імена фото й опис. Вбудовується в застосунок — працює без інтернету.
  * --photos DIR — фото для телефону (WebP: до 1080 px і мініатюра 420 px для списку) з
    іменами <id>-<n>.webp / <id>-0-t.webp, запаковані в архіви tar: <id>.tar — фото виду,
    thumbs.tar — мініатюри всіх видів. Архіви, а не окремі файли: GitHub обмежує кількість
    завантажень у реліз (сотні окремих фото впираються в ліміт). manifest.json — розміри
    архівів (для «Фото без інтернету» в застосунку). Їх викладає
    .github/workflows/catalog.yml у реліз «catalog-photos»; застосунок завантажує архів виду під
    час перегляду, розпаковує й зберігає фото на телефоні.

Запуск: python3 scripts/catalog_sync/build_app_catalog.py [--photos dist/catalog]
"""
from __future__ import annotations

import argparse
import gzip
import io
import json
import tarfile
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
            # Області, де вид поширений (коди як у ukraine_oblasts.json) — карта на сторінці виду.
            "zones": s.get("zones") or [],
            "photos": names,
            # Автор і ліцензія фото (CC BY — підпис обов'язковий).
            "license": {k: lic[k] for k in ("author", "type", "url") if lic.get(k)} or None,
            # Ключі описів — через дефіс (agaricus-arvensis), id видів — через підкреслення.
            "description": descriptions.get(sid.replace("_", "-")) or descriptions.get(sid) or "",
        })
    species.sort(key=lambda x: x["name"])
    return {"version": catalog["meta"].get("generated", ""), "species": species}, photos


def _webp(src: Path, px: int) -> bytes:
    from PIL import Image  # pip install pillow

    buf = io.BytesIO()
    with Image.open(src) as im:
        im = im.convert("RGB")
        im.thumbnail((px, px))
        im.save(buf, "WEBP", quality=78 if px == FULL_PX else 72, method=6)
    return buf.getvalue()


def _add(tar: tarfile.TarFile, name: str, data: bytes) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mtime = 0  # однаковий вміст — однаковий архів
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def bundle_name(photo: str) -> str:
    """Архів, у якому лежить фото: мініатюри — thumbs.tar, решта — <id>.tar."""
    if photo.endswith("-t.webp"):
        return "thumbs.tar"
    return photo.rsplit("-", 1)[0] + ".tar"


def write_photos(photos: list[tuple[Path, str, int]], out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    bundles: dict[str, list[tuple[str, bytes]]] = {}
    for src, name, px in photos:
        bundles.setdefault(bundle_name(name), []).append((name, _webp(src, px)))
    for bundle, files in sorted(bundles.items()):
        with tarfile.open(out_dir / bundle, "w", format=tarfile.USTAR_FORMAT) as tar:
            for name, data in sorted(files):
                _add(tar, name, data)
    sizes = {b: (out_dir / b).stat().st_size for b in sorted(bundles)}
    total = sum(sizes.values())
    # Розміри архівів — застосунок показує, скільки займе «Завантажити всі фото», і прогрес.
    (out_dir / "manifest.json").write_text(
        json.dumps({"total": total, "bundles": sizes}, separators=(",", ":")), encoding="utf-8")
    print(f"  фото: {len(photos)} шт. у {len(bundles)} архівах, {total / 1e6:.1f} МБ → {out_dir}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--photos", type=Path, help="куди покласти фото для релізу catalog-photos")
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
