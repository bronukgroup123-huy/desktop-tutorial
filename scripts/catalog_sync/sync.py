"""Звірка правил рушія (expert_rules) і довідника (mushroom_catalog) з книжковими описами.

    python3 scripts/catalog_sync/sync.py            # звіт «було → стало» (нічого не пише)
    python3 scripts/catalog_sync/sync.py --write    # + міграція, mushroom_catalog.json/.js, docs/CATALOG_SYNC.md

Дерева для 20 видів рушія записані вручну за формулюванням книги (поле «Де росте»):
  * «у хвойних, листяних і мішаних лісах… часто під соснами, дубами» — гриб росте в БУДЬ-ЯКОМУ
    такому лісі, дерева — приклади → загальні типи (coniferous / deciduous / mixed) + названі дерева;
  * «переважно під осиками», «у березових… лісах», «у соснових лісах», «утворює симбіоз з березою» —
    справжнє обмеження → лише названі дерева (+ «мішаний», якщо книга його називає).
Сезон і пік — з поля «Коли збирати» (розбір books.py).
"""
from __future__ import annotations

import calendar
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import books  # noqa: E402

ROOT = books.ROOT
SEED = ROOT / "supabase/migrations/20260912000002_forecast_seed.sql"
CATALOG = ROOT / "mushroom_catalog.json"
CATALOG_JS = ROOT / "data/catalog/mushroom_catalog.js"
MIGRATION = ROOT / "supabase/migrations/20261114100000_rules_from_books.sql"
REPORT = ROOT / "docs/CATALOG_SYNC.md"
CATALOG_TRAILING_NL = CATALOG.read_bytes().endswith(b"\n")

# mushroom_type → (дерева за книгою, чому так). None — книга дерев не називає: лишаємо як є.
FORESTS: dict[str, tuple[list[str] | None, str]] = {
    "boletus_edulis": (["coniferous", "deciduous", "mixed", "pine", "spruce", "oak", "beech", "birch", "hornbeam"],
                       "«У старих хвойних, листяних та змішаних лісах. Шукайте поблизу дубів, буків, беріз, грабів, ліщини, а також сосен та ялин»"),
    "lactarius_torminosus": (None, "у книзі немає поля «Де росте»"),
    "pleurotus_ostreatus": (["deciduous", "coniferous", "oak", "beech", "birch", "aspen"],
                            "«На стовбурах листяних дерев (тополя, верба, бук, дуб, береза, осика), рідше на хвойних»"),
    "lactarius_resimus": (["birch", "mixed"], "«У березових та мішаних з березою лісах… Утворює симбіоз з березою»"),
    "lycoperdon_perlatum": (None, "«на луках, пасовиськах, у лісах на галявинах» — без дерев"),
    "boletus_luridus": (["oak", "beech", "hornbeam"], "«У листяних лісах, переважно під дубом, буком, грабом, липою»"),
    "flammulina_velutipes": (["deciduous", "coniferous", "aspen"],
                             "«На пнях, стовбурах, гілках листяних дерев (особливо тополя, верба, осика, клен), рідше на хвойних»"),
    "hydnum_repandum": (["coniferous", "deciduous", "mixed", "pine", "spruce", "oak", "beech"],
                        "«У хвойних, листяних і мішаних лісах… під соснами, ялинами, дубами, буками»"),
    "suillus_bovinus": (["pine"], "«У соснових лісах, переважно на піщаному ґрунті»"),
    "cantharellus_cibarius": (["coniferous", "deciduous", "mixed", "pine", "spruce", "oak", "beech"],
                              "«У хвойних, листяних і мішаних лісах… під соснами, ялинами, дубами, буками»"),
    "suillus_luteus": (["pine", "mixed"], "«У соснових (особливо молодих) та мішаних із сосною лісах»"),
    "xerocomus_subtomentosus": (["coniferous", "deciduous", "mixed", "pine", "oak", "beech"],
                                "«У хвойних, листяних і мішаних лісах… під соснами, дубами, буками»"),
    "armillaria_mellea": (["coniferous", "deciduous", "mixed"], "«У хвойних, листяних і мішаних лісах. На пнях, стовбурах, корінні дерев»"),
    "agaricus_campestris": (["meadow"], "«На луках, полях, у цілинних степах, на пасовиськах» — не лісовий вид"),
    "leccinum_scabrum": (["birch", "mixed"], "«У березових або мішаних із березою лісах… під березами»"),
    "leccinum_aurantiacum": (["aspen", "mixed"], "«У листяних та мішаних лісах, переважно під осиками, рідше під тополями, вербами»"),
    "imleria_badia": (["coniferous", "mixed", "pine"], "«У хвойних і мішаних (з сосною) лісах»"),
    "lactarius_deliciosus": (["coniferous", "pine"], "«У хвойних, переважно молодих соснових, лісах»"),
    "russula_vesca": (["deciduous", "coniferous", "birch", "oak", "pine"],
                      "«У листяних та хвойних лісах… під березами, дубами, соснами»"),
    "morchella_esculenta": (None, "«У лісах, на опушках, у парках і садах, на вирубках» — без дерев"),
}

