#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Сканує папку `фото Топ-20 грибів (webp)` і генерує photos_top20.csv
для подальшого імпорту в таблицю species_photos.
"""
import csv, os, re
from pathlib import Path

PHOTO_DIR = Path('фото Топ-20 грибів (webp)')

# Мапа: назва папки -> scientific_name
FOLDER_TO_SCI = {
    'Білий гриб Boletus edulis': 'Boletus edulis',
    'Вовнянка рожева Lactarius torminosus': 'Lactarius torminosus',
    'Глива звичайна Pleurotus ostreatus': 'Pleurotus ostreatus',
    'Груздь справжній Lactarius resimus': 'Lactarius resimus',
    'Дощовик їстівний Lycoperdon perlatum': 'Lycoperdon perlatum',
    'Дубовик звичайний Suillellus luridus': 'Suillellus luridus',
    'Зимовий опеньок Flammulina velutipes': 'Flammulina velutipes',
    'Козляк Suillus bovinus': 'Suillus bovinus',
    'Лисичка справжня Cantharellus cibarius': 'Cantharellus cibarius',
    'Маслюк пізній Suillus luteus': 'Suillus luteus',
    'Моховик зелений Xerocomus subtomentosus': 'Xerocomus subtomentosus',
    'Опеньок осінній Armillaria mellea': 'Armillaria mellea',
    'Печериця звичайна Agaricus campestris': 'Agaricus campestris',
    'Польський гриб Imleria badia': 'Imleria badia',
    'Підберезник звичайний Leccinum scabrum': 'Leccinum scabrum',
    'Підосичник Leccinum aurantiacum': 'Leccinum aurantiacum',
    'Рижик справжній Lactarius deliciosus': 'Lactarius deliciosus',
    'Сироїжка Russula vesca': 'Russula vesca',
    'Сморчок звичайний Morchella esculenta': 'Morchella esculenta',
    'Їжовик жовтуватий Hydnum repandum': 'Hydnum repandum',
}

def angle_from_filename(name: str) -> str:
    n = name.lower()
    if 'cap_top' in n or 'верх' in n:
        return 'cap_top'
    if 'cap_bottom' in n or 'низ' in n:
        return 'cap_bottom'
    if 'stem' in n or 'ніжка' in n or 'ножка' in n:
        return 'stem'
    if 'flesh' in n or 'м' in n or 'секція' in n:
        return 'flesh_cut'
    if 'habitat' in n or 'місце' in n or 'середовище' in n:
        return 'habitat'
    if 'in_hand' in n or 'в руці' in n or 'рука' in n:
        return 'in_hand'
    if 'twin' in n or 'двійник' in n or 'порівн' in n:
        return 'twin_comparison'
    if 'scale' in n or 'масштаб' in n or 'лінійка' in n:
        return 'scale_reference'
    return 'general'

def main():
    rows = []
    for folder in sorted(PHOTO_DIR.iterdir()):
        if not folder.is_dir():
            continue
        sci = FOLDER_TO_SCI.get(folder.name)
        if not sci:
            continue

        files = sorted(folder.glob('*.webp'))
        for idx, path in enumerate(files, start=1):
            rows.append({
                'scientific_name': sci,
                'file_name': path.name,
                'storage_path': str(path),
                'angle': angle_from_filename(path.name),
                'license_code': 'cc0',
                'license_url': '',
                'license_file_path': '',
                'author': '',
                'source_url': '',
                'attribution': '',
                'modified': 'false',
                'modification_note': '',
                'sort_order': idx,
            })

    out_path = Path('photos_top20.csv')
    with out_path.open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=[
            'scientific_name','file_name','storage_path','angle',
            'license_code','license_url','license_file_path','author',
            'source_url','attribution','modified','modification_note','sort_order'
        ])
        writer.writeheader()
        writer.writerows(rows)

    print(f"✓ photos_top20.csv: {len(rows)} фото для {len(FOLDER_TO_SCI)} видів")

if __name__ == '__main__':
    main()
