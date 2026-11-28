# Стікери «Швидкої картки» довідника

Мальовані стікери ознак гриба біля рядків «Швидка картка (як визначити)» / «Як упізнати».
Картинки згенерував і передав власник проєкту для «Грибного Радара» (2026-11-27, три набори); тут —
лише технічна обробка: прозоре тло без «пилу», обрізка полів, квадрат 256×256, WebP.

| Файл | Що показує | Коли показується (`passportSticker`) |
|---|---|---|
| under_gills | пластинки | «Пластинки», «Низ шапки» з пластинками (білі — висвітлений) |
| under_tubes | трубочки / губка з порами | «Низ шапки (Трубочки)», «Трубчастий…» |
| under_folds | складки, що спускаються на ніжку | «Низ шапки (Складки)», «Гіменофор: складки…» |
| under_spines | шипи | «Низ шапки (Шипи)», «Шипастий (голчастий)» |
| stem_ring | кільце на ніжці | «Ніжка … з кільцем», «Кільце» |
| stem_volva | вольва («мішечок») | «Ніжка … вольва/піхва», «Основа … вольва» |
| stem_net | сіточка на ніжці | «Ніжка … сіточка/сітка» |
| stem_scales | темні лусочки на ніжці | «Ніжка … лусочками» |
| flesh_white | зріз не змінює кольору | «М'якоть … не змінює колір / не синіє», «М'якоть: біла…» |
| flesh_blue | зріз синіє | «М'якоть … синіє» |
| flesh_red | зріз червоніє / рожевіє | «М'якоть … червоніє / рожевіє» |
| flesh_dark | зріз темніє | «М'якоть … темніє / чорніє / сіріє» (дієслово; «темніша» — ні) |
| milk | молочний сік на зламі | «Молочний сік», «М'якоть … молочний сік» |
| spores_brown | коричневий відбиток спор | «Споровий порошок: коричневий / бурий / іржавий» |
| smell | понюхати гриб | «Запах» |
| taste | смак кінчиком язика | «Смак» |
| place_tree | під деревом | «Місце зростання … ліс / під березою …» |
| place_wood | на пні, деревині | «Місце зростання … пні / деревина / стовбури» |
| place_meadow | луки, галявина | «Місце зростання … луки / пасовища / галявини» |
| key_feature | лупа з галочкою | «Ключова ознака», «Головне правило» |
| cap_white / cap_yellow / cap_brown / cap_olive | шапка кольору | «Шапка» / «Капелюх» — за першим названим кольором |
| cap_red | червона шапка з пластівцями | лише коли в тексті є пластівці (мухомор); червона без пластівців — `cap_red_plain` (нижче) |
| cap_neutral | нейтральна шапка | «Шапка» без названого кольору |
| spores_white / pink / yellow / dark | відбиток спор кольору | «Споровий порошок»: темний → коричневий → рожевий → жовтий/оливковий → білий |
| place_pine / place_oak / place_spruce | під сосною (і хвойні) / дубом / ялиною | «Місце зростання», «Ліс/місце» — конкретне дерево, що згадано першим |
| flesh_green | зріз зеленіє | «М'якоть … зеленіє» (рижик) — раніше за молочний сік |

Зміна кольору зрізу й місце зростання — та, що згадана в тексті першою («темніє до синювато-чорної» → темніє).
Заперечення («Кільця немає», «без кільця та піхви», «не синіє») стікер не вмикають.
Немає ознаки в тексті — лишається схематичний значок.

## Четвертий набір (2026-11-28): форма, ніжка без кільця, дощовик, корал

Намальовані власником за промтами нижче, оброблені так само (прозоре тло, 256×256, WebP). Після них без стікера
лишилося 6 рядків із 437 (мікроскопія спор, сезон, «Гіменофор: відсутній», ніжка/м'якоть дощовика, сіра м'якоть).
Новий стікер додається так: правило в `passportStickerRule`, файл у `assets/stickers/passport/`, підпис у
`passportStickers`; поки файлу немає — `_stickerFallback` або схема.

| Файл | Коли | Запасний (до малюнка) |
|---|---|---|
| stem_plain | «Ніжка» без кільця/вольви/сіточки/лусочок, біла | схема |
| stem_colored | те саме, але колір названо («кольору шапки», «одного кольору з шапкою», жовта…); без кольору — схема | схема |
| stem_hollow | «Ніжка … порожниста / з порожниною» | схема |
| stem_side | «Ніжка … бічна / ексцентрична / зміщена / майже відсутня» | схема |
| stem_granules | «Ніжка … зерниста / крапками / бородавками» (маслюки) | схема |
| cap_red_plain | червона шапка без пластівців (сироїжки, підосичники) | схема |
| cap_grey | сіра шапка (рядовка сіра, поплавок) | cap_neutral |
| cap_funnel | «лійкоподібна», жовта/оранжева (лисички, рижики) | cap_yellow |
| cap_funnel_white | «лійкоподібна», біла (грузді, скрипиця) | cap_white |
| cap_funnel_dark | «лійкоподібна», бура/сіра (лисичка сіра, трубчаста) | cap_brown |
| cap_morel | «ячеиста / комірчаста» (сморчок) | схема |
| cap_brain | «мозкоподібна / звивиста» (строчок) | схема |
| cap_oyster | «віялоподібна / черепашковидна», не жовта (гливи) | схема |
| cap_bracket | те саме, жовта (трутовик сірчано-жовтий, лускатий) | схема |
| body_puffball | «Плодове тіло: кулясте / грушоподібне» | схема |
| body_coral | «Плодове тіло: кораловидне / кущовидне» | схема |
| spores_puff | «Спорова маса» (дощовик) | схема |
| flesh_yellow | «М'якоть: жовта / оранжева …» без зміни на зрізі | схема |

