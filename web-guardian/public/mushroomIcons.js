/**
 * mushroomIcons.js
 * Кастомні SVG-іконки для видів грибів, що мають фото (has_photo: true).
 * viewBox="0 0 64 64" для всіх іконок.
 * Експортує функцію getMushroomIconHtml(species, size = 32),
 * яка повертає HTML-рядок <svg>...</svg> для використання у vanilla-JS коді (landing.html).
 *
 * Підхід: 4 базові SVG-шаблони з чітким контуром (stroke="#333", stroke-width="2")
 * + динамічні CSS-змінні (--cap-color, --stem-color) для кольорів.
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
  "boletus_edulis":        { template: "tubular", cap: "#8B4513", stem: "#E6D3B6", spots: false },
  "leccinum_scabrum":      { template: "tubular", cap: "#696969", stem: "#E6D3B6", spots: true },
  "cantharellus_cibarius": { template: "funnel",  cap: "#FFD700", stem: "#FFD700", spots: false },
  "lactarius_deliciosus":  { template: "funnel",  cap: "#FF8C00", stem: "#FF8C00", spots: false },
  "armillaria_mellea":     { template: "ringed",   cap: "#D2B48C", stem: "#FFF8DC", spots: false },
  "amanita_muscaria":      { template: "amanita",  cap: "#E32636", stem: "#FFFFFF", spots: false },
};

// Колірна палітра для Сироїжок (Russula) — різні кольори шапки
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
  return "tubular";
}

// Визначення кольорів за типом гриба (для видів, що не в ICON_CONFIG)
function colorsFor(species) {
  if (species.startsWith("amanita_")) return { cap: "#E32636", stem: "#FFFFFF" };
  if (species.startsWith("boletus_") || species.includes("boletus")) return { cap: "#8B4513", stem: "#E6D3B6" };
  if (species.includes("cantharellus") || species.includes("craterellus")) return { cap: "#FB8C00", stem: "#FFECB3" };
  if (species.includes("lactarius") || species.includes("lactifluus")) return { cap: "#BF360C", stem: "#EFEBE9" };
  if (species.startsWith("russula_")) {
    const idx = species.charCodeAt(species.length - 1) % RUSSULA_COLORS.length;
    return { cap: RUSSULA_COLORS[idx], stem: "#FFF9C4" };
  }
  if (species.includes("armillaria") || species.includes("kuehneromyces") || species.includes("hypholoma")) return { cap: "#FFB300", stem: "#FFFDE7" };
  if (species.includes("leccinum")) return { cap: "#808080", stem: "#E6D3B6" };
  if (species.includes("suillus")) return { cap: "#BCAAA4", stem: "#D7CCC8" };
  if (species.includes("tricholoma_")) return { cap: "#795548", stem: "#D7CCC8" };
  if (species.includes("macrolepiota")) return { cap: "#D7CCC8", stem: "#F5F5F5" };
  if (species.includes("pleurotus")) return { cap: "#ECEFF1", stem: "#CFD8DC" };
  if (species.includes("polyporus") || species.includes("laetiporus") || species.includes("grifola") || species.includes("sparassis")) return { cap: "#8D6E63", stem: "#6D4C41" };
  if (species.includes("morchella") || species.includes("gyromitra")) return { cap: "#D7CCC8", stem: "#D7CCC8" };
  if (species.includes("phallus") || species.includes("pseudocolus") || species.includes("anthurus")) return { cap: "#E53935", stem: "#FFFDE7" };
  return { cap: "#8D6E63", stem: "#E6D3B6" };
}

// Чи має вид юбочку (кільце)
function hasRingFor(species) {
  if (ICON_CONFIG[species] && ICON_CONFIG[species].template === "ringed") return true;
  if (species.includes("armillaria") || species.includes("kuehneromyces") || species.includes("hypholoma")) return true;
  if (species.startsWith("amanita_")) return true;
  if (species.includes("macrolepiota")) return true;
  if (species.includes("lepiota")) return true;
  return false;
}

// Чи мають бути чорні крапки на нічці (лусочки Підберезника)
function hasSpotsFor(species) {
  return ICON_CONFIG[species] && ICON_CONFIG[species].spots === true;
}

// ---------------------------------------------------------------------------
// 4 Базові SVG-шаблони (stroke="#333", stroke-width="2" на всіх path)
// ---------------------------------------------------------------------------
function templateTubular({ size, capColor, stemColor, spots }) {
  const spotsHtml = spots
    ? `<circle cx="26" cy="48" r="2" fill="#000000" />
       <circle cx="30" cy="50" r="2" fill="#000000" />
       <circle cx="34" cy="46" r="2" fill="#000000" />
       <circle cx="38" cy="52" r="2" fill="#000000" />`
    : "";
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg"
     style="--cap-color:${capColor};--stem-color:${stemColor};">
  <path d="M26 40 Q24 54 28 58 L36 58 Q40 54 38 40 Z" fill="var(--stem-color, #E6D3B6)" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
  <path d="M14 34 C14 16 50 16 50 34 C50 38 44 42 32 42 C20 42 14 38 14 34 Z" fill="var(--cap-color, #8B4513)" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
  <path d="M18 36 Q32 42 46 36" stroke="#333" stroke-width="2" opacity="0.3" fill="none"/>
  ${spotsHtml}
</svg>`;
}

function templateRinged({ size, capColor, stemColor }) {
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg"
     style="--cap-color:${capColor};--stem-color:${stemColor};">
  <path d="M28 38 L26 56 L38 56 L36 38 Z" fill="var(--stem-color, #FFF)" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
  <path d="M16 30 C16 16 48 16 48 30 C48 34 40 38 32 38 C24 38 16 34 16 30 Z" fill="var(--cap-color, #D2B48C)" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
  <path d="M22 42 Q32 48 42 42 Q38 40 32 40 Q26 40 22 42 Z" fill="#FFF" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
</svg>`;
}

function templateFunnel({ size, capColor, stemColor }) {
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg"
     style="--cap-color:${capColor};--stem-color:${stemColor};">
  <path d="M18 26 C14 14 50 14 46 26 C44 32 38 36 36 42 L36 56 L28 56 L28 42 C26 36 20 32 18 26 Z" fill="var(--cap-color, #FFA500)" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
  <ellipse cx="32" cy="24" rx="10" ry="4" fill="rgba(0,0,0,0.15)" stroke="#333" stroke-width="1.5"/>
</svg>`;
}

function templateAmanita({ size, capColor, stemColor }) {
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg"
     style="--cap-color:${capColor};--stem-color:${stemColor};">
  <path d="M28 38 L26 56 L38 56 L36 38 Z" fill="#FFF" stroke="#333" stroke-width="2"/>
  <path d="M12 32 C12 12 52 12 52 32 C52 36 44 38 32 38 C20 38 12 36 12 32 Z" fill="#E32636" stroke="#333" stroke-width="2"/>
  <circle cx="24" cy="22" r="3" fill="#FFF" stroke="#333" stroke-width="1"/>
  <circle cx="38" cy="20" r="4" fill="#FFF" stroke="#333" stroke-width="1"/>
  <circle cx="32" cy="30" r="3" fill="#FFF" stroke="#333" stroke-width="1"/>
  <circle cx="44" cy="28" r="2" fill="#FFF" stroke="#333" stroke-width="1"/>
  <path d="M22 42 Q32 48 42 42 Q38 40 32 40 Q26 40 22 42 Z" fill="#FFF" stroke="#333" stroke-width="2"/>
</svg>`;
}

// ---------------------------------------------------------------------------
// Fallback SVG для видів без фото / невідомих
// ---------------------------------------------------------------------------
function fallbackSvg(title) {
  const safeTitle = escHtml(title);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" fill="none" aria-label="${safeTitle}" role="img">
    <circle cx="32" cy="32" r="20" fill="#CFD8DC" stroke="#333" stroke-width="2"/>
    <path d="M22 38 Q32 26 42 38" stroke="#90A4AE" stroke-width="4" stroke-linecap="round"/>
    <path d="M27 46 L27 56 M37 46 L37 56" stroke="#B0BEC5" stroke-width="6" stroke-linecap="round"/>
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
    ? { cap: cfg.cap, stem: cfg.stem }
    : colorsFor(resolved);
  const spots = cfg ? cfg.spots : hasSpotsFor(resolved);

  switch (template) {
    case "ringed":
      return templateRinged({ size, capColor: colors.cap, stemColor: colors.stem });
    case "funnel":
      return templateFunnel({ size, capColor: colors.cap, stemColor: colors.stem });
    case "amanita":
      return templateAmanita({ size, capColor: colors.cap, stemColor: colors.stem });
    case "tubular":
    default:
      return templateTubular({ size, capColor: colors.cap, stemColor: colors.stem, spots });
  }
}

window.getMushroomIconHtml = getMushroomIconHtml;
