"""Іконки грибів для стікерів мінікарти (ADR-015 §15.9): 20 SVG із data/catalog/mushroomIcons.js
(«DETAILED_SVGS», відповідають книжковим описам) → flutter_client/assets/stickers/<mushroom_type>.svg.

    python3 scripts/stickers/extract_svgs.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "data/catalog/mushroomIcons.js"
OUT = ROOT / "flutter_client/assets/stickers"
# Ключі веб-іконок → mushroom_type рушія (міграція 20260912000007_forecast_fix_naming).
ALIASES = {"russula_spp": "russula_vesca", "morchella_spp": "morchella_esculenta",
           "lycoperdon_spp": "lycoperdon_perlatum", "xerocomus_spp": "xerocomus_subtomentosus"}


RGBA = re.compile(r'(fill|stroke)="rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)"')


def plain_colors(svg: str) -> str:
    """rgba(…) → колір + *-opacity: так їх надійно малює flutter_svg."""
    def sub(m: re.Match) -> str:
        attr, r, g, b, a = m.groups()
        return f'{attr}="#{int(r):02x}{int(g):02x}{int(b):02x}" {attr}-opacity="{a}"'
    return RGBA.sub(sub, svg)


def main() -> None:
    js = SRC.read_text(encoding="utf-8")
    block = js[js.index("const DETAILED_SVGS = {"):]
    OUT.mkdir(parents=True, exist_ok=True)
    n = 0
    for key, svg in re.findall(r'^\s*"([a-z-]+)":\s*`(.*?)`', block, re.S | re.M):
        mt = key.replace("-", "_")
        mt = ALIASES.get(mt, mt)
        (OUT / f"{mt}.svg").write_text(plain_colors(svg.strip()) + "\n", encoding="utf-8")
        n += 1
    print(f"{n} іконок → {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
