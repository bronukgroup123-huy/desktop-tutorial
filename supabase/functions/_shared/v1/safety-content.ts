// ============================================================================
// Тексти вкладки «Безпека» (ADR-003, ADR-022 §22.3, BACKEND_PLAN B4.3 / B4.10)
//
// Банер ДСНС, «Заблукали?», «Отруєння: що робити», «Інші небезпеки», чек-лист перед походом і
// поради на час повітряної тривоги. Віддає `GET v1-app-config` — змінюються без релізу
// застосунку: рядки `feature_flags` `safety_notices` (масив банерів) і `safety_content`
// (часткова заміна) перекривають типові тексти нижче.
//
// Застосунок вбудовує ТІ САМІ типові тексти (`flutter_client/assets/safety/safety_content.json`
// — тест звіряє), бо в лісі без зв'язку тексти потрібні з першого запуску.
// Лише перевірені загальні поради; медичні — «виконуйте вказівки диспетчера 103».
// ============================================================================

export interface SafetyNotice {
  id: string;
  title: string;
  body: string;
  link_label: string | null;
  link_url: string | null;
  severity: "danger" | "warning" | "info";
}

export interface SafetySection {
  title: string | null;
  items: string[];
}

export interface SafetyGuide {
  id: string;
  title: string;
  subtitle: string;
  sections: SafetySection[];
}

export interface SafetyContent {
  version: number;
  notices: SafetyNotice[];
  guides: SafetyGuide[];
  checklist: Array<{ id: string; label: string }>;
  air_alert: { title: string; tips: string[] };
}

export const DEFAULT_SAFETY_CONTENT: SafetyContent = {
  version: 1,
  notices: [
    {
      id: "mines",
      title: "Мінна небезпека",
      body:
        "Не заходьте в ліси, де велися бойові дії або є таблички «Міни». Не торкайтеся підозрілих " +
        "предметів: зупиніться, поверніться тим самим шляхом і телефонуйте 101 або 102.",
      link_label: "Офіційна інформація — ДСНС",
      link_url: "https://dsns.gov.ua/",
      severity: "danger",
    },
  ],
  guides: [
    {
      id: "lost",
      title: "Заблукали?",
      subtitle: "Зупиніться й не панікуйте — так вас знайдуть швидше",
      sections: [
        {
          title: null,
          items: [
            "Зупиніться. Сядьте, кілька разів глибоко вдихніть — паніка забирає сили й веде вглиб лісу.",
            "Подивіться «Мої координати» й увімкніть «Повернутися» — компас покаже напрямок до машини.",
            "Якщо не знаєте, куди йти, лишайтеся на місці: того, хто стоїть, знайти легше.",
            "Телефонуйте 112 і продиктуйте координати. Дзвінок безкоштовний.",
            "Бережіть батарею: зменште яскравість, закрийте зайві застосунки, не гортайте стрічки.",
            "Подавайте сигнали: свисток — три короткі свистки, вночі — «Світловий сигнал SOS».",
            "Тримайтеся на видноті: яскравий одяг, узлісся чи галявина замість хащів.",
          ],
        },
      ],
    },
    {
      id: "poisoning",
      title: "Отруєння грибами: що робити",
      subtitle: "Нудота, блювання, біль у животі, слабкість після грибів",
      sections: [
        {
          title: null,
          items: [
            "Одразу телефонуйте 103 — навіть якщо стало легше. Отрута блідої поганки діє через 6–24 години, а «полегшення» буває оманливим.",
            "Збережіть залишки грибів, страви чи очистки — лікарям треба знати, який гриб.",
            "Сфотографуйте гриби, якщо залишків немає, — і перевірте в «Розпізнати».",
            "До лікаря — усім, хто їв ту саму страву, навіть без ознак отруєння.",
            "Виконуйте вказівки диспетчера 103.",
          ],
        },
        {
          title: "Чого не робити",
          items: [
            "Не лікуйтеся самі й не чекайте, «поки мине».",
            "Не пийте алкоголь і не давайте його постраждалому.",
          ],
        },
      ],
    },
    {
      id: "dangers",
      title: "Інші небезпеки",
      subtitle: "Кліщі, гадюка, кабани, сезон полювання",
      sections: [
        {
          title: "Кліщі",
          items: [
            "У ліс — закритий одяг світлого кольору, штани заправте в шкарпетки.",
            "Після лісу огляньте все тіло, особливо пахви, пах, шию й голову.",
            "Кліща витягуйте пінцетом чи «петлею» якомога ближче до шкіри, рівно, без різких ривків; ранку продезінфікуйте.",
            "Запам'ятайте дату. Почервоніння кільцем, температура чи слабкість протягом місяця — до лікаря.",
          ],
        },
        {
          title: "Укус гадюки",
          items: [
            "Телефонуйте 103. Постраждалому — спокій і якомога менше рухатися.",
            "Знерухомте укушену руку чи ногу, зніміть каблучки й браслети — набряк швидко росте.",
            "Не розрізайте ранку, не висмоктуйте отруту, не накладайте джгут і не пийте алкоголь.",
          ],
        },
        {
          title: "Кабани й інші звірі",
          items: [
            "Побачили кабана, особливо самку з поросятами, — повільно відійдіть, не біжіть і не підходьте.",
            "Не годуйте звірів і не підходьте до малят — мати поруч.",
          ],
        },
        {
          title: "Сезон полювання",
          items: [
            "Яскравий одяг або жилет — щоб вас не сплутали зі звіром.",
            "Говоріть, не ховайтеся в кущах, не ходіть лісом у сутінках.",
            "Чуєте постріли — подайте голос і відійдіть у протилежний бік.",
          ],
        },
      ],
    },
  ],
  checklist: [
    { id: "phone", label: "Телефон заряджений, павербанк із кабелем" },
    { id: "water", label: "Вода й перекус" },
    { id: "clothes", label: "Яскравий одяг за погодою, дощовик, зручне взуття" },
    { id: "whistle", label: "Свисток і ліхтарик" },
    { id: "aid", label: "Аптечка: бинт, пластир, антисептик, свої ліки" },
    { id: "knife", label: "Ніж і кошик (не пакет — гриби в ньому псуються)" },
    { id: "route", label: "Маршрут створено — є точка старту" },
    { id: "tell", label: "Сказали рідним, куди йдете і коли повернетеся" },
  ],
  air_alert: {
    title: "Повітряна тривога",
    tips: [
      "Відійдіть від доріг, мостів, ЛЕП і вишок.",
      "Сховайтеся в низині, яру чи канаві; ляжте, прикрийте голову руками.",
      "Не знімайте й не публікуйте військові об'єкти, удари й роботу ППО.",
    ],
  },
};

