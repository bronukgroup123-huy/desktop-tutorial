#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
regions_map.py

Мапінги областей, фізико-географічних регіонів та їхніх slug/лейблів.
"""

REGIONS = {
    "Вінницька": "vinnytska",
    "Волинська": "volynska",
    "Дніпропетровська": "dnipropetrovska",
    "Донецька": "donetska",
    "Житомирська": "zhytomyrska",
    "Закарпатська": "zakarpatska",
    "Запорізька": "zaporizka",
    "Івано-Франківська": "ivano-frankivska",
    "Київська": "kyivska",
    "Кіровоградська": "kirovohradska",
    "Луганська": "luhanska",
    "Львівська": "lvivska",
    "Миколаївська": "mykolaivska",
    "Одеська": "odeska",
    "Полтавська": "poltavska",
    "Рівненська": "rivnenska",
    "Сумська": "sumska",
    "Тернопільська": "ternopilska",
    "Харківська": "kharkivska",
    "Херсонська": "khersonska",
    "Хмельницька": "khmelnytska",
    "Черкаська": "cherkaska",
    "Чернівецька": "chernivetska",
    "Чернігівська": "chernihivska",
    "АР Крим": "krym",
    "Крим": "krym",
}

GEO_REGIONS = {
    "Карпати": ["zakarpatska", "ivano-frankivska", "lvivska", "chernivetska"],
    "Прикарпаття": ["ivano-frankivska", "lvivska", "chernivetska"],
    "Закарпаття": ["zakarpatska"],
    "Полісся": ["volynska", "rivnenska", "zhytomyrska", "kyivska", "chernihivska", "sumska"],
    "Західне Полісся": ["volynska", "rivnenska"],
    "Центральне Полісся": ["kyivska", "zhytomyrska", "chernihivska"],
    "Лівобережне Полісся": ["chernihivska", "sumska", "kyivska"],
    "Правобережне Полісся": ["zhytomyrska", "rivnenska", "volynska", "kyivska"],
    "Лісостеп": ["vinnytska", "kyivska", "poltavska", "sumska", "kharkivska", "cherkaska", "khmelnytska", "ternopilska", "chernivetska", "kirovohradska"],
    "Правобережний Лісостеп": ["vinnytska", "kyivska", "cherkaska", "khmelnytska", "ternopilska"],
    "Лівобережний Лісостеп": ["poltavska", "sumska", "kharkivska", "cherkaska"],
    "Степ": ["zaporizka", "khersonska", "mykolaivska", "odeska", "dnipropetrovska", "donetska", "luhanska", "kirovohradska"],
    "Гірський Крим": ["krym"],
    "Південний Крим": ["krym"],
    "Крим": ["krym"],
    "Ростоцько-Опільські Ліси": ["lvivska", "ivano-frankivska"],
}

ALL_REGIONS = [
    "vinnytska", "volynska", "dnipropetrovska", "donetska", "zhytomyrska",
    "zakarpatska", "zaporizka", "ivano-frankivska", "kyivska", "kirovohradska",
    "luhanska", "lvivska", "mykolaivska", "odeska", "poltavska",
    "rivnenska", "sumska", "ternopilska", "kharkivska", "khersonska",
    "khmelnytska", "cherkaska", "chernivetska", "chernihivska", "krym"
]

REGION_LABELS = {
    "vinnytska": "Вінницька",
    "volynska": "Волинська",
    "dnipropetrovska": "Дніпропетровська",
    "donetska": "Донецька",
    "zhytomyrska": "Житомирська",
    "zakarpatska": "Закарпатська",
    "zaporizka": "Запорізька",
    "ivano-frankivska": "Івано-Франківська",
    "kyivska": "Київська",
    "kirovohradska": "Кіровоградська",
    "luhanska": "Луганська",
    "lvivska": "Львівська",
    "mykolaivska": "Миколаївська",
    "odeska": "Одеська",
    "poltavska": "Полтавська",
    "rivnenska": "Рівненська",
    "sumska": "Сумська",
    "ternopilska": "Тернопільська",
    "kharkivska": "Харківська",
    "khersonska": "Херсонська",
    "khmelnytska": "Хмельницька",
    "cherkaska": "Черкаська",
    "chernivetska": "Чернівецька",
    "chernihivska": "Чернігівська",
    "krym": "АР Крим",
}