# Назви в сід-міграції → канонічні (міграція 20260912000007_forecast_fix_naming).
SEED_ALIASES = {"morchella_spp": "morchella_esculenta", "russula_spp": "russula_vesca",
                "lycoperdon_spp": "lycoperdon_perlatum", "xerocomus_spp": "xerocomus_subtomentosus"}

WAVES = [("wave_spring", {4, 5}), ("wave_summer1", {6}), ("wave_summer2", {7, 8}),
         ("wave_autumn", {9, 10}), ("wave_late", {11, 12, 1, 2})]


def seed_rules() -> dict[str, dict]:
    """Правила з сід-міграції (поточні значення: пізніші міграції змінювали лише назви й піки)."""
    s = SEED.read_text(encoding="utf-8")
    body = s[s.index(") VALUES") + 8: s.index(";", s.index(") VALUES"))]
    out = {}
    for r in re.split(r"\n  \(\n", body)[1:]:
        lines = [l.strip().rstrip(",") for l in r.strip().split("\n")]
        mt = re.match(r"\d+, '([^']+)'", lines[0]).group(1).replace("-", "_")
        mt = SEED_ALIASES.get(mt, mt)
        arr = re.findall(r"ARRAY\[([^\]]*)\]", lines[6])
        forest = re.findall(r"'([a-z_]+)'", arr[0]) if arr else []
        ss = re.findall(r"'(\d\d-\d\d)'", lines[10])
        waves = [w.strip() == "TRUE" for w in lines[11].split(",")]
        out[mt] = {"forest": forest, "start": ss[0], "end": ss[1], "waves": waves}
    return out


def season_bounds(months: list[int], text: str | None) -> tuple[str, str]:
    a, b = months[0], months[-1]
    d0, d1 = books.season_days(text) if text else (1, None)
    return f"{a:02d}-{d0:02d}", f"{b:02d}-{d1 or calendar.monthrange(2025, b)[1]:02d}"


def waves_for(months: list[int]) -> list[bool]:
    ms = set(months)
    return [bool(ms & w) for _, w in WAVES]


def sql_arr(xs, typ="TEXT") -> str:
    if not xs:
        return f"'{{}}'::{typ}[]"
    return f"ARRAY[{','.join(repr(x) if typ == 'TEXT' else str(x) for x in xs)}]::{typ}[]"