/** Банери з `feature_flags.safety_notices` (масив) — лише коректні, посилання лише https. */
export function parseNotices(raw: unknown): SafetyNotice[] | null {
  if (!Array.isArray(raw)) return null;
  const out: SafetyNotice[] = [];
  for (const n of raw) {
    if (!n || typeof n !== "object") continue;
    const o = n as Record<string, unknown>;
    if (typeof o.id !== "string" || typeof o.title !== "string" || typeof o.body !== "string") continue;
    const url = typeof o.link_url === "string" && o.link_url.startsWith("https://") ? o.link_url : null;
    out.push({
      id: o.id,
      title: o.title,
      body: o.body,
      link_label: url && typeof o.link_label === "string" ? o.link_label : null,
      link_url: url,
      severity: o.severity === "warning" || o.severity === "info" ? o.severity : "danger",
    });
  }
  return out;
}

/** Типові тексти + заміни з `feature_flags` (будь-яка помилка — типові тексти). */
export function mergeSafetyContent(
  notices: unknown,
  override: unknown,
): SafetyContent {
  const base: SafetyContent = structuredClone(DEFAULT_SAFETY_CONTENT);
  const o = override && typeof override === "object" ? override as Partial<SafetyContent> : {};
  if (Array.isArray(o.guides) && o.guides.every((g) => g && typeof g.id === "string" && Array.isArray(g.sections))) {
    base.guides = o.guides;
  }
  if (Array.isArray(o.checklist) && o.checklist.every((c) => c && typeof c.id === "string" && typeof c.label === "string")) {
    base.checklist = o.checklist;
  }
  if (o.air_alert && Array.isArray(o.air_alert.tips) && typeof o.air_alert.title === "string") {
    base.air_alert = o.air_alert;
  }
  if (typeof o.version === "number") base.version = o.version;
  const parsed = parseNotices(notices);
  if (parsed) base.notices = parsed;
  return base;
}
