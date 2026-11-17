"""Фото двійників без ліцензійних обмежень (рішення PO 2026-11-17: «бери фото, якщо вони без
ліцензії»): лише суспільне надбання (Public domain) і CC0 — без вимоги підпису.

Шукає на Wikimedia Commons (за латинською назвою; файл має стосуватися саме цього виду), а якщо
там замало — на iNaturalist (лише фото з ліцензією CC0, спостереження «research grade»).
Кожне фото записується в папку виду `фото двійників (webp)/<Назва> <Latin>/` як WebP і
блоком у `ліцензія.txt` (автор, ліцензія, сторінка фото) — у тому ж форматі, що й інші папки,
тож scripts/build_licenses.py і довідник застосунку показують їх так само.
Далі — шляхи фото в mushroom_catalog.json / .js (has_photo), ліцензії, довідник застосунку.

Запуск (потрібна мережа до commons.wikimedia.org і api.inaturalist.org — у CI):
    python3 scripts/catalog_sync/fetch_free_photos.py
"""
from __future__ import annotations

import io
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOLDER = "фото двійників (webp)"
CATALOG = ROOT / "mushroom_catalog.json"
CATALOG_JS = ROOT / "web-guardian/public/mushroom_catalog.js"
PER_SPECIES = 3
UA = "GrybnyiRadar-catalog/1.0 (https://github.com/bronukgroup123-huy/desktop-tutorial)"

# Двійники, яких бракувало в довіднику (перевертень «Як відрізнити» показував «Фото поки немає»).
SPECIES = ["tylopilus_felleus", "lactarius_pubescens", "gyrodon_lividus"]

CC0_URL = "https://creativecommons.org/publicdomain/zero/1.0/"
PD_URL = "https://commons.wikimedia.org/wiki/Help:Public_domain"


def get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def get_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def plain(html: str | None) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", html or "")).strip()


def free_license(meta: dict) -> tuple[str, str] | None:
    """(назва, посилання) для CC0 / суспільного надбання без вимоги підпису; інакше None."""
    short = plain(meta.get("LicenseShortName", {}).get("value"))
    code = plain(meta.get("License", {}).get("value")).lower()
    attribution = plain(meta.get("AttributionRequired", {}).get("value")).lower()
    if attribution == "true":
        return None
    if code.startswith("cc0") or short.upper().startswith("CC0"):
        return "CC0 1.0", CC0_URL
    if code.startswith("pd") or short.lower().startswith("public domain"):
        return "Суспільне надбання (Public domain)", PD_URL
    return None