def main(write: bool) -> None:
    descs = books.load()
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    cat = {s["id"]: s for s in catalog["species"]}
    rules = seed_rules()

    rule_rows, cat_rows, report = [], [], []
    for mt, (forest, why) in FORESTS.items():
        r = rules[mt]
        desc = descs.get(mt, "")
        months, peak, season_text = books.season(desc)
        c = cat[mt]
        new_forest = forest if forest is not None else r["forest"]
        new_months = months or c["months"]
        new_peak = [p for p in (peak or c.get("peak_months") or []) if p in new_months]
        start, end = season_bounds(new_months, season_text if months else None)
        waves = waves_for(new_months)
        changes = []
        if sorted(new_forest) != sorted(r["forest"]):
            changes.append(f"дерева {r['forest']} → {new_forest}")
        if (start, end) != (r["start"], r["end"]):
            changes.append(f"сезон {r['start']}…{r['end']} → {start}…{end}")
        if waves != r["waves"]:
            changes.append("хвилі " + ", ".join(n.replace("wave_", "") for (n, _), w in zip(WAVES, waves) if w))
        if new_peak != (c.get("peak_months") or []):
            changes.append(f"пік {c.get('peak_months')} → {new_peak}")
        if new_months != c["months"]:
            changes.append(f"місяці довідника {c['months']} → {new_months}")
            cat_rows.append((mt, new_months, new_peak))
        elif new_peak != (c.get("peak_months") or []):
            cat_rows.append((mt, new_months, new_peak))
        rule_rows.append((mt, new_forest, start, end, waves, new_peak))
        report.append((c["name"], mt, changes, why, season_text))
        print(f"{c['name']:22} " + ("; ".join(changes) if changes else "без змін"))

    if not write:
        return
    if MIGRATION.exists() and "--force" not in sys.argv:
        raise SystemExit(f"{MIGRATION.name} уже є (можливо, застосована): для нових змін — нова міграція або --force")

    # ── Міграція ──
    lines = [
        "-- ============================================================================",
        "-- Правила рушія і довідник — за книжковими описами (scripts/catalog_sync/sync.py)",
        "-- Дерева (forest_type), сезон, хвилі й пік 20 видів рушія; місяці довідника, де їх",
        "-- неправильно розібрано (зимовий опеньок — «цілий рік») або змінено всупереч книзі (глива).",
        "-- Звіт: docs/CATALOG_SYNC.md. Згенеровано — не редагувати вручну.",
        "-- ============================================================================",
        "",
    ]
    for mt, forest, start, end, waves, peak in rule_rows:
        wave_sql = ", ".join(f"{n} = {'TRUE' if w else 'FALSE'}" for (n, _), w in zip(WAVES, waves))
        lines.append(
            f"UPDATE public.expert_rules SET forest_type = {sql_arr(forest)}, season_start = '{start}', "
            f"season_end = '{end}', {wave_sql}, peak_months = {sql_arr(peak, 'INT')}, "
            f"peak_waves = public.months_to_waves({sql_arr(peak, 'INT')}) WHERE mushroom_type = '{mt}';"
        )
    lines.append("")
    for mt, months, peak in cat_rows:
        lines.append(
            f"UPDATE public.mushroom_catalog SET months = {sql_arr(months, 'INT')}, "
            f"peak_months = {sql_arr(peak, 'INT')}, updated_at = now() WHERE id = '{mt}';"
        )
    MIGRATION.write_text("\n".join(lines) + "\n", encoding="utf-8")

    # ── Довідник (JSON + копія для веб-застосунку) ──
    for mt, months, peak in cat_rows:
        cat[mt]["months"] = months
        if peak:
            cat[mt]["peak_months"] = peak
        else:
            cat[mt].pop("peak_months", None)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + ("\n" if CATALOG_TRAILING_NL else ""), encoding="utf-8")
    js = CATALOG_JS.read_text(encoding="utf-8")
    head = js[: js.index("window.MUSHROOM_CATALOG")]
    body = json.dumps(catalog, ensure_ascii=False, separators=(",", ":")).replace("</script", "<\\/script")
    CATALOG_JS.write_text(f"{head}window.MUSHROOM_CATALOG = {body};\n", encoding="utf-8")

    # ── Звіт ──
    md = ["# Звірка з книгами — правила рушія і довідник", "",
          "Згенеровано `scripts/catalog_sync/sync.py` (міграція `20261114100000_rules_from_books.sql`).",
          "Джерело — книжкові описи (`опис.txt` → `data/catalog/mushroom_descriptions.js`).", "",
          "| Вид | Що змінено | Де росте (книга) | Коли збирати (книга) |", "|---|---|---|---|"]
    for name, mt, changes, why, season_text in report:
        md.append(f"| {name} | {'<br>'.join(changes) if changes else 'без змін'} | {why} | {season_text or '—'} |")
    REPORT.write_text("\n".join(md) + "\n", encoding="utf-8")
    print(f"→ {MIGRATION.relative_to(ROOT)}, {CATALOG.name}, {CATALOG_JS.relative_to(ROOT)}, {REPORT.relative_to(ROOT)}")


if __name__ == "__main__":
    main("--write" in sys.argv)
