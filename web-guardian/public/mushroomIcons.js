/**
 * mushroomIcons.js
 * Кастомні SVG-іконки для видів грибів, що мають фото (has_photo: true).
 * viewBox="0 0 64 64" для всіх іконок.
 * Експортує функцію getMushroomIconHtml(species, size = 32),
 * яка повертає HTML-рядок <svg>...</svg> для використання у vanilla-JS коді (landing.html).
 *
 * Підхід: 4 базові SVG-шаблони (трубчастий, з юбочкою, воронкоподібний, мухомор)
 * + динамічні CSS-змінні (--cap-color, --stem-color, --detail-color) для кольорів.
 */

const SPECIES_WITH_PHOTO = new Set([
  "boletus_edulis","lactarius_torminosus","pleurotus_ostreatus","lactarius_resimus","lycoperdon_perlatum",
  "boletus_luridus","flammulina_velutipes","hydnum_repandum","suillus_bovinus","cantharellus_cibarius",
  "suillus_luteus","xerocomus_subtomentosus","armillaria_mellea","agaricus_campestris","leccinum_scabrum",
  "leccinum_aurantiacum","imleria_badia","lactarius_deliciosus","russula_vesca","morchella_esculenta",
  "albatrellus_confluens","albatrellus_ovinus","boletus_reticulatus","boletus_pinophilus","pleurotus_dryinus",
  "pleurotus_pulmonarius","macrolepiota_procera","macrolepiota_mastoidea","tricholoma_equestre","hydnum_rufescens",
  "hydnum_umbilicatum","clavulina_coralloides","cantharellus_amethysteus","craterellus_lutescens","craterellus_cinereus",
  "craterellus_tubaeformis","cantharellus_friesii","suillus_placidus","suillus_variegatus","suillus_granulatus",
  "suillus_grevillei","xerocomellus_chrysenteron","amanita_excelsa","amanita_rubescens","amanita_crocea",
  "kuehneromyces_mutabilis","armillaria_ostoyae","leccinellum_pseudoscabrum","leccinum_versipelle","leccinum_variicolor",
  "leccinum_duriusculum","russula_delica","leccinum_albostipitatum","amanita_fulva","amanita_vaginata",
  "ramaria_botrytis","lactarius_deterrimus","lactarius_salmonicolor","tricholoma_terreum","lepista_personata",
  "calocybe_gambosa","tricholoma_portentosum","lepista_nuda","russula_xerampelina","russula_virescens",
  "russula_cyanoxantha","russula_foetens","lactarius_vellereus","polyporus_squamosus","laetiporus_sulphureus",
  "lactarius_quietus","lactifluus_volemus","lactarius_piperatus","lactarius_subdulcis","boletus_aereus",
  "rubroboletus_lupinus","butyriboletus_appendiculatus","butyriboletus_regius","butyriboletus_subappendiculatus",
  "butyriboletus_fuscoroseus","rubroboletus_rhodoxanthus","rubroboletus_satanas","butyriboletus_fechtneri",
  "rubroboletus_rubrosanguineus","phallus_duplicatus","hemileccinum_depilatum","hericium_erinaceus","hericium_coralloides",
  "hygrocybe_calyptriformis","gomphus_clavatus","grifola_frondosa","morchella_steppicola","pseudocolus_fusiformis",
  "catathelasma_imperiale","anthurus_archeri","clavariadelphus_pistillaris","lyophyllum_favrei","helvella_monachella",
  "suillus_plorans","myriostoma_coliforme","boletus_parasiticus","amanita_caesarea","amanita_strobiliformis",
  "chalciporus_rubinus","clathrus_ruber","tricholoma_colossus","tricholoma_focale","sarcosoma_globosum",
  "russula_turci","scleroderma_geaster","sparassis_crispa","polyporus_umbellatus","tuber_aestivum",
  "phellorinia_herculeana","phaeolepiota_aurea","phylloporus_pelletieri","lactarius_lignyotus","strobilomyces_strobilaceus",
  "amanita_muscaria","amanita_pantherina","amanita_phalloides","amanita_verna","amanita_virosa",
  "clitocybe_candicans","clitocybe_dealbata","entoloma_sinuatum","galerina_marginata","gyromitra_esculenta",
  "hygrophoropsis_aurantiaca","inocybe_erubescens","inocybe_geophylla","paxillus_involutus",
]);

