#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
parse_200_detailed.py
Читає list_200_detailed.txt і генерує CSV:
  distribution_200.csv   : scientific_name,zones
  descriptions_200.csv   : scientific_name,key_features_ai
  habitats_200.csv       : scientific_name,season,forest_types,substrate,description
  twins_200.csv          : scientific_name,twin_scientific_name,twin_common_name,distinguishing
  culinary_200.csv       : scientific_name,cooking_note,requires_cooking,taste_note,storage_note
"""
import csv, re

INPUT_FILE = 'list_200_detailed.txt'

# Мапа регіонів (з parse_distribution.py)
REGION_NAMES = {
    'вінницька':'Вінницька','волинська':'Волинська',
    'дніпропетровська':'Дніпропетровська','донецька':'Донецька',
    'житомирська':'Житомирська','закарпатська':'Закарпатська',
    'запорізька':'Запорізька','івано-франківська':'Івано-Франківська',
    'київська':'Київська','кіровоградська':'Кіровоградська',
    'луганська':'Луганська','львівська':'Львівська',
    'миколаївська':'Миколаївська','одеська':'Одеська',
    'полтавська':'Полтавська','рівненська':'Рівненська',
    'сумська':'Сумська','тернопільська':'Тернопільська',
    'харківська':'Харківська','херсонська':'Херсонська',
    'хмельницька':'Хмельницька','черкаська':'Черкаська',
    'чернівецька':'Чернівецька','чернігівська':'Чернігівська',
    'ар крим':'АР Крим','крим':'АР Крим',
}

PSEUDO = {
    'карпати':['Закарпатська','Івано-Франківська','Львівська','Чернівецька'],
    'прикарпаття':['Івано-Франківська','Львівська','Чернівецька'],
    'полісся':['Волинська','Рівненська','Житомирська','Київська','Чернігівська'],
    'західне полісся':['Волинська','Рівненська'],
    'правобережне полісся':['Житомирська','Київська','Рівненська'],
    'лівобережне полісся':['Чернігівська','Сумська','Полтавська'],
    'центральне полісся':['Київська','Житомирська'],
    'лісостеп':['Вінницька','Черкаська','Полтавська','Харківська','Тернопільська','Хмельницька','Кіровоградська'],
    'правобережний лісостеп':['Вінницька','Черкаська','Тернопільська','Хмельницька'],
    'лівобережний лісостеп':['Полтавська','Харківська','Сумська'],
    'степ':['Дніпропетровська','Запорізька','Миколаївська','Одеська','Херсонська','Донецька'],
    'злаково-лучний степ':['Дніпропетровська','Запорізька','Миколаївська'],
    'злаковий степ':['Дніпропетровська','Запорізька'],
    'гірський крим':['АР Крим'],
    'розтоцько-опільські ліси':['Львівська'],
}


def parse_zones(text: str) -> list:
    result = set()
    text_lower = text.lower()
    all_keys = sorted(
        list(PSEUDO.keys()) + list(REGION_NAMES.keys()),
        key=len, reverse=True
    )
    for key in all_keys:
        if key in text_lower:
            if key in PSEUDO:
                result.update(PSEUDO[key])
            else:
                result.add(REGION_NAMES[key])
            text_lower = text_lower.replace(key, ' ' * len(key))
    if 'по всій' in text_lower or 'всі області' in text_lower:
        result.update(REGION_NAMES.values())
    return sorted(result)


def parse_species_blocks(content: str) -> list:
    blocks = []
    parts = re.split(r'\n(?=\d+\.\s+🍄\s+)', content)
    for part in parts:
        part = part.strip()
        if not part:
            continue
        m = re.match(r'(\d+)\.\s+🍄\s+(.+?)(?:\s*\(([^)]*)\))?\s*\n', part)
        if not m:
            continue
        number = int(m.group(1))
        common_name = m.group(2).strip()
        alt_name = m.group(3).strip() if m.group(3) else ''
        rest = part[m.end():]

        # Determine scientific_name: if alt_name looks like latin (contains space, starts with capital), use it
        # Otherwise, take the first non-empty line of rest
        if alt_name and re.match(r'^[A-Z][a-z]+ [a-z]+', alt_name):
            scientific_name = alt_name
        else:
            first_line = rest.split('\n')[0].strip()
            scientific_name = first_line
            # Remove the first line from rest if we used it
            rest = '\n'.join(rest.split('\n')[1:])

        status_m = re.search(r'⚠️\s*СТАТУС:\s*(.+)', rest)
        status = status_m.group(1).strip() if status_m else ''

        appearance_m = re.search(r'🔍\s*ЯК ВИГЛЯДАЄ:\n(.+?)(?=\n📍\s*ДЕ ШУКАТИ:)', rest, re.DOTALL)
        appearance = appearance_m.group(1).strip() if appearance_m else ''

        location_m = re.search(r'📍\s*ДЕ ШУКАТИ:\n(.+?)(?=\n⚠️\s*НЕ СПЛУТАЙ:)', rest, re.DOTALL)
        location = location_m.group(1).strip() if location_m else ''

        twins_m = re.search(r'⚠️\s*НЕ СПЛУТАЙ:\n(.+?)(?=\n✅\s*ПОРАДИ:)', rest, re.DOTALL)
        twins_raw = twins_m.group(1).strip() if twins_m else ''

        tips_m = re.search(r'✅\s*ПОРАДИ:\n(.+)', rest, re.DOTALL)
        tips_raw = tips_m.group(1).strip() if tips_m else ''

        blocks.append({
            'number': number,
            'common_name': common_name,
            'alt_name': alt_name,
            'scientific_name': scientific_name,
            'status': status,
            'appearance': appearance,
            'location': location,
            'twins_raw': twins_raw,
            'tips_raw': tips_raw,
        })
    return blocks


def extract_zones(location_text: str) -> str:
    lines = location_text.split('\n')
    regions_line = ''
    for line in lines:
        line = line.strip()
        if line.startswith('• Області України:'):
            regions_line = line.replace('• Області України:', '').strip()
            break
    if not regions_line:
        return ''
    zones = parse_zones(regions_line)
    return '|'.join(zones)


def extract_season(location_text: str) -> str:
    for line in location_text.split('\n'):
        line = line.strip()
        if line.startswith('• Сезон:'):
            return line.replace('• Сезон:', '').strip()
    return ''


def extract_forest_types(location_text: str) -> str:
    for line in location_text.split('\n'):
        line = line.strip()
        if line.startswith('• Ліс/місце:'):
            return line.replace('• Ліс/місце:', '').strip()
    return ''


def extract_key_features(appearance_text: str) -> str:
    lines = [l.strip() for l in appearance_text.split('\n') if l.strip()]
    return ' '.join(lines)


def extract_twins(twins_raw: str) -> list:
    twins = []
    for line in twins_raw.split('\n'):
        line = line.strip()
        if not line.startswith('• '):
            continue
        line = line[2:]
        m = re.match(r'(.+?)\s+—\s+(.+?)\s+—\s+(.+)', line)
        if m:
            twins.append({
                'name': m.group(1).strip(),
                'status': m.group(2).strip(),
                'distinguishing': m.group(3).strip(),
            })
    return twins


def extract_culinary(tips_raw: str):
    cooking = ''
    taste = ''
    storage = ''
    requires_cooking = False
    for line in tips_raw.split('\n'):
        line = line.strip()
        if line.startswith('• Як готувати:'):
            cooking = line.replace('• Як готувати:', '').strip()
            requires_cooking = 'відварювання' in cooking.lower() and 'не обов\'язкове' not in cooking.lower() and 'не потрібне' not in cooking.lower()
        elif line.startswith('• Цінність:'):
            taste = line.replace('• Цінність:', '').strip()
        elif line.startswith('• Особливості:'):
            storage = line.replace('• Особливості:', '').strip()
    return cooking, requires_cooking, taste, storage


def main():
    with open(INPUT_FILE, encoding='utf-8') as f:
        content = f.read()

    blocks = parse_species_blocks(content)
    print(f"✓ Знайдено блоків: {len(blocks)}")

    dist_rows = []
    desc_rows = []
    habitat_rows = []
    twin_rows = []
    culinary_rows = []

    for b in blocks:
        sci = b['scientific_name']
        zones = extract_zones(b['location'])
        dist_rows.append([sci, zones])

        desc_rows.append([sci, extract_key_features(b['appearance'])])

        season = extract_season(b['location'])
        forest = extract_forest_types(b['location'])
        habitat_rows.append([sci, season, forest, '', b['appearance'].replace('\n', ' ')])

        twins = extract_twins(b['twins_raw'])
        for t in twins:
            twin_rows.append([sci, t['name'], t['status'], t['distinguishing']])

        cooking, req_cook, taste, storage = extract_culinary(b['tips_raw'])
        culinary_rows.append([sci, cooking, 'true' if req_cook else 'false', taste, storage])

    # distribution_200.csv
    with open('distribution_200.csv', 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerow(['scientific_name', 'zones'])
        w.writerows(dist_rows)
    print(f"✓ distribution_200.csv: {len(dist_rows)} рядків")

    # descriptions_200.csv
    with open('descriptions_200.csv', 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerow(['scientific_name', 'key_features_ai'])
        w.writerows(desc_rows)
    print(f"✓ descriptions_200.csv: {len(desc_rows)} рядків")

    # habitats_200.csv
    with open('habitats_200.csv', 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerow(['scientific_name', 'season', 'forest_types', 'substrate', 'description'])
        w.writerows(habitat_rows)
    print(f"✓ habitats_200.csv: {len(habitat_rows)} рядків")

    # twins_200.csv
    with open('twins_200.csv', 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerow(['scientific_name', 'twin_name', 'twin_status', 'distinguishing'])
        w.writerows(twin_rows)
    print(f"✓ twins_200.csv: {len(twin_rows)} рядків")

    # culinary_200.csv
    with open('culinary_200.csv', 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerow(['scientific_name', 'cooking_note', 'requires_cooking', 'taste_note', 'storage_note'])
        w.writerows(culinary_rows)
    print(f"✓ culinary_200.csv: {len(culinary_rows)} рядків")


if __name__ == '__main__':
    main()
