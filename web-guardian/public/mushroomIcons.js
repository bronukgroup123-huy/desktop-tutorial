/**
 * mushroomIcons.js
 * Кастомні SVG-іконки для видів грибів, що мають фото (has_photo: true).
 * viewBox="0 0 64 64" для всіх іконок. Експортує функцію getMushroomIconHtml(species)
 * яка повертає HTML-рядок SVG для використання у vanilla-JS коді (landing.html).
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

function colorsFor(species) {
  if (species.startsWith("amanita_")) return { cap: "#e53935", stem: "#fffde7", accent: "#ffffff" };
  if (species.startsWith("boletus_")) return { cap: "#6d4c41", stem: "#efebe9", accent: "#8d6e63" };
  if (species.includes("rubroboletus") || species.includes("butyriboletus")) return { cap: "#5d4037", stem: "#d7ccc8", accent: "#4e342e" };
  if (species.includes("cantharellus") || species.includes("craterellus")) return { cap: "#fb8c00", stem: "#ffecb3", accent: "#ffcc00" };
  if (species.includes("suillus")) return { cap: "#bcaaa4", stem: "#d7ccc8", accent: "#ffd54f" };
  if (species.includes("leccinum")) return { cap: "#a1887f", stem: "#cfd8dc", accent: "#78909c" };
  if (species.includes("lactarius") || species.includes("lactifluus")) return { cap: "#bf360c", stem: "#efebe9", accent: "#ff7043" };
  if (species.startsWith("russula_")) return { cap: "#ffcc80", stem: "#fff9c4", accent: "#ffd54f" };
  if (species.startsWith("tricholoma_")) return { cap: "#795548", stem: "#d7ccc8", accent: "#6d4c41" };
  if (species.includes("armillaria") || species.includes("kuehneromyces") || species.includes("hypholoma")) return { cap: "#ffb300", stem: "#fffde7", accent: "#ffeb3b" };
  if (species.includes("macrolepiota")) return { cap: "#d7ccc8", stem: "#f5f5f5", accent: "#efebe9" };
  if (species.includes("cortinarius") || species.includes("inocybe")) return { cap: "#7986cb", stem: "#e8eaf6", accent: "#c5cae9" };
  if (species.includes("pleurotus")) return { cap: "#eceff1", stem: "#cfd8dc", accent: "#b0bec5" };
  if (species.includes("polyporus") || species.includes("laetiporus") || species.includes("grifola") || species.includes("sparassis")) return { cap: "#8d6e63", stem: "#6d4c41", accent: "#a1887f" };
  if (species.includes("morchella") || species.includes("gyromitra")) return { cap: "#d7ccc8", stem: "#d7ccc8", accent: "#bcaaa4" };
  if (species.includes("phallus") || species.includes("pseudocolus") || species.includes("anthurus")) return { cap: "#e53935", stem: "#fffde7", accent: "#fff176" };
  if (species.startsWith("clitocybe_") || species.startsWith("collybia_") || species.startsWith("entoloma_") || species.startsWith("galerina_")) return { cap: "#795548", stem: "#efebe9", accent: "#6d4c41" };
  if (species.includes("hydnum")) return { cap: "#a1887f", stem: "#cfd8dc", accent: "#78909c" };
  if (species.includes("lycoperdon") || species.includes("myriostoma") || species.includes("scleroderma")) return { cap: "#cfd8dc", stem: "#eceff1", accent: "#b0bec5" };
  if (species.includes("clavulina") || species.includes("ramaria") || species.includes("clavariadelphus")) return { cap: "#bcaaa4", stem: "#d7ccc8", accent: "#a1887f" };
  if (species.includes("helvella")) return { cap: "#424242", stem: "#616161", accent: "#757575" };
  if (species.includes("tuber")) return { cap: "#5d4037", stem: "#6d4c41", accent: "#3e2723" };
  if (species.includes("strobilomyces")) return { cap: "#424242", stem: "#424242", accent: "#212121" };
  if (species.includes("hemileccinum")) return { cap: "#a1887f", stem: "#cfd8dc", accent: "#78909c" };
  if (species.includes("hericium")) return { cap: "#fffde7", stem: "#fffde7", accent: "#ffecb3" };
  if (species.includes("hygrocybe")) return { cap: "#e53935", stem: "#fffde7", accent: "#ffeb3b" };
  if (species.includes("gomphus")) return { cap: "#795548", stem: "#d7ccc8", accent: "#6d4c41" };
  if (species.includes("albatrellus")) return { cap: "#cfd8dc", stem: "#f5f5f5", accent: "#eceff1" };
  if (species.includes("imleria")) return { cap: "#6d4c41", stem: "#d7ccc8", accent: "#5d4037" };
  if (species.includes("phaeolepiota") || species.includes("phylloporus")) return { cap: "#fb8c00", stem: "#ffecb3", accent: "#ffcc00" };
  if (species.includes("phellorinia") || species.includes("sarcosoma")) return { cap: "#424242", stem: "#424242", accent: "#212121" };
  if (species.includes("catathelasma")) return { cap: "#d7ccc8", stem: "#f5f5f5", accent: "#eceff1" };
  if (species.includes("agaricus")) return { cap: "#f5f5f5", stem: "#ffffff", accent: "#e0e0e0" };
  return { cap: "#8d6e63", stem: "#d7ccc8", accent: "#ffeb3b" };
}

function styleFor(species) {
  if (species.startsWith("amanita_")) return "cap-stem";
  if (species.startsWith("boletus_") || species.includes("rubroboletus") || species.includes("butyriboletus")) return "cap-stem";
  if (species.includes("leccinum")) return "cap-stem";
  if (species.includes("cantharellus") || species.includes("craterellus")) return "funnel";
  if (species.includes("suillus")) return "cap-stem";
  if (species.includes("lactarius") || species.includes("lactifluus")) return "funnel";
  if (species.startsWith("russula_")) return "cap-stem";
  if (species.startsWith("tricholoma_")) return "cap-stem";
  if (species.includes("armillaria") || species.includes("kuehneromyces") || species.includes("hypholoma")) return "cap-stem";
  if (species.includes("macrolepiota")) return "flat-cap";
  if (species.includes("cortinarius") || species.includes("inocybe")) return "cap-stem";
  if (species.includes("pleurotus")) return "bracket";
  if (species.includes("polyporus") || species.includes("laetiporus") || species.includes("grifola") || species.includes("sparassis")) return "bracket";
  if (species.includes("morchella") || species.includes("gyromitra")) return "morel";
  if (species.includes("phallus") || species.includes("pseudocolus") || species.includes("anthurus")) return "stinkhorn";
  if (species.startsWith("clitocybe_") || species.startsWith("collybia_") || species.startsWith("entoloma_") || species.startsWith("galerina_")) return "cap-stem";
  if (species.includes("hydnum")) return "cap-stem";
  if (species.includes("lycoperdon") || species.includes("myriostoma") || species.includes("scleroderma")) return "puffball";
  if (species.includes("clavulina") || species.includes("ramaria") || species.includes("clavariadelphus")) return "coral";
  if (species.includes("helvella")) return "morel";
  if (species.includes("tuber")) return "truffle";
  if (species.includes("strobilomyces")) return "globular";
  if (species.includes("hemileccinum")) return "cap-stem";
  if (species.includes("hericium")) return "globular";
  if (species.includes("hygrocybe")) return "cap-stem";
  if (species.includes("gomphus")) return "funnel";
  if (species.includes("albatrellus")) return "cap-stem";
  if (species.includes("imleria")) return "cap-stem";
  if (species.includes("phaeolepiota") || species.includes("phylloporus")) return "cap-stem";
  if (species.includes("phellorinia") || species.includes("sarcosoma")) return "globular";
  if (species.includes("catathelasma")) return "cap-stem";
  if (species.includes("agaricus")) return "cap-stem";
  return "cap-stem";
}

function hasRingFor(species) {
  if (species.includes("armillaria") || species.includes("kuehneromyces") || species.includes("hypholoma")) return true;
  if (species.startsWith("amanita_")) return true;
  if (species.includes("macrolepiota")) return true;
  if (species.includes("lepiota")) return true;
  return false;
}

function escHtml(unsafe) {
  return unsafe
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function buildSvgString({ capColor, stemColor, accentColor, hasRing, style }) {
  const cx = 32, capY = 22, stemX = 27, stemY = 34, stemH = 24, stemW = 10;
  let body = "";

  if (style === "cap-stem") {
    body += `<path d="M${cx-20} ${capY} Q${cx} ${capY-14} ${cx+20} ${capY} Q${cx} ${capY+10} ${cx-20} ${capY} Z" fill="${capColor}" stroke="#3e2723" stroke-width="1.5" />`;
    body += `<rect x="${stemX}" y="${stemY}" width="${stemW}" height="${stemH}" rx="2" fill="${stemColor}" stroke="#3e2723" stroke-width="1.5" />`;
    if (hasRing) {
      body += `<path d="M${stemX-2} ${stemY+4} Q${cx} ${stemY} ${stemX+stemW+2} ${stemY+4} Z" fill="none" stroke="${accentColor}" stroke-width="2.5" stroke-linecap="round" />`;
    }
  } else if (style === "flat-cap") {
    body += `<path d="M${cx-18} ${capY} Q${cx} ${capY-8} ${cx+18} ${capY} Q${cx} ${capY+6} ${cx-18} ${capY} Z" fill="${capColor}" stroke="#3e2723" stroke-width="1.5" />`;
    body += `<rect x="${stemX}" y="${stemY}" width="${stemW}" height="${stemH}" rx="2" fill="${stemColor}" stroke="#3e2723" stroke-width="1.5" />`;
  } else if (style === "funnel") {
    body += `<path d="M${cx-20} ${capY} Q${cx} ${capY-6} ${cx+20} ${capY} Q${cx} ${capY+14} ${cx-20} ${capY} Z" fill="${capColor}" stroke="#3e2723" stroke-width="1.5" />`;
    body += `<path d="M${cx-8} ${capY+4} Q${cx} ${capY+10} ${cx+8} ${capY+4} Z" fill="none" stroke="#5d4037" stroke-width="2" stroke-linecap="round" />`;
    body += `<rect x="${stemX}" y="${stemY}" width="${stemW}" height="${stemH}" rx="2" fill="${stemColor}" stroke="#3e2723" stroke-width="1.5" />`;
  } else if (style === "coral") {
    body += `<path d="M${cx-16} ${capY} Q${cx-6} ${capY-10} ${cx} ${capY} Q${cx+6} ${capY-10} ${cx+16} ${capY} Z" fill="${capColor}" stroke="#3e2723" stroke-width="1.5" />`;
    body += `<path d="M${cx-10} ${capY} L${cx-10} ${capY+12}" stroke="${capColor}" stroke-width="5" stroke-linecap="round" />`;
    body += `<path d="M${cx+10} ${capY} L${cx+10} ${capY+12}" stroke="${capColor}" stroke-width="5" stroke-linecap="round" />`;
    body += `<rect x="${stemX}" y="${stemY}" width="${stemW}" height="${stemH}" rx="2" fill="${stemColor}" stroke="#3e2723" stroke-width="1.5" />`;
  } else if (style === "puffball") {
    body += `<circle cx="${cx}" cy="${capY+10}" r="18" fill="${capColor}" stroke="#3e2723" stroke-width="1.5" />`;
    body += `<rect x="${stemX}" y="${stemY}" width="${stemW}" height="${stemH}" rx="2" fill="${stemColor}" stroke="#3e2723" stroke-width="1.5" />`;
  } else if (style === "star") {
    body += `<path d="M${cx} ${capY-8} L${cx+4} ${capY+4} L${cx+14} ${capY+6} L${cx+6} ${capY+10} L${cx+10} ${capY+16} L${cx} ${capY+12} L${cx-10} ${capY+16} L${cx-6} ${capY+10} L${cx-14} ${capY+6} L${cx-4} ${capY+4} Z" fill="${capColor}" stroke="#3e2723" stroke-width="1.5" />`;
    body += `<rect x="${stemX}" y="${stemY}" width="${stemW}" height="${stemH}" rx="2" fill="${stemColor}" stroke="#3e2723" stroke-width="1.5" />`;
  } else if (style === "bracket") {
    body += `<path d="M${cx-18} ${capY+2} Q${cx} ${capY+12} ${cx+18} ${capY+2} Q${cx} ${capY+20} ${cx-18} ${capY+2} Z" fill="${capColor}" stroke="#3e2723" stroke-width="1.5" />`;
    body += `<path d="M${cx-14} ${capY+6} Q${cx} ${capY+12} ${cx+14} ${capY+6} Z" fill="none" stroke="#5d4037" stroke-width="2" />`;
  } else if (style === "morel") {
    body += `<path d="M${cx-14} ${capY} Q${cx} ${capY-14} ${cx+14} ${capY} Q${cx} ${capY+6} ${cx-14} ${capY} Z" fill="${capColor}" stroke="#3e2723" stroke-width="1.5" />`;
    body += `<path d="M${cx-10} ${capY+2} L${cx-10} ${capY+10} M${cx-4} ${capY+2} L${cx-4} ${capY+10} M${cx+2} ${capY+2} L${cx+2} ${capY+10} M${cx+8} ${capY+2} L${cx+8} ${capY+10}" stroke="#5d4037" stroke-width="2" stroke-linecap="round" />`;
    body += `<rect x="${stemX}" y="${stemY}" width="${stemW}" height="${stemH}" rx="2" fill="${stemColor}" stroke="#3e2723" stroke-width="1.5" />`;
  } else if (style === "stinkhorn") {
    body += `<path d="M${cx-12} ${capY+2} Q${cx} ${capY-12} ${cx+12} ${capY+2} Q${cx} ${capY+8} ${cx-12} ${capY+2} Z" fill="${capColor}" stroke="#3e2723" stroke-width="1.5" />`;
    body += `<rect x="${stemX}" y="${stemY}" width="${stemW}" height="${stemH}" rx="2" fill="${stemColor}" stroke="#3e2723" stroke-width="1.5" />`;
  } else if (style === "truffle") {
    body += `<path d="M${cx-16} ${capY+8} Q${cx} ${capY-4} ${cx+16} ${capY+8} Q${cx} ${capY+18} ${cx-16} ${capY+8} Z" fill="${capColor}" stroke="#3e2723" stroke-width="1.5" />`;
    body += `<path d="M${cx-10} ${capY+10} Q${cx} ${capY+14} ${cx+10} ${capY+10} Z" fill="none" stroke="#5d4037" stroke-width="2" />`;
  } else if (style === "globular") {
    body += `<circle cx="${cx}" cy="${capY+8}" r="16" fill="${capColor}" stroke="#3e2723" stroke-width="1.5" />`;
  }

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none">${body}</svg>`;
}

function detailedSvg(species) {
  switch (species) {
    case "boletus_edulis": {
      const { cap, stem, accent } = colorsFor(species);
      return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none">
        <path d="M20 30 Q32 18 44 30 Q32 36 20 30 Z" fill="${cap}" stroke="#3e2723" stroke-width="1.5" />
        <ellipse cx="32" cy="30" rx="12" ry="6" fill="${stem}" opacity="0.6" />
        <path d="M27 34 L27 56 M37 34 L37 56" stroke="${stem}" stroke-width="9" stroke-linecap="round" />
        <path d="M27 56 L27 58 M37 56 L37 58" stroke="#3e2723" stroke-width="1" />
        <path d="M24 24 Q32 20 40 24 M26 28 Q32 26 38 28" fill="none" stroke="${accent}" stroke-width="1.5" stroke-linecap="round" />
      </svg>`;
    }
    case "cantharellus_cibarius": {
      const { cap, stem, accent } = colorsFor(species);
      return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none">
        <path d="M14 26 Q32 14 50 26 Q32 34 14 26 Z" fill="${cap}" stroke="#3e2723" stroke-width="1.5" />
        <path d="M24 30 Q32 36 40 30 Z" fill="none" stroke="#e65100" stroke-width="2" stroke-linecap="round" />
        <path d="M27 36 Q32 50 37 36 Q32 44 27 36 Z" fill="${stem}" stroke="#3e2723" stroke-width="1.5" />
        <path d="M20 22 Q32 30 44 22 M18 26 Q32 34 46 26" fill="none" stroke="${accent}" stroke-width="1.5" stroke-linecap="round" />
      </svg>`;
    }
    case "leccinum_scabrum": {
      const { cap, stem, accent } = colorsFor(species);
      return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none">
        <path d="M16 28 Q32 16 48 28 Q32 36 16 28 Z" fill="${cap}" stroke="#3e2723" stroke-width="1.5" />
        <path d="M25 42 L25 46 M29 44 L29 48 M33 42 L33 46 M37 44 L37 48 M39 42 L39 46" stroke="#5d4037" stroke-width="2.5" stroke-linecap="round" />
        <path d="M26 36 L26 56 M38 36 L38 56" stroke="${stem}" stroke-width="10" stroke-linecap="round" />
        <path d="M20 24 Q32 18 44 24" fill="none" stroke="${accent}" stroke-width="1.5" stroke-linecap="round" />
      </svg>`;
    }
    case "armillaria_mellea": {
      const { cap, stem, accent } = colorsFor(species);
      return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none">
        <path d="M16 26 Q32 14 48 26 Q32 34 16 26 Z" fill="${cap}" stroke="#3e2723" stroke-width="1.5" />
        <path d="M23 32 L23 54 M41 32 L41 54" stroke="${stem}" stroke-width="7" stroke-linecap="round" />
        <path d="M21 32 Q32 28 43 32" fill="none" stroke="${accent}" stroke-width="3" stroke-linecap="round" />
        <path d="M20 22 Q32 26 44 22" fill="none" stroke="#3e2723" stroke-width="1" stroke-linecap="round" />
      </svg>`;
    }
    case "lactarius_deliciosus": {
      const { cap, stem, accent } = colorsFor(species);
      return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none">
        <path d="M14 28 Q32 16 50 28 Q32 36 14 28 Z" fill="${cap}" stroke="#3e2723" stroke-width="1.5" />
        <path d="M22 32 Q32 38 42 32 Z" fill="none" stroke="#b71c1c" stroke-width="2.5" stroke-linecap="round" />
        <path d="M26 38 Q32 46 38 38 Z" fill="${stem}" opacity="0.8" stroke="#3e2723" stroke-width="1.5" />
        <path d="M27 40 L27 54 M37 40 L37 54" stroke="${stem}" stroke-width="8" stroke-linecap="round" />
        <path d="M20 24 Q32 28 44 24" fill="none" stroke="${accent}" stroke-width="1.5" stroke-linecap="round" />
      </svg>`;
    }
    case "amanita_muscaria": {
      const { cap, stem, accent } = colorsFor(species);
      return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none">
        <path d="M14 26 Q32 12 50 26 Q32 36 14 26 Z" fill="${cap}" stroke="#3e2723" stroke-width="1.5" />
        <circle cx="24" cy="24" r="3" fill="${accent}" />
        <circle cx="40" cy="22" r="3" fill="${accent}" />
        <circle cx="30" cy="30" r="3" fill="${accent}" />
        <circle cx="46" cy="28" r="3" fill="${accent}" />
        <path d="M24 40 L24 56 M40 40 L40 56" stroke="${stem}" stroke-width="10" stroke-linecap="round" />
        <path d="M22 32 Q32 28 42 32" fill="none" stroke="${accent}" stroke-width="2" stroke-linecap="round" />
      </svg>`;
    }
    default:
      return null;
  }
}

function fallbackSvg(title) {
  const safeTitle = escHtml(title);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" aria-label="${safeTitle}" role="img">
    <circle cx="32" cy="32" r="20" fill="#cfd8dc" />
    <path d="M22 38 Q32 26 42 38" stroke="#90a4ae" stroke-width="4" stroke-linecap="round" />
    <path d="M27 46 L27 56 M37 46 L37 56" stroke="#b0bec5" stroke-width="6" stroke-linecap="round" />
    <title>${safeTitle}</title>
  </svg>`;
}

/**
 * Повертає HTML-рядок SVG-іконки для вида.
 * @param {string} species - програмне ім'я виду (id)
 * @param {string} title - ARIA/title
 * @returns {string} HTML-рядок <svg>...</svg>
 */
function getMushroomIconHtml(species, title = "") {
  if (!species || !SPECIES_WITH_PHOTO.has(species)) {
    return fallbackSvg(title || "Невідомий гриб");
  }
  const detailed = detailedSvg(species);
  if (detailed) return detailed;
  const { cap: capColor, stem: stemColor, accent: accentColor } = colorsFor(species);
  const style = styleFor(species);
  const hasRing = hasRingFor(species);
  return buildSvgString({ capColor, stemColor, accentColor, hasRing, style });
}

window.getMushroomIconHtml = getMushroomIconHtml;