// Alias map: forecast sticker IDs → actual species IDs in SPECIES_WITH_PHOTO
const SPECIES_ALIASES = {
  "morchella_spp": "morchella_esculenta",
  "lycoperdon_spp": "lycoperdon_perlatum",
  "xerocomus_spp": "xerocomus_subtomentosus",
};

// ---------------------------------------------------------------------------
// Конфігурація видів: template + кольори + додаткові деталі
// template: "tubular" | "ringed" | "funnel" | "amanita"
// ---------------------------------------------------------------------------
const ICON_CONFIG = {
  "boletus_edulis":        { template: "tubular", cap: "#8B4513", stem: "#F5F5DC", detail: "#5D4037", ring: false, spots: false },
  "cantharellus_cibarius": { template: "funnel",  cap: "#FFD700", stem: "#FFD700", detail: "#FF8C00", ring: false, spots: false },
  "armillaria_mellea":     { template: "ringed",   cap: "#D2B48C", stem: "#FFF8DC", detail: "#FFFFFF", ring: true,  spots: false },
  "leccinum_scabrum":      { template: "tubular", cap: "#808080", stem: "#F5F5DC", detail: "#000000", ring: false, spots: true },
  "lactarius_deliciosus":  { template: "funnel",  cap: "#FF8C00", stem: "#FF8C00", detail: "#B71C1C", ring: false, spots: false },
  "lactarius_resimus":     { template: "funnel",  cap: "#FFF8DC", stem: "#FFFFFF", detail: "#FFF8DC", ring: false, spots: false },
  "amanita_muscaria":      { template: "amanita",  cap: "#E32636", stem: "#FFFFFF", detail: "#FFFFFF", ring: true,  spots: false },
};

// Колірна паліпа для Сироїжок (Russula) — різні кольори шапки
const RUSSULA_COLORS = ["#DC2626", "#15803D", "#CA8A04", "#BE185D", "#0891B2", "#4D7C0F"];

