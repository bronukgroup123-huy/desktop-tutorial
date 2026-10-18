/**
 * mushroomIcons.js
 * Кастомні SVG-іконки для видів грибів, що мають фото (has_photo: true).
 * viewBox="0 0 64 64" для всіх іконок.
 * Експортує функцію getMushroomIconHtml(species, size = 32),
 * яка повертає HTML-рядок <svg>...</svg> для використання у vanilla-JS коді (landing.html).
 *
 * Підхід: 7 базових SVG-шаблонів (tubular, gilled, funnel, amanita, morel, bracket, puffball)
 * з динамічними кольорами (cap, stem) та функціональними деталями (ring, dots, spines, brain, fuzzy, slimy).
 * Усі шляхи мають stroke="#333" та stroke-width="2" для чіткості на будь-якому фоні.
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
// MUSHROOM_VISUALS — 132 види з авто-парсингу descriptions + коригування вручну
// Ключ — species.id з mushroom_catalog.json (з підкресленнями, як у каталозі)
// ---------------------------------------------------------------------------
const MUSHROOM_VISUALS = {
  "boletus_edulis": { shape: "tubular", cap: "#8B4513", stem: "#FFFFFF", features: [] },
  "lactarius_torminosus": { shape: "funnel", cap: "#E32636", stem: "#CD5C5C", features: ["fuzzy"] },
  "pleurotus_ostreatus": { shape: "funnel", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "lactarius_resimus": { shape: "tubular", cap: "#FFF8DC", stem: "#FFFFFF", features: ["fuzzy"] },
  "lycoperdon_perlatum": { shape: "tubular", cap: "#F0F8FF", stem: "#FFFFFF", features: ["spines"] },
  "boletus_luridus": { shape: "tubular", cap: "#8D6E63", stem: "#FFFFFF", features: [] },
  "flammulina_velutipes": { shape: "tubular", cap: "#D2691E", stem: "#A0522D", features: ["slimy"] },
  "hydnum_repandum": { shape: "tubular", cap: "#FFD700", stem: "#FFFFFF", features: ["spines"] },
  "suillus_bovinus": { shape: "tubular", cap: "#CD853F", stem: "#FFFFFF", features: ["slimy"] },
  "cantharellus_cibarius": { shape: "tubular", cap: "#FFD700", stem: "#FFD700", features: [] },
  "suillus_luteus": { shape: "tubular", cap: "#B8860B", stem: "#FFFFFF", features: ["ring", "slimy"] },
  "xerocomus_subtomentosus": { shape: "tubular", cap: "#6B8E23", stem: "#FFFFFF", features: ["fuzzy"] },
  "armillaria_mellea": { shape: "tubular", cap: "#D2691E", stem: "#FFFFFF", features: ["ring"] },
  "agaricus_campestris": { shape: "tubular", cap: "#F0F8FF", stem: "#FFFFFF", features: ["ring"] },
  "leccinum_scabrum": { shape: "tubular", cap: "#808080", stem: "#FFFFFF", features: ["dots"] },
  "leccinum_aurantiacum": { shape: "tubular", cap: "#D2691E", stem: "#FFFFFF", features: ["dots"] },
  "imleria_badia": { shape: "tubular", cap: "#5D4037", stem: "#FFFFFF", features: ["slimy"] },
  "lactarius_deliciosus": { shape: "funnel", cap: "#FF8C00", stem: "#FF8C00", features: ["slimy"] },
  "russula_vesca": { shape: "tubular", cap: "#FFD700", stem: "#FFFFFF", features: ["slimy"] },
  "morchella_esculenta": { shape: "tubular", cap: "#F5F5DC", stem: "#FFFFFF", features: ["brain"] },
  "albatrellus_confluens": { shape: "tubular", cap: "#DEB887", stem: "#FFFFFF", features: [] },
  "albatrellus_ovinus": { shape: "tubular", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "boletus_reticulatus": { shape: "tubular", cap: "#8B4513", stem: "#FFFFFF", features: [] },
  "boletus_pinophilus": { shape: "tubular", cap: "#5D4037", stem: "#FFFFFF", features: [] },
  "pleurotus_dryinus": { shape: "bracket", cap: "#D2691E", stem: "#FFFFFF", features: ["ring", "dots"] },
  "pleurotus_pulmonarius": { shape: "bracket", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "macrolepiota_procera": { shape: "tubular", cap: "#FFFFFF", stem: "#FFFFFF", features: ["ring"] },
  "macrolepiota_mastoidea": { shape: "tubular", cap: "#FFFFFF", stem: "#FFFFFF", features: ["ring"] },
  "tricholoma_equestre": { shape: "tubular", cap: "#FFD700", stem: "#FFFFFF", features: [] },
  "hydnum_rufescens": { shape: "tubular", cap: "#CD853F", stem: "#FFFFFF", features: ["spines"] },
  "hydnum_umbilicatum": { shape: "tubular", cap: "#FFA500", stem: "#FFFFFF", features: [] },
  "clavulina_coralloides": { shape: "morel", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "cantharellus_amethysteus": { shape: "gilled", cap: "#9370DB", stem: "#FFD700", features: ["dots"] },
  "craterellus_lutescens": { shape: "gilled", cap: "#FFD700", stem: "#FFD700", features: [] },
  "craterellus_cinereus": { shape: "gilled", cap: "#808080", stem: "#FFFFFF", features: [] },
  "craterellus_tubaeformis": { shape: "gilled", cap: "#696969", stem: "#FFFFFF", features: [] },
  "cantharellus_friesii": { shape: "gilled", cap: "#FF8C00", stem: "#FFD700", features: ["fuzzy"] },
  "suillus_placidus": { shape: "tubular", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "suillus_variegatus": { shape: "tubular", cap: "#CD853F", stem: "#FFFFFF", features: ["slimy"] },
  "suillus_granulatus": { shape: "tubular", cap: "#DAA520", stem: "#FFFFFF", features: ["slimy"] },
  "suillus_grevillei": { shape: "tubular", cap: "#D2691E", stem: "#FFFFFF", features: ["ring"] },
  "xerocomellus_chrysenteron": { shape: "tubular", cap: "#8B4513", stem: "#FFFFFF", features: [] },
  "amanita_excelsa": { shape: "amanita", cap: "#808080", stem: "#FFFFFF", features: ["ring"] },
  "amanita_rubescens": { shape: "amanita", cap: "#CD853F", stem: "#FFFFFF", features: ["ring"] },
  "amanita_crocea": { shape: "amanita", cap: "#D2691E", stem: "#FFFFFF", features: ["dots", "slimy"] },
  "kuehneromyces_mutabilis": { shape: "tubular", cap: "#CD853F", stem: "#FFFFFF", features: ["ring", "dots"] },
  "armillaria_ostoyae": { shape: "tubular", cap: "#696969", stem: "#FFFFFF", features: ["ring"] },
  "leccinellum_pseudoscabrum": { shape: "morel", cap: "#A9A9A9", stem: "#FFFFFF", features: ["dots"] },
  "leccinum_versipelle": { shape: "tubular", cap: "#8B4513", stem: "#FFFFFF", features: ["dots"] },
  "leccinum_variicolor": { shape: "tubular", cap: "#696969", stem: "#FFFFFF", features: ["dots"] },
  "leccinum_duriusculum": { shape: "tubular", cap: "#696969", stem: "#FFFFFF", features: ["dots"] },
  "russula_delica": { shape: "funnel", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "leccinum_albostipitatum": { shape: "tubular", cap: "#FFFFFF", stem: "#FFFFFF", features: ["dots"] },
  "amanita_fulva": { shape: "amanita", cap: "#CD853F", stem: "#FFFFFF", features: ["slimy"] },
  "amanita_vaginata": { shape: "amanita", cap: "#A9A9A9", stem: "#FFFFFF", features: ["slimy"] },
  "ramaria_botrytis": { shape: "tubular", cap: "#DA70D6", stem: "#FFFFFF", features: [] },
  "lactarius_deterrimus": { shape: "funnel", cap: "#FF8C00", stem: "#FF8C00", features: [] },
  "lactarius_salmonicolor": { shape: "funnel", cap: "#FFA07A", stem: "#FF8C00", features: ["slimy"] },
  "tricholoma_terreum": { shape: "tubular", cap: "#696969", stem: "#FFFFFF", features: ["dots"] },
  "lepista_personata": { shape: "tubular", cap: "#696969", stem: "#9370DB", features: [] },
  "calocybe_gambosa": { shape: "tubular", cap: "#FFF8DC", stem: "#FFFFFF", features: [] },
  "tricholoma_portentosum": { shape: "tubular", cap: "#808080", stem: "#FFFFFF", features: ["slimy"] },
  "lepista_nuda": { shape: "tubular", cap: "#9370DB", stem: "#FFFFFF", features: ["fuzzy"] },
  "russula_xerampelina": { shape: "tubular", cap: "#A52A2A", stem: "#FFFFFF", features: [] },
  "russula_virescens": { shape: "tubular", cap: "#8FBC8F", stem: "#FFFFFF", features: [] },
  "russula_cyanoxantha": { shape: "morel", cap: "#7FFFD4", stem: "#FFFFFF", features: ["slimy"] },
  "russula_foetens": { shape: "tubular", cap: "#DAA520", stem: "#FFFFFF", features: ["slimy"] },
  "lactarius_vellereus": { shape: "funnel", cap: "#F5F5DC", stem: "#FFFFFF", features: ["fuzzy"] },
  "polyporus_squamosus": { shape: "bracket", cap: "#DEB887", stem: "#FFFFFF", features: ["dots"] },
  "laetiporus_sulphureus": { shape: "tubular", cap: "#FFD700", stem: "#FFFFFF", features: [] },
  "lactarius_quietus": { shape: "tubular", cap: "#8B4513", stem: "#FFFFFF", features: [] },
  "lactifluus_volemus": { shape: "tubular", cap: "#CD5C5C", stem: "#FFFFFF", features: [] },
  "lactarius_piperatus": { shape: "funnel", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "lactarius_subdulcis": { shape: "tubular", cap: "#8B4513", stem: "#FFFFFF", features: [] },
  "boletus_aereus": { shape: "tubular", cap: "#4E342E", stem: "#FFFFFF", features: [] },
  "rubroboletus_lupinus": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "butyriboletus_appendiculatus": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "butyriboletus_regius": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "butyriboletus_subappendiculatus": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "butyriboletus_fuscoroseus": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "rubroboletus_rhodoxanthus": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "rubroboletus_satanas": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "butyriboletus_fechtneri": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "rubroboletus_rubrosanguineus": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "phallus_duplicatus": { shape: "tubular", cap: "#FFFFFF", stem: "#FFFFFF", features: [] },
  "hemileccinum_depilatum": { shape: "tubular", cap: "#CD853F", stem: "#FFFFFF", features: [] },
  "hericium_erinaceus": { shape: "tubular", cap: "#FFFFFF", stem: "#FFFFFF", features: ["spines"] },
  "hericium_coralloides": { shape: "tubular", cap: "#FFFFFF", stem: "#FFFFFF", features: ["spines"] },
  "hygrocybe_calyptriformis": { shape: "tubular", cap: "#FF69B4", stem: "#FFFFFF", features: [] },
  "gomphus_clavatus": { shape: "tubular", cap: "#CD853F", stem: "#FFFFFF", features: [] },
  "grifola_frondosa": { shape: "tubular", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "morchella_steppicola": { shape: "tubular", cap: "#F5F5DC", stem: "#FFFFFF", features: ["brain"] },
  "pseudocolus_fusiformis": { shape: "tubular", cap: "#FF0000", stem: "#FFFFFF", features: [] },
  "catathelasma_imperiale": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "anthurus_archeri": { shape: "tubular", cap: "#FF0000", stem: "#FFFFFF", features: [] },
  "clavariadelphus_pistillaris": { shape: "tubular", cap: "#FFA500", stem: "#FFFFFF", features: [] },
  "lyophyllum_favrei": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "helvella_monachella": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "suillus_plorans": { shape: "tubular", cap: "#2F4F4F", stem: "#FFFFFF", features: [] },
  "myriostoma_coliforme": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "boletus_parasiticus": { shape: "tubular", cap: "#6D4C41", stem: "#FFFFFF", features: [] },
  "amanita_caesarea": { shape: "amanita", cap: "#FF4500", stem: "#FFD700", features: ["ring"] },
  "amanita_strobiliformis": { shape: "amanita", cap: "#FFFFFF", stem: "#FFFFFF", features: ["ring"] },
  "chalciporus_rubinus": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "clathrus_ruber": { shape: "tubular", cap: "#FF0000", stem: "#FFFFFF", features: [] },
  "tricholoma_colossus": { shape: "tubular", cap: "#FFFFFF", stem: "#FFFFFF", features: [] },
  "tricholoma_focale": { shape: "tubular", cap: "#FFF8DC", stem: "#FFFFFF", features: [] },
  "sarcosoma_globosum": { shape: "tubular", cap: "#2F4F4F", stem: "#2F4F4F", features: [] },
  "russula_turci": { shape: "tubular", cap: "#9370DB", stem: "#FFFFFF", features: [] },
  "scleroderma_geaster": { shape: "tubular", cap: "#A9A9A9", stem: "#FFFFFF", features: [] },
  "sparassis_crispa": { shape: "tubular", cap: "#FFF8DC", stem: "#FFFFFF", features: [] },
  "polyporus_umbellatus": { shape: "tubular", cap: "#FFF8DC", stem: "#FFFFFF", features: [] },
  "tuber_aestivum": { shape: "tubular", cap: "#000000", stem: "#000000", features: [] },
  "phellorinia_herculeana": { shape: "tubular", cap: "#2F4F4F", stem: "#2F4F4F", features: [] },
  "phaeolepiota_aurea": { shape: "tubular", cap: "#FFD700", stem: "#FFFFFF", features: [] },
  "phylloporus_pelletieri": { shape: "tubular", cap: "#D2691E", stem: "#FFFFFF", features: [] },
  "lactarius_lignyotus": { shape: "tubular", cap: "#000000", stem: "#FFFFFF", features: [] },
  "strobilomyces_strobilaceus": { shape: "tubular", cap: "#696969", stem: "#696969", features: [] },
  "amanita_muscaria": { shape: "amanita", cap: "#E32636", stem: "#FFFFFF", features: ["ring", "dots"] },
  "amanita_pantherina": { shape: "amanita", cap: "#8B4513", stem: "#FFFFFF", features: ["ring", "dots"] },
  "amanita_phalloides": { shape: "amanita", cap: "#8FBC8F", stem: "#FFFFFF", features: ["ring"] },
  "amanita_verna": { shape: "amanita", cap: "#FFFFFF", stem: "#FFFFFF", features: ["ring"] },
  "amanita_virosa": { shape: "amanita", cap: "#FFFFFF", stem: "#FFFFFF", features: ["ring"] },
  "clitocybe_candicans": { shape: "tubular", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "clitocybe_dealbata": { shape: "tubular", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "entoloma_sinuatum": { shape: "tubular", cap: "#DAA520", stem: "#FFFFFF", features: [] },
  "galerina_marginata": { shape: "tubular", cap: "#CD853F", stem: "#FFFFFF", features: [] },
  "gyromitra_esculenta": { shape: "tubular", cap: "#8B4513", stem: "#FFFFFF", features: ["brain"] },
  "hygrophoropsis_aurantiaca": { shape: "tubular", cap: "#FFA500", stem: "#FFA500", features: [] },
  "inocybe_erubescens": { shape: "tubular", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "inocybe_geophylla": { shape: "tubular", cap: "#F0F8FF", stem: "#FFFFFF", features: [] },
  "paxillus_involutus": { shape: "tubular", cap: "#CD853F", stem: "#FFFFFF", features: [] },
};

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

// ---------------------------------------------------------------------------
// 7 Базових SVG-шаблонів (stroke="#333", stroke-width="2" на всіх path)
// ---------------------------------------------------------------------------
function templateTubular({ size, capColor, stemColor, features }) {
  const dotsHtml = features.includes("dots")
    ? `<circle cx="26" cy="48" r="2" fill="#000000" />
       <circle cx="30" cy="50" r="2" fill="#000000" />
       <circle cx="34" cy="46" r="2" fill="#000000" />
       <circle cx="38" cy="52" r="2" fill="#000000" />`
    : "";
  const slimyHtml = features.includes("slimy")
    ? `<ellipse cx="32" cy="34" rx="14" ry="3" fill="#FFFFFF" opacity="0.6" stroke="none"/>`
    : "";
  const fuzzyHtml = features.includes("fuzzy")
    ? `<path d="M14 34 Q16 32 18 34 M48 34 Q46 32 44 34" stroke="#666" stroke-width="1" fill="none" stroke-linecap="round"/>`
    : "";
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M26 40 Q24 54 28 58 L36 58 Q40 54 38 40 Z" fill="${stemColor}" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
  ${dotsHtml}
  <path d="M14 34 C14 16 50 16 50 34 C50 38 44 42 32 42 C20 42 14 38 14 34 Z" fill="${capColor}" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
  ${fuzzyHtml}
  <path d="M18 36 Q32 42 46 36" stroke="#333" stroke-width="2" opacity="0.3" fill="none"/>
  ${slimyHtml}
</svg>`;
}

function templateGilled({ size, capColor, stemColor, features }) {
  const ringHtml = features.includes("ring")
    ? `<path d="M24 42 Q32 48 42 42 Q38 40 32 40 Q26 40 24 42 Z" fill="#FFFFFF" stroke="#333" stroke-width="2" stroke-linejoin="round"/>`
    : "";
  const dotsHtml = features.includes("dots")
    ? `<circle cx="26" cy="46" r="1.5" fill="#000000" />
       <circle cx="30" cy="48" r="1.5" fill="#000000" />
       <circle cx="34" cy="46" r="1.5" fill="#000000" />`
    : "";
  const gillsHtml = `
    <path d="M24 34 L24 38" stroke="#555" stroke-width="1.5" stroke-linecap="round"/>
    <path d="M28 34 L28 38" stroke="#555" stroke-width="1.5" stroke-linecap="round"/>
    <path d="M32 34 L32 38" stroke="#555" stroke-width="1.5" stroke-linecap="round"/>
    <path d="M36 34 L36 38" stroke="#555" stroke-width="1.5" stroke-linecap="round"/>
    <path d="M40 34 L40 38" stroke="#555" stroke-width="1.5" stroke-linecap="round"/>
  `;
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M26 40 Q24 54 28 58 L36 58 Q40 54 38 40 Z" fill="${stemColor}" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
  ${ringHtml}
  <path d="M14 34 C14 16 50 16 50 34 C50 38 44 42 32 42 C20 42 14 38 14 34 Z" fill="${capColor}" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
  ${gillsHtml}
  ${dotsHtml}
</svg>`;
}

function templateFunnel({ size, capColor, stemColor, features }) {
  const slimyHtml = features.includes("slimy")
    ? `<ellipse cx="32" cy="30" rx="14" ry="3" fill="#FFFFFF" opacity="0.6" stroke="none"/>`
    : "";
  const fuzzyHtml = features.includes("fuzzy")
    ? `<path d="M12 28 Q14 26 16 28 M52 28 Q50 26 48 28" stroke="#666" stroke-width="1" fill="none" stroke-linecap="round"/>`
    : "";
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M18 26 C14 14 50 14 46 26 C44 32 38 36 36 42 L36 56 L28 56 L28 42 C26 36 20 32 18 26 Z" fill="${capColor}" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
  ${fuzzyHtml}
  <ellipse cx="32" cy="24" rx="10" ry="4" fill="rgba(0,0,0,0.15)" stroke="#333" stroke-width="1.5"/>
  ${slimyHtml}
  <path d="M27 42 L27 56 M37 42 L37 56" stroke="${stemColor}" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;
}

function templateAmanita({ size, capColor, stemColor, features }) {
  const dotsHtml = features.includes("dots")
    ? `<circle cx="24" cy="22" r="3" fill="#FFF" stroke="#333" stroke-width="1"/>
       <circle cx="38" cy="20" r="4" fill="#FFF" stroke="#333" stroke-width="1"/>
       <circle cx="32" cy="30" r="3" fill="#FFF" stroke="#333" stroke-width="1"/>
       <circle cx="44" cy="28" r="2" fill="#FFF" stroke="#333" stroke-width="1"/>`
    : "";
  const ringHtml = features.includes("ring")
    ? `<path d="M22 42 Q32 48 42 42 Q38 40 32 40 Q26 40 22 42 Z" fill="#FFF" stroke="#333" stroke-width="2" stroke-linejoin="round"/>`
    : "";
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M28 38 L26 56 L38 56 L36 38 Z" fill="${stemColor}" stroke="#333" stroke-width="2"/>
  ${ringHtml}
  <path d="M12 32 C12 12 52 12 52 32 C52 36 44 38 32 38 C20 38 12 36 12 32 Z" fill="${capColor}" stroke="#333" stroke-width="2"/>
  ${dotsHtml}
</svg>`;
}

function templateMorel({ size, capColor, stemColor, features }) {
  const brainHtml = features.includes("brain")
    ? `<path d="M20 26 Q24 22 28 26 Q32 22 36 26 Q40 22 44 26 Q40 30 36 30 Q32 34 28 30 Q24 34 20 26 Z" fill="${capColor}" stroke="#333" stroke-width="2" stroke-linejoin="round"/>`
    : `<path d="M20 26 Q24 22 28 26 Q32 22 36 26 Q40 22 44 26 Q40 34 36 34 Q32 38 28 34 Q24 34 20 26 Z" fill="${capColor}" stroke="#333" stroke-width="2" stroke-linejoin="round"/>`;
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg">
  ${brainHtml}
  <path d="M26 38 L26 56 M38 38 L38 56" stroke="${stemColor}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;
}

function templateBracket({ size, capColor, stemColor, features }) {
  const dotsHtml = features.includes("dots")
    ? `<circle cx="24" cy="28" r="2" fill="#000000" />
       <circle cx="36" cy="28" r="2" fill="#000000" />
       <circle cx="28" cy="32" r="2" fill="#000000" />`
    : "";
  const ringHtml = features.includes("ring")
    ? `<path d="M22 36 Q32 42 42 36 Q38 34 32 36 Q26 34 22 36 Z" fill="#FFF" stroke="#333" stroke-width="2" stroke-linejoin="round"/>`
    : "";
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M14 34 Q32 44 50 34 Q32 48 14 34 Z" fill="${capColor}" stroke="#333" stroke-width="2" stroke-linejoin="round"/>
  ${ringHtml}
  ${dotsHtml}
</svg>`;
}

function templatePuffball({ size, capColor, stemColor, features }) {
  const spinesHtml = features.includes("spines")
    ? `<path d="M18 26 L16 22 M30 22 L28 18 M40 22 L42 26 M46 30 L48 32" stroke="#999" stroke-width="2" stroke-linecap="round"/>`
    : "";
  return `
<svg viewBox="0 0 64 64" width="${size}" height="${size}" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="32" cy="32" r="18" fill="${capColor}" stroke="#333" stroke-width="2"/>
  ${spinesHtml}
  <path d="M28 46 L28 56 M36 46 L36 56" stroke="${stemColor}" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;
}

function renderTemplate(shape, { size, capColor, stemColor, features }) {
  switch (shape) {
    case "gilled": return templateGilled({ size, capColor, stemColor, features });
    case "funnel": return templateFunnel({ size, capColor, stemColor, features });
    case "amanita": return templateAmanita({ size, capColor, stemColor, features });
    case "morel": return templateMorel({ size, capColor, stemColor, features });
    case "bracket": return templateBracket({ size, capColor, stemColor, features });
    case "puffball": return templatePuffball({ size, capColor, stemColor, features });
    case "tubular":
    default: return templateTubular({ size, capColor, stemColor, features });
  }
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

  const visual = MUSHROOM_VISUALS[resolved];
  if (!visual) {
    return fallbackSvg(resolved);
  }

  return renderTemplate(visual.shape, {
    size,
    capColor: visual.cap,
    stemColor: visual.stem,
    features: visual.features || [],
  });
}

window.getMushroomIconHtml = getMushroomIconHtml;
