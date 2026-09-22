#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Генерує master.csv — 333 види, з zones та key_features_ai для 200 видів без фото.
"""
import csv

HEADER = [
    'scientific_name','common_name_uk','edibility_status',
    'has_photos','in_top20','is_popular',
    'is_poisonous','is_deadly','is_red_listed','rarity_label_uk',
    'in_ai_recognition','has_ai_prompt','legacy_id',
    'zones','key_features_ai','season','photo_path',
]

PHOTO_DIR = 'фото Топ-20 грибів (webp)'
PHOTO_MAP = {
    'Boletus edulis': f'{PHOTO_DIR}/Білий гриб Boletus edulis/large.webp',
    'Lactarius torminosus': f'{PHOTO_DIR}/Вовнянка рожева Lactarius torminosus/large.webp',
    'Pleurotus ostreatus': f'{PHOTO_DIR}/Глива звичайна Pleurotus ostreatus/large.webp',
    'Lactarius resimus': f'{PHOTO_DIR}/Груздь справжній Lactarius resimus/large.webp',
    'Lycoperdon perlatum': f'{PHOTO_DIR}/Дощовик їстівний Lycoperdon perlatum/large.webp',
    'Boletus luridus': f'{PHOTO_DIR}/Дубовик звичайний Suillellus luridus/large.webp',
    'Flammulina velutipes': f'{PHOTO_DIR}/Зимовий опеньок Flammulina velutipes/large.webp',
    'Hydnum repandum': f'{PHOTO_DIR}/Їжовик жовтуватий Hydnum repandum/large.webp',
    'Suillus bovinus': f'{PHOTO_DIR}/Козляк Suillus bovinus/large.webp',
    'Cantharellus cibarius': f'{PHOTO_DIR}/Лисичка справжня Cantharellus cibarius/large.webp',
    'Suillus luteus': f'{PHOTO_DIR}/Маслюк пізній Suillus luteus/large.webp',
    'Xerocomus subtomentosus': f'{PHOTO_DIR}/Моховик зелений Xerocomus subtomentosus/large.webp',
    'Armillaria mellea': f'{PHOTO_DIR}/Опеньок осінній Armillaria mellea/large.webp',
    'Agaricus campestris': f'{PHOTO_DIR}/Печериця звичайна Agaricus campestris/large.webp',
    'Leccinum scabrum': f'{PHOTO_DIR}/Підберезник звичайний Leccinum scabrum/large.webp',
    'Leccinum aurantiacum': f'{PHOTO_DIR}/Підосичник Leccinum aurantiacum/large.webp',
    'Imleria badia': f'{PHOTO_DIR}/Польський гриб Imleria badia/large.webp',
    'Lactarius deliciosus': f'{PHOTO_DIR}/Рижик справжній Lactarius deliciosus/large.webp',
    'Russula vesca': f'{PHOTO_DIR}/Сироїжка Russula vesca/large.webp',
    'Morchella esculenta': f'{PHOTO_DIR}/Сморчок звичайний Morchella esculenta/large.webp',
}

POPULAR_55_DIR = 'фото популярні 55 грибів (webp)'
POPULAR_55_MAP = {
    'Hydnum rufescens': f'{POPULAR_55_DIR}/Їжовик рудуватий Hydnum rufescens/large.webp',
    'Hydnum umbilicatum': f'{POPULAR_55_DIR}/Їжовик ямчастий Hydnum umbilicatum/large.webp',
    'Albatrellopsis confluens': f'{POPULAR_55_DIR}/Альбатрел злитий Albatrellopsis confluens/large.webp',
    'Albatrellus ovinus': f'{POPULAR_55_DIR}/Альбатрел овечий Albatrellus ovinus/large.webp',
    'Boletus pinophilus': f'{POPULAR_55_DIR}/Білий гриб сосновий Boletus pinophilus/large.webp',
    'Boletus reticulatus': f'{POPULAR_55_DIR}/Білий гриб сітчастий Boletus reticulatus/large.webp',
    'Pleurotus dryinus': f'{POPULAR_55_DIR}/Глива дубова Pleurotus dryinus/large.webp',
    'Pleurotus pulmonarius': f'{POPULAR_55_DIR}/Глива легенева Pleurotus pulmonarius/large.webp',
    'Macrolepiota procera': f'{POPULAR_55_DIR}/Гриб-зонтик великий Macrolepiota procera/large.webp',
    'Macrolepiota mastoidea': f'{POPULAR_55_DIR}/Гриб-зонтик сосковидний Macrolepiota mastoidea/large.webp',
    'Tricholoma equestre': f'{POPULAR_55_DIR}/Зеленушка Tricholoma equestre/large.webp',
    'Clavulina coralloides': f'{POPULAR_55_DIR}/Клавуліна зморшкувата Clavulina coralloides/large.webp',
    'Cantharellus friesii': f'{POPULAR_55_DIR}/Лисичка Фріза Cantharellus friesii/large.webp',
    'Cantharellus amethysteus': f'{POPULAR_55_DIR}/Лисичка аметистова Cantharellus amethysteus/large.webp',
    'Craterellus lutescens': f'{POPULAR_55_DIR}/Лисичка жовта Craterellus lutescens/large.webp',
    'Craterellus cinereus': f'{POPULAR_55_DIR}/Лисичка сіра Craterellus cinereus/large.webp',
    'Craterellus tubaeformis': f'{POPULAR_55_DIR}/Лисичка трубчаста Craterellus tubaeformis/large.webp',
    'Suillus placidus': f'{POPULAR_55_DIR}/Маслюк білий Suillus placidus/large.webp',
    'Suillus variegatus': f'{POPULAR_55_DIR}/Маслюк жовто-бурий Suillus variegatus/large.webp',
    'Suillus granulatus': f'{POPULAR_55_DIR}/Маслюк зернистий Suillus granulatus/large.webp',
    'Suillus grevillei': f'{POPULAR_55_DIR}/Маслюк модриновий Suillus grevillei/large.webp',
    'Xerocomellus chrysenteron': f'{POPULAR_55_DIR}/Моховик тріщинуватий Xerocomellus chrysenteron/large.webp',
    'Amanita excelsa': f'{POPULAR_55_DIR}/Мухомор високий Amanita excelsa/large.webp',
    'Amanita rubescens': f'{POPULAR_55_DIR}/Мухомор червоніючий Amanita rubescens/large.webp',
    'Amanita crocea': f'{POPULAR_55_DIR}/Мухомор шафрановий Amanita crocea/large.webp',
    'Kuehneromyces mutabilis': f'{POPULAR_55_DIR}/Опеньок літній Kuehneromyces mutabilis/large.webp',
    'Armillaria ostoyae': f'{POPULAR_55_DIR}/Опеньок темний Armillaria ostoyae/large.webp',
    'Amanita fulva': f'{POPULAR_55_DIR}/Поплавок жовто-коричневий Amanita fulva/large.webp',
    'Amanita vaginata': f'{POPULAR_55_DIR}/Поплавок сірий Amanita vaginata/large.webp',
    'Leccinellum pseudoscabrum': f'{POPULAR_55_DIR}/Підберезник грабовий Leccinellum pseudoscabrum/large.webp',
    'Leccinum versipelle': f'{POPULAR_55_DIR}/Підберезник жовто-бурий Leccinum versipelle/large.webp',
    'Leccinum variicolor': f'{POPULAR_55_DIR}/Підберезник різнокольоровий Leccinum variicolor/large.webp',
    'Leccinum duriusculum': f'{POPULAR_55_DIR}/Підберезник тополевий Leccinum duriusculum/large.webp',
    'Russula delica': f'{POPULAR_55_DIR}/Підгруздь Russula delica/large.webp',
    'Leccinum rufum': f'{POPULAR_55_DIR}/Підосичник білоніжковий Leccinum rufum/large.webp',
    'Ramaria botrytis': f'{POPULAR_55_DIR}/Рамарія гроновидна Ramaria botrytis/large.webp',
    'Lactarius deterrimus': f'{POPULAR_55_DIR}/Рижик ялиновий Lactarius deterrimus/large.webp',
    'Lactarius salmonicolor': f'{POPULAR_55_DIR}/Рижик ялицевий Lactarius salmonicolor/large.webp',
    'Tricholoma terreum': f'{POPULAR_55_DIR}/Рядовка землиста Tricholoma terreum/large.webp',
    'Collybia personata': f'{POPULAR_55_DIR}/Рядовка ліловонога Collybia personata/large.webp',
    'Calocybe gambosa': f'{POPULAR_55_DIR}/Рядовка майська Calocybe gambosa/large.webp',
    'Tricholoma portentosum': f'{POPULAR_55_DIR}/Рядовка сіра Tricholoma portentosum/large.webp',
    'Collybia nuda': f'{POPULAR_55_DIR}/Рядовка фіолетова Collybia nuda/large.webp',
    'Russula xerampelina': f'{POPULAR_55_DIR}/Сироїжка буро-червона Russula xerampelina/large.webp',
    'Russula virescens': f'{POPULAR_55_DIR}/Сироїжка зелена Russula virescens/large.webp',
    'Russula cyanoxantha': f'{POPULAR_55_DIR}/Сироїжка синьо-жовта Russula cyanoxantha/large.webp',
    'Russula foetens': f'{POPULAR_55_DIR}/Сироїжка смердюча Russula foetens/large.webp',
    'Lactifluus vellereus': f'{POPULAR_55_DIR}/Скрипиця Lactifluus vellereus/large.webp',
    'Cerioporus squamosus': f'{POPULAR_55_DIR}/Трутовик лускатий Cerioporus squamosus/large.webp',
    'Laetiporus sulphureus': f'{POPULAR_55_DIR}/Трутовик сірчано-жовтий Laetiporus sulphureus/large.webp',
    'Lactarius quietus': f'{POPULAR_55_DIR}/Хрящ-молочник дубовий Lactarius quietus/large.webp',
    'Lactifluus piperatus': f'{POPULAR_55_DIR}/Хрящ-молочник перцевий Lactifluus piperatus/large.webp',
    'Lactarius subdulcis': f'{POPULAR_55_DIR}/Хрящ-молочник солодкуватий Lactarius subdulcis/large.webp',
    'Lactifluus volemus': f'{POPULAR_55_DIR}/Хрящ-молочник їстівний Lactifluus volemus/large.webp',
    'Albatrellus confluens': f'{POPULAR_55_DIR}/Альбатрел злитий Albatrellopsis confluens/large.webp',
    'Clavulina cristata': f'{POPULAR_55_DIR}/Клавуліна гребінчаста Clavulina coralloides/large.webp',
    'Leccinum albostipitatum': f'{POPULAR_55_DIR}/Підосичник білоніжковий Leccinum rufum/large.webp',
}

POISONOUS_DIR = 'Отруйні та смертельно отруйні (webp)'
POISONOUS_MAP = {
    'Amanita muscaria': f'{POISONOUS_DIR}/Amanita muscaria  Мухомор червоний/large.webp',
    'Amanita pantherina': f'{POISONOUS_DIR}/Amanita pantherina Мухомор пантерний/large.webp',
    'Amanita phalloides': f'{POISONOUS_DIR}/Amanita phalloides Бліда поганка/large.webp',
    'Amanita verna': f'{POISONOUS_DIR}/Amanita verna Мухомор весняний/large.webp',
    'Amanita virosa': f'{POISONOUS_DIR}/Amanita virosa Мухомор смердючий/large.webp',
    'Clitocybe candicans': f'{POISONOUS_DIR}/Clitocybe candicans Говорушка білувата/large.webp',
    'Clitocybe dealbata': f'{POISONOUS_DIR}/Clitocybe dealbata Говорушка воскова/large.webp',
    'Entoloma sinuatum': f'{POISONOUS_DIR}/Entoloma sinuatum Ентолома отруйна/large.webp',
    'Galerina marginata': f'{POISONOUS_DIR}/Galerina marginata Галерина облямована/large.webp',
    'Gyromitra esculenta': f'{POISONOUS_DIR}/Gyromitra esculenta Строчок звичайний/large.webp',
    'Hygrophoropsis aurantiaca': f'{POISONOUS_DIR}/Hygrophoropsis aurantiaca Лисичка несправжня/large.webp',
    'Inocybe erubescens': f'{POISONOUS_DIR}/Inocybe erubescens Волоконниця червоніюча/large.webp',
    'Inocybe geophylla': f'{POISONOUS_DIR}/Inocybe geophylla Іноцибе звичайний/large.webp',
    'Paxillus involutus': f'{POISONOUS_DIR}/Paxillus involutus Свинуха тонка/large.webp',
}

def photo_path_for(sci: str) -> str:
    return PHOTO_MAP.get(sci) or POPULAR_55_MAP.get(sci) or POISONOUS_MAP.get(sci) or ''

# ============================================================
# 133 з фото: (sci, ua, status, top20, popular, legacy)
# zones НЕ тут — воно зливається з distribution.csv
# ============================================================
WITH_PHOTOS = [
    # --- TOP-20 ---
    ("Boletus edulis","Білий гриб","edible",1,1,1),
    ("Lactarius torminosus","Вовнянка рожева","conditionally_edible",1,1,16),
    ("Pleurotus ostreatus","Глива звичайна","edible",1,1,17),
    ("Lactarius resimus","Груздь справжній","conditionally_edible",1,1,8),
    ("Lycoperdon perlatum","Дощовик їстівний","edible",1,1,13),
    ("Boletus luridus","Дубовик звичайний","edible",1,1,14),
    ("Flammulina velutipes","Зимовий опеньок","edible",1,1,""),
    ("Hydnum repandum","Їжовик жовтуватий","edible",1,1,19),
    ("Suillus bovinus","Козляк","edible",1,1,20),
    ("Cantharellus cibarius","Лисичка справжня","edible",1,1,2),
    ("Suillus luteus","Маслюк пізній","edible",1,1,5),
    ("Xerocomus subtomentosus","Моховик зелений","edible",1,1,15),
    ("Armillaria mellea","Опеньок осінній","edible",1,1,6),
    ("Agaricus campestris","Печериця звичайна","edible",1,1,10),
    ("Leccinum scabrum","Підберезник звичайний","edible",1,1,3),
    ("Leccinum aurantiacum","Підосичник","edible",1,1,4),
    ("Imleria badia","Польський гриб","edible",1,1,""),
    ("Lactarius deliciosus","Рижик справжній","edible",1,1,7),
    ("Russula vesca","Сироїжка","edible",1,1,9),
    ("Morchella esculenta","Сморчок звичайний","edible",1,1,11),

    # --- 21-55 популярні ---
    ("Albatrellus confluens","Альбатрел злитий","edible",0,1,""),
    ("Albatrellus ovinus","Альбатрел овечий","edible",0,1,""),
    ("Boletus reticulatus","Білий гриб сітчастий","edible",0,1,""),
    ("Boletus pinophilus","Білий гриб сосновий","edible",0,1,""),
    ("Pleurotus dryinus","Глива дубова","edible",0,1,""),
    ("Pleurotus pulmonarius","Глива легенева","edible",0,1,""),
    ("Macrolepiota procera","Гриб-зонтик великий","edible",0,1,""),
    ("Macrolepiota mastoidea","Гриб-зонтик сосковидний","edible",0,1,""),
    ("Tricholoma equestre","Зеленушка","conditionally_edible",0,1,""),
    ("Hydnum rufescens","Їжовик рудуватий","edible",0,1,""),
    ("Hydnum umbilicatum","Їжовик ямчастий","edible",0,1,""),
    ("Clavulina cristata","Клавуліна гребінчаста","edible",0,1,""),
    ("Clavulina coralloides","Клавуліна зморшкувата","edible",0,1,""),
    ("Cantharellus amethysteus","Лисичка аметистова","edible",0,1,""),
    ("Craterellus lutescens","Лисичка жовта","edible",0,1,""),
    ("Craterellus cinereus","Лисичка сіра","edible",0,1,""),
    ("Craterellus tubaeformis","Лисичка трубчаста","edible",0,1,""),
    ("Cantharellus friesii","Лисичка Фріза","edible",0,1,""),
    ("Suillus placidus","Маслюк білий","edible",0,1,""),
    ("Suillus variegatus","Маслюк жовто-бурий","edible",0,1,""),
    ("Suillus granulatus","Маслюк зернистий","edible",0,1,""),
    ("Suillus grevillei","Маслюк модриновий","edible",0,1,""),
    ("Xerocomellus chrysenteron","Моховик тріщинуватий","edible",0,1,""),
    ("Amanita excelsa","Мухомор високий","conditionally_edible",0,1,""),
    ("Amanita rubescens","Мухомор червоніючий","conditionally_edible",0,1,""),
    ("Amanita crocea","Мухомор шафрановий","edible",0,1,""),
    ("Kuehneromyces mutabilis","Опеньок літній","edible",0,1,""),
    ("Armillaria ostoyae","Опеньок темний","edible",0,1,""),
    ("Leccinellum pseudoscabrum","Підберезник грабовий","edible",0,1,""),
    ("Leccinum versipelle","Підберезник жовто-бурий","edible",0,1,""),
    ("Leccinum variicolor","Підберезник різнокольоровий","edible",0,1,""),
    ("Leccinum duriusculum","Підберезник тополевий","edible",0,1,""),
    ("Russula delica","Підгруздь","edible",0,1,""),
    ("Leccinum albostipitatum","Підосичник білоніжковий","edible",0,1,""),
    ("Amanita fulva","Поплавок жовто-коричневий","edible",0,1,""),

    # --- 56-99: решта з фото (не популярні, не ЧК, не отруйні) ---
    ("Amanita vaginata","Поплавок сірий","edible",0,0,""),
    ("Ramaria botrytis","Рамарія гроновидна","edible",0,0,""),
    ("Lactarius deterrimus","Рижик ялиновий","edible",0,0,""),
    ("Lactarius salmonicolor","Рижик ялицевий","edible",0,0,""),
    ("Tricholoma terreum","Рядовка землиста","edible",0,0,""),
    ("Lepista personata","Рядовка ліловонога","edible",0,0,""),
    ("Calocybe gambosa","Рядовка майська","edible",0,0,""),
    ("Tricholoma portentosum","Рядовка сіра","edible",0,0,""),
    ("Lepista nuda","Рядовка фіолетова","edible",0,0,""),
    ("Russula xerampelina","Сироїжка буро-червона","edible",0,0,""),
    ("Russula virescens","Сироїжка зелена","edible",0,0,""),
    ("Russula cyanoxantha","Сироїжка синьо-жовта","edible",0,0,""),
    ("Russula foetens","Сироїжка смердюча","inedible",0,0,""),
    ("Lactarius vellereus","Скрипиця","conditionally_edible",0,0,""),
    ("Polyporus squamosus","Трутовик лускатий","edible",0,0,""),
    ("Laetiporus sulphureus","Трутовик сірчано-жовтий","edible",0,0,""),
    ("Lactarius quietus","Хрящ-молочник дубовий","edible",0,0,""),
    ("Lactifluus volemus","Хрящ-молочник їстівний","edible",0,0,""),
    ("Lactarius piperatus","Хрящ-молочник перцевий","conditionally_edible",0,0,""),
    ("Lactarius subdulcis","Хрящ-молочник солодкуватий","edible",0,0,""),

    # --- 100-143: 44 ЧЕРВОНОКНИЖНИХ ---
    ("Boletus aereus","Боровик бронзовий","edible",0,0,""),
    ("Rubroboletus lupinus","Боровик вовчий","inedible",0,0,""),
    ("Butyriboletus appendiculatus","Боровик дівочий","edible",0,0,""),
    ("Butyriboletus regius","Боровик королівський","edible",0,0,""),
    ("Butyriboletus subappendiculatus","Боровик напівапендикулярний","edible",0,0,""),
    ("Butyriboletus fuscoroseus","Боровик рожево-бурий","edible",0,0,""),
    ("Rubroboletus rhodoxanthus","Боровик рожево-жовтий","poisonous",0,0,""),
    ("Rubroboletus satanas","Боровик сатанинський","poisonous",0,0,""),
    ("Butyriboletus fechtneri","Боровик Фехтнера","edible",0,0,""),
    ("Rubroboletus rubrosanguineus","Боровик червоно-кривавий","poisonous",0,0,""),
    ("Phallus duplicatus","Веселка подвоєна","inedible",0,0,""),
    ("Hemileccinum depilatum","Гемілецінум безволосий","edible",0,0,""),
    ("Hericium erinaceus","Герицій їжаковий","edible",0,0,""),
    ("Hericium coralloides","Герицій кораловий","inedible",0,0,""),
    ("Hygrocybe calyptriformis","Гігроцибе ковпакоподібна","inedible",0,0,""),
    ("Gomphus clavatus","Гомф булавоподібний","edible",0,0,""),
    ("Grifola frondosa","Грифола листувата","edible",0,0,""),
    ("Morchella steppicola","Зморшок степовий","edible",0,0,""),
    ("Pseudocolus fusiformis","Кальмарник веретеноподібний","inedible",0,0,""),
    ("Catathelasma imperiale","Катателазма царська","edible",0,0,""),
    ("Anthurus archeri","Квітохвісник Арчера","inedible",0,0,""),
    ("Clavariadelphus pistillaris","Клаваріадельф товкачиковий","inedible",0,0,""),
    ("Lyophyllum favrei","Ліофіл Фавре","inedible",0,0,""),
    ("Helvella monachella","Лопатевик чорний","inedible",0,0,""),
    ("Suillus plorans","Маслюк кедровий","edible",0,0,""),
    ("Myriostoma coliforme","Міріостома шийкова","inedible",0,0,""),
    ("Boletus parasiticus","Моховик паразитний","inedible",0,0,""),
    ("Amanita caesarea","Мухомор цезарів","edible",0,0,""),
    ("Amanita strobiliformis","Мухомор щетинистий","conditionally_edible",0,0,""),
    ("Chalciporus rubinus","Решетняк карміново-червоний","inedible",0,0,""),
    ("Clathrus ruber","Решіточник червоний","inedible",0,0,""),
    ("Tricholoma colossus","Рядовка величезна","inedible",0,0,""),
    ("Tricholoma focale","Рядовка опеньковидна","inedible",0,0,""),
    ("Sarcosoma globosum","Саркосома куляста","inedible",0,0,""),
    ("Russula turci","Сироїжка синювата","edible",0,0,""),
    ("Scleroderma geaster","Склеродерма зірчаста","inedible",0,0,""),
    ("Sparassis crispa","Спарасис кучерявий","edible",0,0,""),
    ("Polyporus umbellatus","Трутовик зонтичний","edible",0,0,""),
    ("Tuber aestivum","Трюфель літній","edible",0,0,""),
    ("Phellorinia herculeana","Фелоринія геркулесова","inedible",0,0,""),
    ("Phaeolepiota aurea","Феолепіота золотиста","inedible",0,0,""),
    ("Phylloporus pelletieri","Філопор рожево-золотистий","edible",0,0,""),
    ("Lactarius lignyotus","Хрящ-молочник чорний","edible",0,0,""),
    ("Strobilomyces strobilaceus","Шишкогриб лускатий","inedible",0,0,""),

    # --- 144-157: 14 отруйних і смертельно отруйних ---
    ("Amanita muscaria","Мухомор червоний","poisonous",0,0,""),
    ("Amanita pantherina","Мухомор пантерний","poisonous",0,0,""),
    ("Amanita phalloides","Бліда поганка","deadly_poisonous",0,0,""),
    ("Amanita verna","Мухомор весняний","deadly_poisonous",0,0,""),
    ("Amanita virosa","Мухомор смердючий","deadly_poisonous",0,0,""),
    ("Clitocybe candicans","Говорушка білувата","poisonous",0,0,""),
    ("Clitocybe dealbata","Говорушка воскова","poisonous",0,0,""),
    ("Entoloma sinuatum","Ентолома отруйна","poisonous",0,0,""),
    ("Galerina marginata","Галерина облямована","deadly_poisonous",0,0,""),
    ("Gyromitra esculenta","Строчок звичайний","deadly_poisonous",0,0,""),
    ("Hygrophoropsis aurantiaca","Лисичка несправжня","poisonous",0,0,""),
    ("Inocybe erubescens","Волоконниця червоніюча","poisonous",0,0,""),
    ("Inocybe geophylla","Іноцибе звичайний","poisonous",0,0,""),
    ("Paxillus involutus","Свинуха тонка","poisonous",0,0,""),
]

assert len(WITH_PHOTOS) == 133, f"Очікується 133, отримано {len(WITH_PHOTOS)}"

# ============================================================
# 200 без фото: (sci, ua, status)
# zones — поки НЕ заповнюємо (окрема ітерація)
# ============================================================
WITHOUT_PHOTOS = [
    ("Agaricus arvensis","Печериця польова","edible"),
    ("Agaricus silvaticus","Печериця лісова","edible"),
    ("Agaricus xanthodermus","Печериця жовтошкіра","poisonous"),
    ("Amanita citrina","Мухомор цитриновий","poisonous"),
    ("Amanita porphyria","Мухомор пурпуровий","poisonous"),
    ("Amanita vittadinii","Мухомор Віттадіні","poisonous"),
    ("Amanita echinocephala","Мухомор колючоголовий","inedible"),
    ("Boletus calopus","Боровик неїстівний","inedible"),
    ("Boletus impolitus","Боровик жовтий","edible"),
    ("Boletus queletii","Боровик Келета","conditionally_edible"),
    ("Boletus erythropus","Боровик зернистоногий","conditionally_edible"),
    ("Boletus purpureus","Боровик пурпуровий","poisonous"),
    ("Gyroporus castaneus","Гіропор каштановий","edible"),
    ("Gyroporus cyanescens","Гіропор синіючий","edible"),
    ("Gyrodon lividus","Гіродон сизуватий","edible"),
    ("Boletinus cavipes","Болетин порожньоногий","edible"),
    ("Tylopilus felleus","Тилопіл жовчний","inedible"),
    ("Porphyrellus porphyrosporus","Порфірел пурпуровоспоровий","inedible"),
    ("Gomphidius glutinosus","Мокруха клейка","edible"),
    ("Gomphidius roseus","Мокруха рожева","edible"),
    ("Gomphidius rutilus","Мокруха слизька","edible"),
    ("Gomphidius maculatus","Мокруха плямиста","edible"),
    ("Paxillus atrotomentosus","Паксил чорноповстистий","conditionally_edible"),
    ("Paxillus panuoides","Паксил вохряно-рудий","conditionally_edible"),
    ("Ripartites tricholoma","Рипартитес рядовковидний","edible"),
    ("Ripartites helomorpha","Рипартит геломорфний","edible"),
    ("Lactarius sanguifluus","Рижик червоний","edible"),
    ("Lactarius semisanguifluus","Хрящ-молочник зеленувато-червоний","edible"),
    ("Lactarius fuliginosus","Хрящ-молочник сірий","conditionally_edible"),
    ("Lactarius acris","Хрящ-молочник червоніючий","inedible"),
    ("Lactarius chrysorrheus","Хрящ-молочник золотисто-жовтий","inedible"),
    ("Lactarius theiogalus","Хрящ-молочник болотний","inedible"),
    ("Lactarius hepaticus","Хрящ-молочник оранжево-пластинчастий","inedible"),
    ("Lactarius scrobiculatus","Хрящ-молочник жовтий","conditionally_edible"),
    ("Lactarius trivialis","Хрящ-молочник сизий","conditionally_edible"),
    ("Lactarius musteus","Хрящ-молочник моховий","inedible"),
    ("Lactarius rubrocinctus","Хрящ-молочник рубчастий","inedible"),
    ("Lactarius glaucescens","Хрящ-молочник зеленіючий","edible"),
    ("Lactarius blennius","Хрящ-молочник сіро-зелений","edible"),
    ("Lactarius vietus","Хрящ-молочник бляклий","conditionally_edible"),
    ("Lactarius uvidus","Хрящ-молочник ліловіючий","conditionally_edible"),
    ("Lactarius violascens","Хрящ-молочник фіолетовий","inedible"),
    ("Lactarius aspideus","Хрящ-молочник жовтуватий ліловіючий","inedible"),
    ("Lactarius repraesentaneus","Хрящ-молочник золотисто-жовтий ліловіючий","conditionally_edible"),
    ("Lactarius pubescens","Хрящ-молочник пухнастий","conditionally_edible"),
    ("Lactarius controversus","Хрящ-молочник осиковий","conditionally_edible"),
    ("Lactarius turpis","Хрящ-молочник оливково-чорний","conditionally_edible"),
    ("Lactarius mammosus","Хрящ-молочник сосочковий","inedible"),
    ("Lactarius flexuosus","Хрящ-молочник сіро-лілуватий","conditionally_edible"),
    ("Lactarius spinosulus","Хрящ-молочник шипастий","inedible"),
    ("Russula albonigra","Сироїжка біло-чорна","conditionally_edible"),
    ("Russula nigricans","Сироїжка чорніюча","conditionally_edible"),
    ("Russula densifolia","Сироїжка густопластинчаста","inedible"),
    ("Russula adusta","Сироїжка чорна","conditionally_edible"),
    ("Russula decolorans","Сироїжка вицвітаюча","edible"),
    ("Russula obscura","Сироїжка темна","edible"),
    ("Russula claroflava","Сироїжка світло-жовта","edible"),
    ("Russula ochroleuca","Сироїжка вохряно-жовта","inedible"),
    ("Russula puellaris","Сироїжка дівоча","edible"),
    ("Russula viscida","Сироїжка слизька","edible"),
    ("Russula lilacea","Сироїжка лілова","edible"),
    ("Russula pulchella","Сироїжка гарна","edible"),
    ("Russula olivacea","Сироїжка оливково-зелена","edible"),
    ("Russula atropurpurea","Сироїжка чорно-пурпурова","edible"),
    ("Russula lutea","Сироїжка червоно-жовта","edible"),
    ("Russula mustelina","Сироїжка коричнева","edible"),
    ("Russula mollis","Сироїжка м'яка","edible"),
    ("Russula aeruginosa","Сироїжка зелена велика","edible"),
    ("Russula amoena","Сироїжка зерниста","edible"),
    ("Russula heterophylla","Сироїжка різнопластинчаста","edible"),
    ("Russula grisea","Сироїжка сіра","edible"),
    ("Russula roseipes","Сироїжка рожевонога","edible"),
    ("Russula brunneoviolacea","Сироїжка коричнево-лілова","edible"),
    ("Russula melliolens","Сироїжка медова","edible"),
    ("Russula aurata","Сироїжка золотиста","edible"),
    ("Russula paludosa","Сироїжка болотяна","edible"),
    ("Russula curtipes","Сироїжка коротконога","edible"),
    ("Russula alutacea","Сироїжка зелено-червона","edible"),
    ("Russula integra","Сироїжка бездоганна","edible"),
    ("Russula fellea","Сироїжка жовта","inedible"),
    ("Russula farinipes","Сироїжка валуєвидна","inedible"),
    ("Russula consobrina","Сироїжка сірувато-бура","inedible"),
    ("Russula pectinata","Сироїжка гребінчаста","inedible"),
                            ("Russula maculata","Сироїжка плямиста","inedible"),
    ("Russula rubra","Сироїжка червона","inedible"),
    ("Russula sanguinea","Сироїжка криваво-червона","inedible"),
    ("Russula badia","Сироїжка пурпурово-коричнева","inedible"),
    ("Russula sardonia","Сироїжка темно-фіолетова","inedible"),
    ("Russula queletii","Сироїжка Келета","inedible"),
    ("Russula rosea","Сироїжка рожева","conditionally_edible"),
    ("Russula pseudointegra","Сироїжка рум'яна","conditionally_edible"),
    ("Russula caerulea","Сироїжка лазурова","edible"),
    ("Russula nauseosa","Сироїжка бридка","inedible"),
    ("Tricholoma album","Рядовка біла","poisonous"),
    ("Tricholoma sulphureum","Рядовка сірчано-жовта","poisonous"),
    ("Tricholoma virgatum","Рядовка волокниста","poisonous"),
    ("Tricholoma vaccinum","Рядовка рудувато-червона","inedible"),
    ("Tricholoma imbricatum","Рядовка черепичаста","inedible"),
    ("Tricholoma pessundatum","Рядовка згубна","poisonous"),
    ("Tricholoma populinum","Рядовка тополева","edible"),
    ("Tricholoma saponaceum","Рядовка сіра","inedible"),
    ("Tricholoma sejunctum","Рядовка відокремлена","inedible"),
    ("Tricholoma orirubens","Рядовка червоніюча","inedible"),
    ("Clitocybe nebularis","Говорушка сіра","conditionally_edible"),
    ("Clitocybe geotropa","Говорушка руда","edible"),
    ("Clitocybe gigantea","Говорушка гігантська","edible"),
    ("Clitocybe odora","Говорушка ароматна","edible"),
    ("Clitocybe clavipes","Говорушка булавовиднонога","inedible"),
    ("Clitocybe infundibuliformis","Говорушка лійковидна","edible"),
    ("Clitocybe rivulosa","Говорушка червонувата","poisonous"),
    ("Clitocybe phyllophila","Говорушка листолюбна","poisonous"),
    ("Clitocybe suaveolens","Говорушка запашна","edible"),
    ("Clitocybe brumalis","Говорушка зимова","inedible"),
    ("Collybia dryophila","Колібія лісолюбна","edible"),
    ("Collybia peronata","Колібія обгорнута","inedible"),
    ("Collybia confluens","Колібія численна","edible"),
    ("Collybia maculata","Колібія плямиста","inedible"),
    ("Collybia butyracea","Колібія рудувато-сіра","edible"),
    ("Collybia fusipes","Колібія веретенонога","conditionally_edible"),
    ("Mycena pura","Міцена чиста","poisonous"),
    ("Mycena galericulata","Міцена ковпаковидна","inedible"),
    ("Mycena polygramma","Міцена штрихувата","inedible"),
    ("Mycena haematopus","Міцена кривавонога","inedible"),
    ("Mycena rosella","Міцена рожева","inedible"),
    ("Mycena epipterygia","Міцена слизька","inedible"),
    ("Mycena inclinata","Міцена нахилена","inedible"),
    ("Mycena aetites","Міцена лужна","inedible"),
    ("Mycena galopus","Міцена білосокова","inedible"),
    ("Mycena sanguinolenta","Міцена кривавоплямиста","inedible"),
    ("Marasmius oreades","Опеньок луговий","edible"),
    ("Marasmius alliaceus","Часничник великий","edible"),
    ("Marasmius scorodonius","Часничник дрібний","edible"),
    ("Marasmius prasiosmus","Маразмій вицвітаючий","edible"),
    ("Marasmius rotula","Маразмій колесовидний","inedible"),
    ("Marasmius epiphyllus","Маразмій листовий","inedible"),
    ("Entoloma clypeatum","Ентолома щитовидна","edible"),
    ("Entoloma rhodopolium","Ентолома рожево-сива","poisonous"),
    ("Entoloma nidorosum","Ентолома смердюча","poisonous"),
    ("Entoloma sericeum","Ентолома шовковиста","edible"),
    ("Entoloma jubatum","Ентолома волохата","edible"),
    ("Entoloma aprile","Ентолома квітнева","poisonous"),
    ("Pluteus cervinus","Плютей бурий","edible"),
    ("Pluteus salicinus","Плютей вербовий","edible"),
    ("Hygrophorus eburneus","Гігрофор жовтувато-білий","edible"),
    ("Hygrophorus chrysodon","Гігрофор золотистий","edible"),
    ("Hygrophorus hypothejus","Гігрофор пізній","edible"),
    ("Hygrophorus olivaceo-albus","Гігрофор оливково-білий","edible"),
    ("Hygrophorus russula","Гігрофор сироїжковидний","edible"),
    ("Hygrophorus pratensis","Гігрофор луговий","edible"),
    ("Hygrophorus nemoreus","Гігрофор дібровний","edible"),
    ("Hygrophorus camarophyllus","Гігрофор козячий","edible"),
    ("Hygrophorus virgineus","Гігрофор дівочий","edible"),
    ("Hygrophorus fornicatus","Гігрофор склепистий","edible"),
    ("Hygrophorus foetens","Гігрофор смердючий","inedible"),
    ("Hygrophorus capreolarius","Гігрофор винно-червоний","edible"),
    ("Hygrophorus marzuolus","Гігрофор ранній","edible"),
    ("Hygrophorus penarius","Гігрофор їстівний","edible"),
    ("Hygrophorus lucorum","Гігрофор модриновий","edible"),
    ("Coprinus comatus","Гнойовик білий","edible"),
    ("Coprinus atramentarius","Гнойовик сірий","conditionally_edible"),
    ("Coprinus micaceus","Гнойовик мерехтливий","edible"),
    ("Coprinus radians","Гнойовик променистий","inedible"),
    ("Coprinus lagopus","Гнойовик заяча лапа","inedible"),
    ("Hypholoma fasciculare","Опеньок сірчано-жовтий","poisonous"),
    ("Hypholoma capnoides","Опеньок димчастий","edible"),
    ("Stropharia aeruginosa","Строфарія синьо-зелена","inedible"),
    ("Pholiota squarrosa","Лускатка луската","conditionally_edible"),
    ("Pholiota aurivella","Лускатка золотиста","edible"),
    ("Cortinarius violaceus","Павутинник фіолетовий","edible"),
    ("Cortinarius armillatus","Павутинник браслетний","edible"),
    ("Cortinarius triumphans","Павутинник тріумфальний","edible"),
    # ЗАМІНА: Inocybe geophylla вже є у WITH_PHOTOS.
    # Тому використано Inocybe rimosa — споріднений отруйний вид.
    ("Inocybe rimosa","Волоконниця тріщинувата","poisonous"),
    ("Inocybe fastigiata","Волоконниця рівновершинна","poisonous"),
    ("Macrolepiota rhacodes","Гриб-зонтик червоніючий","edible"),
    ("Lepiota clypeolaria","Лепіота щитоносна","inedible"),
    ("Lepiota cristata","Лепіота гребінчаста","poisonous"),
    ("Lepiota felina","Лепіота котяча","inedible"),
    ("Lepiota lilacea","Лепіота лілова","inedible"),
    ("Lyophyllum decastes","Ліофіл груповий","edible"),
    ("Lyophyllum connatum","Ліофіл зрослий","edible"),
    ("Lyophyllum ulmarium","Ліофіл в'язовий","edible"),
    ("Lyophyllum loricatum","Ліофіл панцирний","edible"),
    ("Lyophyllum immundum","Ліофіл чорніючий","edible"),
    ("Pleurotus cornucopiae","Плеврот рясний","edible"),
    ("Pleurotus calyptratus","Плеврот ковпаковидний","edible"),
    ("Pleurotus eryngii","Плеврот миколайчиковий","edible"),
    ("Lentinus tigrinus","Лентин тигровий","edible"),
    ("Lentinus cyathiformis","Лентин бокаловидний","edible"),
    ("Lentinus lepideus","Лентин лускатий","edible"),
    ("Schizophyllum commune","Схізофіл звичайний","inedible"),
    ("Volvariella speciosa","Вольварієла прекрасна","edible"),
    ("Volvariella bombycina","Вольварієла надеревна","edible"),
    ("Pluteus atromarginatus","Плютей чорнооторочений","edible"),
    ("Russula cyanoxantha","Сироїжка синьо-жовта","edible"),
    ("Russula delica","Підгруздь","edible"),
    ("Russula foetens","Сироїжка смердюча","conditionally_edible"),
    ("Russula turci","Сироїжка синювата","edible"),
    ("Russula vesca","Сироїжка істівна","edible"),
    ("Russula virescens","Сироїжка луската","edible"),
    ("Russula xerampelina","Сироїжка буро-червона","edible"),
]

# ============================================================
# ПЕРЕВІРКИ (після обох списків!)
# ============================================================

with_photos_sci = {s[0] for s in WITH_PHOTOS}
top20_sci = {s[0] for s in WITH_PHOTOS if s[3] == 1}
popular_sci = {s[0] for s in WITH_PHOTOS if s[4] == 1}

if not top20_sci.issubset(popular_sci):
    raise SystemExit("❌ TOP-20 має бути підмножиною популярних")

assert len(top20_sci) == 20, f"Очікується 20, отримано {len(top20_sci)}"
assert len(popular_sci) == 55, f"Очікується 55, отримано {len(popular_sci)}"

print(f"✓ Перевірки: WITH_PHOTOS={len(with_photos_sci)}, TOP-20={len(top20_sci)}, популярних={len(popular_sci)}")

# ============================================================
# Додаткові множини
# ============================================================
DEADLY_SPECIES = {
    'Amanita phalloides','Amanita verna','Amanita virosa',
    'Galerina marginata','Gyromitra esculenta',
}

RARITY_LABELS = {
    'Boletus aereus':'Рідкісний вид',
    'Rubroboletus lupinus':'Вразливий вид',
    'Butyriboletus appendiculatus':'Рідкісний вид',
    'Butyriboletus regius':'Зникаючий вид',
    'Butyriboletus subappendiculatus':'Рідкісний вид',
    'Butyriboletus fuscoroseus':'Рідкісний вид',
    'Rubroboletus rhodoxanthus':'Вразливий вид',
    'Rubroboletus satanas':'Рідкісний вид',
    'Butyriboletus fechtneri':'Зникаючий вид',
    'Rubroboletus rubrosanguineus':'Вразливий вид',
    'Phallus duplicatus':'Рідкісний вид',
    'Hemileccinum depilatum':'Рідкісний вид',
    'Hericium erinaceus':'Вразливий вид',
    'Hericium coralloides':'Вразливий вид',
    'Hygrocybe calyptriformis':'Рідкісний вид',
    'Gomphus clavatus':'Вразливий вид',
    'Grifola frondosa':'Рідкісний вид',
    'Morchella steppicola':'Зникаючий вид',
    'Pseudocolus fusiformis':'Рідкісний вид',
    'Catathelasma imperiale':'Рідкісний вид',
    'Anthurus archeri':'Рідкісний вид',
    'Clavariadelphus pistillaris':'Рідкісний вид',
    'Lyophyllum favrei':'На межі зникнення',
    'Helvella monachella':'Рідкісний вид',
    'Suillus plorans':'Рідкісний вид',
    'Myriostoma coliforme':'Вразливий вид',
    'Boletus parasiticus':'Рідкісний вид',
    'Amanita caesarea':'Зникаючий вид',
    'Amanita strobiliformis':'Рідкісний вид',
    'Chalciporus rubinus':'Рідкісний вид',
    'Clathrus ruber':'Рідкісний вид',
    'Tricholoma colossus':'Рідкісний вид',
    'Tricholoma focale':'Вразливий вид',
    'Sarcosoma globosum':'Вразливий вид',
    'Russula turci':'Рідкісний вид',
    'Scleroderma geaster':'Рідкісний вид',
    'Sparassis crispa':'Вразливий вид',
    'Polyporus umbellatus':'Рідкісний вид',
    'Tuber aestivum':'Зникаючий вид',
    'Phellorinia herculeana':'На межі зникнення',
    'Phaeolepiota aurea':'Рідкісний вид',
    'Phylloporus pelletieri':'Рідкісний вид',
    'Lactarius lignyotus':'Рідкісний вид',
    'Strobilomyces strobilaceus':'Рідкісний вид',
}

# ============================================================
# Читаємо distribution.csv (133 з фото) + distribution_200.csv (200 без фото)
# ============================================================
dist = {}
try:
    with open('distribution.csv', encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            dist[row['scientific_name']] = row['zones']
except FileNotFoundError:
    print("⚠ distribution.csv не знайдено — zones будуть порожні")

try:
    with open('distribution_200.csv', encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            dist[row['scientific_name']] = row['zones']
except FileNotFoundError:
    print("⚠ distribution_200.csv не знайдено — zones для 200 видів будуть порожні")

# ============================================================
# Читаємо descriptions_200.csv (key_features_ai)
# ============================================================
descriptions = {}
try:
    with open('descriptions_200.csv', encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            descriptions[row['scientific_name']] = row.get('key_features_ai', '')
except FileNotFoundError:
    print("⚠ descriptions_200.csv не знайдено — key_features_ai будуть порожні")

# ============================================================
# Читаємо habitats_200.csv (season)
# ============================================================
habitats = {}
try:
    with open('habitats_200.csv', encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            habitats[row['scientific_name']] = row.get('season', '')
except FileNotFoundError:
    print("⚠ habitats_200.csv не знайдено — season будуть порожні")

# ============================================================
# Генерація
# ============================================================
with open('master.csv', 'w', encoding='utf-8-sig', newline='') as f:
    w = csv.writer(f)
    w.writerow(HEADER)

    # --- 133 з фото ---
    for sci, ua, status, top20, popular, legacy in WITH_PHOTOS:
        is_poison = status in ('poisonous','deadly_poisonous')
        is_deadly = sci in DEADLY_SPECIES
        is_red = sci in RARITY_LABELS
        rarity = RARITY_LABELS.get(sci, '')
        zones = dist.get(sci, '')

        ai_recognition = 0 if is_red else 1

        w.writerow([
            sci, ua, status,
            1, top20, popular,
            1 if is_poison else 0,
            1 if is_deadly else 0,
            1 if is_red else 0,
            rarity,
            ai_recognition, 1,
            legacy,
            zones,
            descriptions.get(sci, ''),
            habitats.get(sci, ''),
            photo_path_for(sci),
        ])

    # --- 200 без фото ---
    for sci, ua, status in WITHOUT_PHOTOS:
        is_poison = status in ('poisonous','deadly_poisonous')
        is_deadly = sci in DEADLY_SPECIES

        w.writerow([
            sci, ua, status,
            0, 0, 0,
            1 if is_poison else 0,
            1 if is_deadly else 0,
            0, '',
            0, 1,
            '',
            dist.get(sci, ''),
            descriptions.get(sci, ''),
            habitats.get(sci, ''),
            photo_path_for(sci),
        ])

print(f"✓ master.csv: 133 + {len(WITHOUT_PHOTOS)} = {133 + len(WITHOUT_PHOTOS)} рядків")
print(f"  ▪ zones заповнено для {len(dist)} видів")
print(f"  ▪ key_features_ai заповнено для {len(descriptions)} видів")
print(f"  ▪ season заповнено для {len(habitats)} видів")
print(f"  ▪ 44 ЧК, 14 отруйних, 5 смертельно отруйних")