// ---------------------------------------------------------------------------
// Допоміжні функції
// ---------------------------------------------------------------------------
function escHtml(unsafe) {
  return unsafe
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

// Визначення шаблону за типом гриба (для видів, що не в ICON_CONFIG)
function templateFor(species) {
  if (species.startsWith("amanita_")) return "amanita";
  if (species.includes("cantharellus") || species.includes("craterellus")) return "funnel";
  if (species.includes("lactarius") || species.includes("lactifluus")) return "funnel";
  if (species.includes("armillaria") || species.includes("kuehneromyces") || species.includes("hypholoma")) return "ringed";
  if (species.startsWith("leccinum") || species.includes("leccinum")) return "tubular";
  if (species.startsWith("boletus_") || species.includes("boletus")) return "tubular";
  if (species.startsWith("russula_")) return "tubular";
  return "tubular";
}

// Визначення кольорів за типом гриба (для видів, що не в ICON_CONFIG)
function colorsFor(species) {
  if (species.startsWith("amanita_")) return { cap: "#E32636", stem: "#FFFFFF", detail: "#FFFFFF" };
  if (species.startsWith("boletus_") || species.includes("boletus")) return { cap: "#8B4513", stem: "#F5F5DC", detail: "#5D4037" };
  if (species.includes("cantharellus") || species.includes("craterellus")) return { cap: "#FB8C00", stem: "#FFECB3", detail: "#FF8C00" };
  if (species.includes("lactarius") || species.includes("lactifluus")) return { cap: "#BF360C", stem: "#EFEBE9", detail: "#FF7043" };
  if (species.startsWith("russula_")) {
    // Детермінований "випадковий" колір на основі назви виду
    const idx = species.charCodeAt(species.length - 1) % RUSSULA_COLORS.length;
    return { cap: RUSSULA_COLORS[idx], stem: "#FFF9C4", detail: "#FDD835" };
  }
  if (species.includes("armillaria") || species.includes("kuehneromyces") || species.includes("hypholoma")) return { cap: "#FFB300", stem: "#FFFDE7", detail: "#FFEB3B" };
  if (species.includes("leccinum")) return { cap: "#808080", stem: "#F5F5DC", detail: "#000000" };
  if (species.includes("suillus")) return { cap: "#BCAAA4", stem: "#D7CCC8", detail: "#FFD54F" };
  if (species.includes("tricholoma_")) return { cap: "#795548", stem: "#D7CCC8", detail: "#6D4C41" };
  if (species.includes("macrolepiota")) return { cap: "#D7CCC8", stem: "#F5F5F5", detail: "#EFEBE9" };
  if (species.includes("pleurotus")) return { cap: "#ECEFF1", stem: "#CFD8DC", detail: "#B0BEC5" };
  if (species.includes("polyporus") || species.includes("laetiporus") || species.includes("grifola") || species.includes("sparassis")) return { cap: "#8D6E63", stem: "#6D4C41", detail: "#A1887F" };
  if (species.includes("morchella") || species.includes("gyromitra")) return { cap: "#D7CCC8", stem: "#D7CCC8", detail: "#BCAAA4" };
  if (species.includes("phallus") || species.includes("pseudocolus") || species.includes("anthurus")) return { cap: "#E53935", stem: "#FFFDE7", detail: "#FFF176" };
  return { cap: "#8D6E63", stem: "#D7CCC8", detail: "#FFEB3B" };
}

// Чи має вид юбочку (кільце)
function hasRingFor(species) {
  if (ICON_CONFIG[species] && ICON_CONFIG[species].ring) return true;
  if (species.includes("armillaria") || species.includes("kuehneromyces") || species.includes("hypholoma")) return true;
  if (species.startsWith("amanita_")) return true;
  if (species.includes("macrolepiota")) return true;
  if (species.includes("lepiota")) return true;
  return false;
}

// Чи мають бути чорні крапки на нічці (лусочки Підберезника)
function hasSpotsFor(species) {
  if (ICON_CONFIG[species] && ICON_CONFIG[species].spots) return true;
  return false;
}

// ---------------------------------------------------------------------------
// 4 Базові SVG-шаблони (CSS-змінні: --cap-color, --stem-color, --detail-color)
// ---------------------------------------------------------------------------
function templateTubular({ size, capColor, stemColor, detailColor, spots }) {
  const spotsHtml = spots
    ? `<circle cx="26" cy="48" r="1.5" fill="${detailColor}" />
       <circle cx="30" cy="50" r="1.5" fill="${detailColor}" />
       <circle cx="34" cy="46" r="1.5" fill="${detailColor}" />
       <circle cx="38" cy="52" r="1.5" fill="${detailColor}" />`
    : "";
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg"
     style="--cap-color:${capColor};--stem-color:${stemColor};--detail-color:${detailColor};">
  <path d="M18 32 C18 18, 46 18, 46 32 C46 38, 40 42, 32 42 C24 42, 18 38, 18 32 Z" fill="var(--cap-color,#8B4513)"/>
  <path d="M26 42 C26 42, 24 56, 28 58 L36 58 C40 56, 38 42, 38 42 Z" fill="var(--stem-color,#F5F5DC)"/>
  ${spotsHtml}
  <path d="M18 32 C18 38, 24 42, 32 42 C40 42, 46 38, 46 32" stroke="rgba(0,0,0,0.2)" stroke-width="2" stroke-linecap="round"/>
</svg>`;
}

function templateRinged({ size, capColor, stemColor, detailColor }) {
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg"
     style="--cap-color:${capColor};--stem-color:${stemColor};--detail-color:${detailColor};">
  <path d="M16 30 C16 16, 48 16, 48 30 C48 36, 42 38, 32 38 C22 38, 16 36, 16 30 Z" fill="var(--cap-color,#D2B48C)"/>
  <path d="M28 38 C28 38, 26 52, 28 56 L36 56 C38 52, 36 38, 36 38 Z" fill="var(--stem-color,#FFF8DC)"/>
  <path d="M24 42 C28 46, 36 46, 40 42 C38 40, 26 40, 24 42 Z" fill="var(--detail-color,#FFF)" opacity="0.8"/>
  <path d="M16 30 C16 36, 22 38, 32 38 C42 38, 48 36, 48 30" stroke="rgba(0,0,0,0.2)" stroke-width="2"/>
</svg>`;
}

function templateFunnel({ size, capColor, stemColor, detailColor }) {
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg"
     style="--cap-color:${capColor};--stem-color:${stemColor};--detail-color:${detailColor};">
  <path d="M12 28 C12 16, 20 12, 32 12 C44 12, 52 16, 52 28 C52 32, 46 36, 42 40 C38 44, 36 50, 36 56 L28 56 C28 50, 26 44, 22 40 C18 36, 12 32, 12 28 Z" fill="var(--cap-color,#FFA500)"/>
  <ellipse cx="32" cy="26" rx="8" ry="4" fill="rgba(0,0,0,0.1)"/>
</svg>`;
}

function templateAmanita({ size, capColor, stemColor, detailColor }) {
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg"
     style="--cap-color:${capColor};--stem-color:${stemColor};--detail-color:${detailColor};">
  <path d="M12 32 C12 12, 52 12, 52 32 C52 36, 44 40, 32 40 C20 40, 12 36, 12 32 Z" fill="var(--cap-color,#E32636)"/>
  <circle cx="24" cy="22" r="3" fill="#FFF"/>
  <circle cx="38" cy="20" r="4" fill="#FFF"/>
  <circle cx="32" cy="30" r="3" fill="#FFF"/>
  <circle cx="44" cy="28" r="2" fill="#FFF"/>
  <path d="M28 40 C28 40, 26 52, 28 56 L36 56 C38 52, 36 40, 36 40 Z" fill="var(--stem-color,#FFF)"/>
  <path d="M22 44 C28 48, 36 48, 42 44 C38 42, 26 42, 22 44 Z" fill="#FFF" opacity="0.9"/>
</svg>`;
}

// ---------------------------------------------------------------------------
// Fallback SVG для видів без фото / невідомих
// ---------------------------------------------------------------------------
function fallbackSvg(title) {
  const safeTitle = escHtml(title);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" fill="none" aria-label="${safeTitle}" role="img">
    <circle cx="32" cy="32" r="20" fill="#CFD8DC" />
    <path d="M22 38 Q32 26 42 38" stroke="#90A4AE" stroke-width="4" stroke-linecap="round" />
    <path d="M27 46 L27 56 M37 46 L37 56" stroke="#B0BEC5" stroke-width="6" stroke-linecap="round" />
    <title>${safeTitle}</title>
  </svg>`;
}

/**
 * Повертає HTML-рядок SVG-іконки для виду.
 * @param {string} species - програмне ім'я виду (id)
 * @param {number|string} size - розмір іконки (за замовчуванням 32)
 * @returns {string} HTML-рядок <svg>...</svg>
 */
function getMushroomIconHtml(species, size = 32) {
  if (!species) {
    return fallbackSvg("Невідомий гриб");
  }

  // Resolve forecast sticker aliases (e.g. morchella_spp → morchella_esculenta)
  const resolved = SPECIES_ALIASES[species] || species;

  if (!SPECIES_WITH_PHOTO.has(resolved)) {
    return fallbackSvg(resolved);
  }

  const cfg = ICON_CONFIG[resolved] || null;
  const template = cfg ? cfg.template : templateFor(resolved);
  const colors = cfg
    ? { cap: cfg.cap, stem: cfg.stem, detail: cfg.detail }
    : colorsFor(resolved);
  const ring = cfg ? cfg.ring : hasRingFor(resolved);
  const spots = cfg ? cfg.spots : hasSpotsFor(resolved);

  switch (template) {
    case "ringed":
      return templateRinged({ size, capColor: colors.cap, stemColor: colors.stem, detailColor: colors.detail });
    case "funnel":
      return templateFunnel({ size, capColor: colors.cap, stemColor: colors.stem, detailColor: colors.detail });
    case "amanita":
      return templateAmanita({ size, capColor: colors.cap, stemColor: colors.stem, detailColor: colors.detail });
    case "tubular":
    default:
      return templateTubular({ size, capColor: colors.cap, stemColor: colors.stem, detailColor: colors.detail, spots });
  }
}

window.getMushroomIconHtml = getMushroomIconHtml;