Ще в цьому наборі правил: «• Шапка» (маркер списку) читається як «Шапка»; «Складочки (не пластинки!)» → складки;
у складеному кольорі головний — останній («червоно-коричнева» → коричнева, «сірувато- або брудно-жовта» → жовта);
«здебільшого» — не «білий»; «буріє на зрізі» → зріз темніє; «стружка» на ніжці → лусочки; «червоніє при дотику» → зріз червоніє;
«Споровий порошок: охряний» → жовтуватий.

### Промти (кожен окремо, одна картинка на промт)

#### 35. Ніжка — гладка, біла — `stem_plain`
Видно: цілий гриб збоку; головне — гладка біла ніжка без кільця, вольви, сіточки й лусочок.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a whole mushroom standing upright, seen from the side. The STEM is the main feature and takes most of the picture: tall, smooth, cylindrical, PURE WHITE to light cream, with NO ring, NO skirt, NO net pattern, NO scales and NO sack at the base. The cap on top is small, simple and pale beige. The plain smooth white stem must be clearly visible.
```

#### 36. Ніжка — гладка, кольору шапки — `stem_colored`
Видно: цілий гриб збоку; ніжка гладка, жовто-бура, як шапка.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a whole mushroom standing upright, seen from the side. The STEM is the main feature and takes most of the picture: smooth, cylindrical, YELLOW-BROWN, the same color as the small brown cap on top, with NO ring, NO skirt, NO net pattern, NO scales and NO sack at the base. The plain colored stem must be clearly visible.
```

#### 37. Ніжка — порожниста всередині — `stem_hollow`
Видно: гриб, розрізаний уздовж; у ніжці видно порожнину-трубку.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a mushroom CUT IN HALF LENGTHWISE, the cut surface facing the viewer. The STEM is clearly HOLLOW inside: an empty tube-like cavity runs down the middle of the stem, with thin flesh walls around it. The cap is simple and light brown. A small knife lies next to it. The hollow empty stem must be the main, clearly visible feature.
```

#### 38. Ніжка — збоку, коротка — `stem_side`
Видно: гриб, у якого коротка ніжка прикріплена не посередині, а з краю шапки.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a single mushroom with an irregular, slightly fan-shaped cream-white cap, seen from the side and slightly from below. A SHORT THICK STEM is attached OFF-CENTER, near the EDGE of the cap, not in the middle. The off-center side stem must be the main, clearly visible feature.
```

#### 39. Ніжка — у дрібних зернятках (маслюки) — `stem_granules`
Видно: світло-жовта ніжка, усипана дрібними темними цятками-зернятками; кільця немає.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a whole mushroom standing upright, seen from the side, with a glossy brown slimy cap. The STEM is the main feature: pale yellow, covered with many TINY DARK BROWN DOTS and granules, densest in the upper part, with NO ring. The dotted granular stem must be clearly visible.
```

#### 40. Шапка — червона, БЕЗ пластівців (сироїжка) — `cap_red_plain`
Видно: червона гладенька шапка без жодних білих пластівців — щоб не плутати з мухомором.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a single mushroom CAP seen from the side and slightly from above. The cap is BRIGHT RED to brick-red, smooth and slightly shiny, completely CLEAN: NO white flakes, NO spots, NO warts. Only a very short white stub of the stem under it. No gills visible. The clean red cap without any flakes must be the main, clearly visible feature.
```

#### 41. Шапка — сіра — `cap_grey`
Видно: мишачо-сіра шапка (рядовка сіра, поплавок сірий).
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a single mushroom CAP seen from the side and slightly from above. The cap is MOUSE-GREY to ash-grey with fine darker radial fibres on its surface. Only a very short stub of the stem under it. No gills visible. The grey cap color must be the main, clearly visible feature.
```

#### 42. Шапка — лійка, жовто-оранжева (лисичка) — `cap_funnel`
Видно: жовта шапка-лійка з хвилястим краєм, плавно переходить у ніжку.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a single mushroom seen from the side and slightly from above. The cap is shaped like a FUNNEL or a shallow vase: the center is sunken, the edge is WAVY and slightly rolled. The color is EGG-YOLK YELLOW to orange. The cap flows smoothly into a short stem. The underside is not visible. The yellow funnel shape must be the main, clearly visible feature.
```

