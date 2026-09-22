#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Читає два файли поширення і пише distribution.csv
Формат виходу: scientific_name,zones
"""
import csv, re

# ---------- Мапа назв областей ----------
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

# Псевдоніми регіонів → області
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

def parse_zones(text: str) -> set:
    """Витягує області з довільного тексту."""
    result = set()
    text_lower = text.lower()

    # 1. Прямі назви областей
    for key, val in REGION_NAMES.items():
        if key in text_lower:
            result.add(val)

    # 2. Псевдоніми
    for key, regions in PSEUDO.items():
        if key in text_lower:
            result.update(regions)

    # 3. «По всій Україні» = всі 25
    if 'по всій' in text_lower or 'всі області' in text_lower:
        result.update(REGION_NAMES.values())

    return result


def parse_file_55(path):
    """Файл 'поширення.txt' (55 рядків з таблиці)."""
    out = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) < 4: continue
            try: int(parts[0])
            except ValueError: continue
            sci = parts[2].strip()
            zones_text = parts[3]
            out[sci] = parse_zones(zones_text)
    return out


def parse_file_top20(path):
    """Файл 'поширення.txt' (TOP-20 у форматі 'N. Назва — Latin\\nОбласті: ...')."""
    out = {}
    with open(path, encoding='utf-8') as f:
        content = f.read()

    # Розбиваємо по блоках "N. Назва — Latin"
    blocks = re.split(r'\n(?=\d+\.\s)', content)
    for block in blocks:
        m = re.match(r'(\d+)\.\s+(.+?)\s+—\s+(.+?)\n', block)
        if not m: continue
        sci = m.group(3).strip()
        # Беремо рядок "Області: ..."
        zones_m = re.search(r'Області?:\s*(.+)', block, re.DOTALL)
        if zones_m:
            out[sci] = parse_zones(zones_m.group(1))
    return out


def main():
    # Обидва файли збережені як distribution_55.txt і distribution_top20.txt
    d55 = parse_file_55('distribution_55.txt')
    d20 = parse_file_top20('distribution_top20.txt')

    # Об'єднуємо
    merged = {}
    for k, v in d20.items(): merged[k] = v
    for k, v in d55.items():
        merged.setdefault(k, set()).update(v)

    # Пишемо
    with open('distribution.csv', 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerow(['scientific_name','zones'])
        for sci in sorted(merged):
            zones = '|'.join(sorted(merged[sci]))
            w.writerow([sci, zones])

    print(f"✓ distribution.csv: {len(merged)} видів")

if __name__ == '__main__':
    main()
