#!/usr/bin/env python3
"""
parse_season.py — парсить 📅 Коли збирати? з усіх описів,
додає months і peak_months у mushroom_catalog.json та перегенерує mushroom_catalog.js.

Запуск:  python3 scripts/parse_season.py
"""
import re, json, os, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESC_FILE = ROOT / 'mushroom_descriptions.js'
CATALOG_FILE = ROOT / 'mushroom_catalog.json'
CATALOG_JS = ROOT / 'mushroom_catalog.js'

# ── Ukrainian month dictionary ──────────────────────────────────────
MONTHS = {
    'січень': 1, 'січня': 1, 'січні': 1,
    'лютий': 2, 'лютого': 2, 'лютому': 2,
    'березень': 3, 'березня': 3, 'березні': 3,
    'квітень': 4, 'квітня': 4, 'квітні': 4,
    'травень': 5, 'травня': 5, 'травні': 5,
    'червень': 6, 'червня': 6, 'червні': 6,
    'липень': 7, 'липня': 7, 'липні': 7,
    'серпень': 8, 'серпня': 8, 'серпні': 8,
    'вересень': 9, 'вересня': 9, 'вересні': 9,
    'жовтень': 10, 'жовтня': 10, 'жовтні': 10,
    'листопад': 11, 'листопада': 11, 'листопаді': 11,
    'грудень': 12, 'грудня': 12, 'грудні': 12,
}

MONTH_RE = re.compile(
    r'\b(' + '|'.join(sorted(MONTHS.keys(), key=len, reverse=True)) + r')\b',
    re.IGNORECASE
)

# Peak indicators (in priority order)
PEAK_RE = re.compile(
    r'(?:'
    r'\((?:пік|наймасовіше|найбільше|наймасовіша хвиля)\s*[—:\-][^)]*\)'  # (пік — ...)
    r'|'
    r'(?:Пік|Наймасовіше|Найбільше|наймасовіша хвиля)\s*[—:\-]\s*[^.]*'  # Пік — ...
    r')',
    re.IGNORECASE
)


def find_months(text):
    """Return list of (position, month_number) for all month mentions."""
    results = []
    for m in MONTH_RE.finditer(text):
        name = m.group(1).lower()
        if name in MONTHS:
            results.append((m.start(), MONTHS[name]))
    return results


def extract_month_range(text):
    """Extract month range from text. Returns sorted list of month numbers."""
    found = find_months(text)
    if not found:
        return None
    nums = sorted(set(n for _, n in found))
    if len(nums) == 1:
        return [nums[0]]
    # Continuous range from min to max
    return list(range(nums[0], nums[-1] + 1))


def try_table_format(lines):
    """
    Try to extract season text from table format when there is no 📅 marker.
    Header example: Де росте\tКоли збирати\tПорада\tПоширення в Україні
    Next line:      <де росте>\t<сезон>\t<порада>\t<поширення>
    Returns season text or None.
    """
    for i, line in enumerate(lines):
        if 'коли збирати' not in line.lower() or '\t' not in line:
            continue
        headers = line.split('\t')
        col_idx = None
        for j, h in enumerate(headers):
            if 'коли збирати' in h.lower():
                col_idx = j
                break
        if col_idx is None:
            continue
        if i + 1 >= len(lines):
            return None
        values = lines[i + 1].split('\t')
        if col_idx >= len(values):
            return None
        return values[col_idx].strip()
    return None


def parse_season_text(raw_desc):
    """
    Parse 📅 section from raw description.
    Returns (months, peak_months) or (None, None) if not found.
    """
    lines = raw_desc.split('\n')
    season_text = None
    
    # Try old format first: 📅 Коли збирати?\t<text>
    for line in lines:
        if '📅' in line and 'коли збирати' in line.lower():
            if '\t' in line:
                season_text = line.split('\t', 1)[1].strip()
            else:
                season_text = line.split('📅', 1)[-1].strip().lstrip(' Коли збирати? ')
            break
    
    # Try table format: Де росте\tКоли збирати\tПорада\t...
    if not season_text:
        season_text = try_table_format(lines)
    
    if not season_text:
        return None, None

    # Find peak indicator and split
    peak_match = PEAK_RE.search(season_text)
    if peak_match:
        main_text = season_text[:peak_match.start()] + season_text[peak_match.end():]
        peak_text = peak_match.group(0)
    else:
        main_text = season_text
        peak_text = None

    # Parse months from main text
    months = extract_month_range(main_text)

    # Parse peak months
    peak_months = None
    if peak_text:
        peak_months = extract_month_range(peak_text)

    return months, peak_months


def load_descriptions():
    """Load mushroom_descriptions.js and return dict."""
    txt = DESC_FILE.read_text(encoding='utf-8')
    m = re.search(r'window\.MUSHROOM_DESCRIPTIONS\s*=\s*(\{.*?\});\s*$', txt, re.S)
    if not m:
        print(f'ERROR: cannot parse {DESC_FILE}', file=sys.stderr)
        sys.exit(1)
    return json.loads(m.group(1))


def main():
    print('Loading descriptions...')
    descriptions = load_descriptions()
    print(f'  {len(descriptions)} descriptions loaded')

    print('Loading catalog...')
    catalog = json.loads(CATALOG_FILE.read_text(encoding='utf-8'))
    species = catalog['species']
    print(f'  {len(species)} species loaded')

    parsed_count = 0
    fallback_count = 0
    no_data_count = 0

    for sp in species:
        sp_id = sp['id']
        desc = descriptions.get(sp_id, '')

        if '📅' in desc or 'коли збирати' in desc.lower():
            months, peak_months = parse_season_text(desc)
            if months:
                sp['months'] = months
                if peak_months:
                    sp['peak_months'] = peak_months
                parsed_count += 1
            else:
                # Fallback to catalog months
                if sp.get('months'):
                    fallback_count += 1
                else:
                    no_data_count += 1
        else:
            # No 📅 section — keep existing catalog months
            if not sp.get('months'):
                no_data_count += 1

    # Clean up: remove peak_months if empty or same as months
    for sp in species:
        if sp.get('peak_months') == sp.get('months'):
            sp.pop('peak_months', None)
        elif not sp.get('peak_months'):
            sp.pop('peak_months', None)

    print(f'\nResults:')
    print(f'  Parsed from 📅:        {parsed_count}')
    print(f'  Fallback to catalog:    {fallback_count}')
    print(f'  No data at all:         {no_data_count}')

    # Save catalog JSON
    CATALOG_FILE.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2),
        encoding='utf-8'
    )
    print(f'\nUpdated: {CATALOG_FILE.name}')

    # Regenerate JS
    js_body = json.dumps(catalog, ensure_ascii=False, separators=(',', ':'))
    js_body = js_body.replace('</script', '<\\/script')
    CATALOG_JS.write_text(
        f'window.MUSHROOM_CATALOG = {js_body};\n',
        encoding='utf-8'
    )
    print(f'Updated: {CATALOG_JS.name}')
    print('\nDone!')


if __name__ == '__main__':
    main()