#### 43. Шапка — лійка, біла (груздь) — `cap_funnel_white`
Видно: велика біла шапка-лійка з підвернутим краєм.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a single large mushroom seen from the side and slightly from above. The cap is WHITE to cream, shaped like a wide FUNNEL with a deeply sunken center and the edge slightly rolled down, dry matte surface, soft grey shadows so it stands out from the white sticker border. Short thick white stem. The underside is not visible. The white funnel cap must be the main, clearly visible feature.
```

#### 44. Шапка — сіро-бура труба (лисичка сіра, трубчаста) — `cap_funnel_dark`
Видно: глибока лійка-труба сіро-бурого кольору, отвір у центрі йде в ніжку.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a single TRUMPET-shaped mushroom seen from the side and slightly from above: a deep funnel whose hollow center opens down into the stem, thin wavy edge. The color is GREY-BROWN to dark ash-grey. The trumpet shape must be the main, clearly visible feature.
```

#### 45. Шапка — сморчок (комірки) — `cap_morel`
Видно: яйцеподібна шапка з глибокими комірками, як стільники.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a MOREL mushroom standing upright, seen from the side. The cap is egg-shaped to conical and covered with a HONEYCOMB pattern of deep pits separated by sharp ridges, yellow-brown. Short thick whitish stem. The honeycomb pits must be the main, clearly visible feature.
```

#### 46. Шапинка — строчок (мозок, ОТРУЙНИЙ) — `cap_brain`
Видно: шапинка звивиста, як мозок або ядро волоського горіха, без комірок.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a FALSE MOREL mushroom seen from the side. The cap is irregular, wrinkled and folded like a BRAIN or a walnut kernel, dark red-brown, with NO honeycomb pits, on a short whitish stem. The brain-like folds must be the main, clearly visible feature.
```

#### 47. Шапка — глива (віяло на деревині) — `cap_oyster`
Видно: кілька сіро-білих шапок-віял, що ростуть черепицею з боку деревини.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a cluster of three overlapping OYSTER mushrooms growing out of the side of a piece of tree bark. The caps are FAN-shaped like shells, GREY-WHITE to pale grey-brown, smooth, with very short stems at their side edge. The fan-shaped shell caps on wood must be the main, clearly visible feature.
```

#### 48. Трутовик — полиці на стовбурі (сірчано-жовтий) — `cap_bracket`
Видно: кілька товстих жовто-оранжевих «полиць» на стовбурі, ніжки немає.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a large BRACKET FUNGUS growing out of the side of a tree trunk: several overlapping thick fan-shaped shelves with wavy lobed edges, bright SULPHUR-YELLOW on top with ORANGE edges. No stem. The yellow shelves on the trunk must be the main, clearly visible feature.
```

#### 49. Плодове тіло — дощовик (кулька) — `body_puffball`
Видно: біла кулька чи «груша» без шапки й ніжки, у дрібних шипиках.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a PUFFBALL mushroom on a little moss: a round to pear-shaped WHITE fruit body with NO cap and NO separate stem, its surface covered with tiny white spines and warts, a few of them rubbed off. The round spiny white ball must be the main, clearly visible feature.
```

#### 50. Плодове тіло — кораловидне (рогатик, рамарія) — `body_coral`
Видно: кущик із товстих гілок, як корал або цвітна капуста.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a CORAL mushroom: a bushy fruit body made of many thick upright branches growing from one whitish base, like a sea coral or a cauliflower, CREAM-WHITE with slightly pinkish tips. The branched coral shape must be the main, clearly visible feature.
```

#### 51. Спорова маса — старий дощовик пилить — `spores_puff`
Видно: старий бурий дощовик розкрився зверху, з нього вилітає хмаринка оливково-бурого пилу.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: an old brown PUFFBALL with its top split open, a small cloud of DARK OLIVE-BROWN spore powder puffing out of the opening; inside, the olive-brown powdery mass is visible. The puff of spore powder must be the main, clearly visible feature.
```

#### 52. М'якоть — жовто-оранжева, не змінюється — `flesh_yellow`
Видно: жовто-оранжевий гриб, розрізаний уздовж; м'якоть рівномірно жовта.
```
Cute hand-drawn sticker illustration for a mushroom app. Watercolor with thin dark-brown ink outline, warm natural colors, soft shading. Transparent background, white sticker border. One subject, centered, fills 80% of a square. No text, no letters, no numbers, no arrows, no extra objects.
Subject: a yellow-orange mushroom CUT IN HALF LENGTHWISE, the cut surface facing the viewer. The flesh is evenly pale YELLOW-ORANGE and does not change color. A small knife lies next to it. The yellow flesh on the cut must be the main, clearly visible feature.
```