def commons(latin: str) -> list[dict]:
    q = urllib.parse.urlencode({
        "action": "query", "format": "json", "generator": "search", "gsrnamespace": 6,
        "gsrsearch": f'"{latin}" filetype:bitmap', "gsrlimit": 50,
        "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": 1600,
    })
    pages = get_json(f"https://commons.wikimedia.org/w/api.php?{q}").get("query", {}).get("pages", {})
    out = []
    for p in pages.values():
        info = (p.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata") or {}
        if info.get("mime") not in ("image/jpeg", "image/png") or (info.get("width") or 0) < 800:
            continue
        lic = free_license(meta)
        if not lic:
            continue
        # Файл має стосуватися саме цього виду (пошук знаходить і схожі).
        about = " ".join([p.get("title", ""), plain(meta.get("ImageDescription", {}).get("value")),
                          plain(meta.get("Categories", {}).get("value")), plain(meta.get("ObjectName", {}).get("value"))])
        if latin.lower() not in about.lower().replace("_", " "):
            continue
        author = plain(meta.get("Artist", {}).get("value")) or "невідомий автор"
        out.append({
            "url": info.get("thumburl") or info["url"], "page": info.get("descriptionurl"),
            "author": f"{author}, Wikimedia Commons", "license": lic, "size": info.get("width", 0),
        })
    # Той самий файл різними форматами (…t._103.png і …t._103.jpg) — один раз; фотографії
    # (JPEG) — перед малюнками (PNG).
    seen, unique = set(), []
    for x in sorted(out, key=lambda x: (x["url"].lower().endswith(".png"), -x["size"])):
        stem = re.sub(r"\.(jpe?g|png)$", "", (x["page"] or "").lower())
        if stem not in seen:
            seen.add(stem)
            unique.append(x)
    return unique


def inaturalist(latin: str) -> list[dict]:
    q = urllib.parse.urlencode({
        "taxon_name": latin, "photo_license": "cc0", "quality_grade": "research",
        "per_page": 30, "order_by": "votes",
    })
    out = []
    for obs in get_json(f"https://api.inaturalist.org/v1/observations?{q}").get("results", []):
        if (obs.get("taxon") or {}).get("name", "").lower() != latin.lower():
            continue
        for ph in obs.get("photos") or []:
            if (ph.get("license_code") or "").lower() != "cc0":
                continue
            user = (obs.get("user") or {})
            out.append({
                "url": ph["url"].replace("square", "large"),
                "page": f"https://www.inaturalist.org/photos/{ph['id']}",
                "author": f"{user.get('name') or user.get('login') or 'невідомий автор'}, iNaturalist",
                "license": ("CC0 1.0", CC0_URL), "size": 0,
            })
            break  # одне фото зі спостереження — різні гриби, не серія
    return out


def to_webp(data: bytes) -> bytes:
    from PIL import Image  # pip install pillow

    buf = io.BytesIO()
    with Image.open(io.BytesIO(data)) as im:
        im = im.convert("RGB")
        im.thumbnail((1600, 1600))
        im.save(buf, "WEBP", quality=85, method=6)
    return buf.getvalue()


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    by_id = {s["id"]: s for s in catalog["species"]}
    changed = 0
    for sid in SPECIES:
        s = by_id[sid]
        latin, name = s["latin"], s["name"]
        picks = commons(latin)
        if len(picks) < PER_SPECIES:
            time.sleep(1)
            picks += inaturalist(latin)
        picks = picks[:PER_SPECIES]
        print(f"{latin}: {len(picks)} фото без обмежень")
        if not picks:
            continue
        folder = ROOT / FOLDER / f"{name} {latin}"
        folder.mkdir(parents=True, exist_ok=True)
        for old in folder.glob("*.webp"):
            old.unlink()  # повторний запуск — без залишків попереднього вибору
        blocks, rels = [], []
        for n, p in enumerate(picks):
            fname = "large.webp" if n == 0 else f"large ({n}).webp"
            (folder / fname).write_bytes(to_webp(get_bytes(p["url"])))
            rels.append(f"{FOLDER}/{name} {latin}/{fname}")
            blocks.append(f"{latin} ({name}).\nФото: {p['author']}.\nЛіцензія: {p['license'][0]} — {p['license'][1]}\n"
                          f"Джерело: {p['page']}")
            print(f"  {fname}: {p['author']} · {p['license'][0]} · {p['page']}")
            time.sleep(1)
        (folder / "ліцензія.txt").write_text("\n\n".join(blocks) + "\n", encoding="utf-8")
        s["photos"] = rels
        s["has_photo"] = True
        changed += 1
    if changed:
        catalog["meta"]["with_photos"] = sum(1 for x in catalog["species"] if x.get("photos"))
        trailing = CATALOG.read_bytes().endswith(b"\n")
        CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + ("\n" if trailing else ""), encoding="utf-8")
        js = CATALOG_JS.read_text(encoding="utf-8")
        head = js[: js.index("window.MUSHROOM_CATALOG")]
        body = json.dumps(catalog, ensure_ascii=False, separators=(",", ":")).replace("</script", "<\\/script")
        CATALOG_JS.write_text(f"{head}window.MUSHROOM_CATALOG = {body};\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
