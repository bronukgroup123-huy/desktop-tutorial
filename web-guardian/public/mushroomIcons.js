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
// ДЕТАЛІЗОВАНІ SVG-ІКОНКИ (20 видів з градієнтами, чіткими контурами та деталями)
// Ключі за id з mushroom_catalog.json (підкреслення)
// ---------------------------------------------------------------------------
const DETAILED_SVGS = {
  // 1. Білий гриб (Boletus edulis)
  "boletus_edulis": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-edulis" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#A0522D" />
          <stop offset="100%" stop-color="#5C2E0B" />
        </linearGradient>
        <linearGradient id="stem-edulis" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#E8DCC4" />
          <stop offset="50%" stop-color="#FFF8DC" />
          <stop offset="100%" stop-color="#D2B48C" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="14" ry="4" fill="rgba(0,0,0,0.15)" />
      <path d="M24 40 Q20 55 26 58 L38 58 Q44 55 40 40 Z" fill="url(#stem-edulis)" />
      <path d="M26 46 Q32 50 38 46 M25 50 Q32 54 39 50 M27 42 Q32 45 37 42" stroke="#D2B48C" stroke-width="1.5" fill="none" />
      <path d="M10 32 C10 15 54 15 54 32 C54 38 44 42 32 42 C20 42 10 38 10 32 Z" fill="url(#cap-edulis)" />
      <path d="M18 24 Q32 16 46 24" stroke="rgba(255,255,255,0.3)" stroke-width="3" fill="none" stroke-linecap="round"/>
    </svg>`,

  // 2. Лисичка (Cantharellus cibarius)
  "cantharellus_cibarius": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-canth" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#FFD700" />
          <stop offset="100%" stop-color="#FFA500" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="10" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M14 28 C10 16 54 16 50 28 C48 34 40 40 38 48 L38 56 L26 56 L26 48 C24 40 16 34 14 28 Z" fill="url(#cap-canth)" />
      <path d="M26 48 Q32 52 38 48" stroke="#E69500" stroke-width="2" fill="none" />
      <path d="M14 28 Q18 32 22 28 Q26 32 32 28 Q38 32 42 28 Q46 32 50 28" stroke="#E69500" stroke-width="2" fill="none" />
    </svg>`,

  // 3. Підберезник (Leccinum scabrum)
  "leccinum_scabrum": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-leccinum" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#8B7355" />
          <stop offset="100%" stop-color="#4A3728" />
        </linearGradient>
        <linearGradient id="stem-leccinum" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#D3D3D3" />
          <stop offset="50%" stop-color="#F5F5F5" />
          <stop offset="100%" stop-color="#A9A9A9" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="12" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M25 40 Q22 55 26 58 L38 58 Q42 55 39 40 Z" fill="url(#stem-leccinum)" />
      <circle cx="28" cy="45" r="1.5" fill="#333" />
      <circle cx="35" cy="48" r="1.5" fill="#333" />
      <circle cx="27" cy="52" r="1.5" fill="#333" />
      <circle cx="36" cy="54" r="1.5" fill="#333" />
      <circle cx="31" cy="50" r="1.5" fill="#333" />
      <path d="M12 32 C12 20 52 20 52 32 C52 38 42 42 32 42 C22 42 12 38 12 32 Z" fill="url(#cap-leccinum)" />
      <path d="M20 26 Q32 22 44 26" stroke="rgba(255,255,255,0.2)" stroke-width="2" fill="none" stroke-linecap="round"/>
    </svg>`,

  // 4. Підосичник (Leccinum aurantiacum)
  "leccinum_aurantiacum": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-aur" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#FF6347" />
          <stop offset="100%" stop-color="#B22222" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="12" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M25 40 Q22 55 26 58 L38 58 Q42 55 39 40 Z" fill="#E0E0E0" />
      <circle cx="28" cy="45" r="1.5" fill="#555" />
      <circle cx="35" cy="48" r="1.5" fill="#555" />
      <circle cx="27" cy="52" r="1.5" fill="#555" />
      <circle cx="36" cy="54" r="1.5" fill="#555" />
      <path d="M12 32 C12 20 52 20 52 32 C52 38 42 42 32 42 C22 42 12 38 12 32 Z" fill="url(#cap-aur)" />
      <path d="M20 26 Q32 22 44 26" stroke="rgba(255,255,255,0.3)" stroke-width="2" fill="none" stroke-linecap="round"/>
    </svg>`,

  // 5. Маслюк (Suillus luteus)
  "suillus_luteus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-sui" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#D2691E" />
          <stop offset="100%" stop-color="#8B4513" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="10" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M27 38 Q26 55 28 58 L36 58 Q38 55 37 38 Z" fill="#FFD700" />
      <path d="M23 44 Q32 48 41 44 Q37 42 32 42 Q27 42 23 44 Z" fill="#FFF" />
      <path d="M14 32 C14 18 50 18 50 32 C50 36 42 40 32 40 C22 40 14 36 14 32 Z" fill="url(#cap-sui)" />
      <path d="M22 24 Q32 20 42 24" stroke="#FFF" stroke-width="2" fill="none" opacity="0.5" stroke-linecap="round"/>
    </svg>`,

  // 6. Опеньок осінній (Armillaria mellea)
  "armillaria_mellea": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-arm" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#DAA520" />
          <stop offset="100%" stop-color="#B8860B" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="8" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M28 38 L26 58 L38 58 L36 38 Z" fill="#FFF8DC" />
      <path d="M22 42 Q32 48 42 42 Q38 40 32 40 Q26 40 22 42 Z" fill="#FFF" stroke="#E0E0E0" stroke-width="1" />
      <path d="M16 32 C16 20 48 20 48 32 C48 36 40 40 32 40 C24 40 16 36 16 32 Z" fill="url(#cap-arm)" />
      <circle cx="32" cy="26" r="2" fill="#8B6508" />
      <circle cx="26" cy="28" r="1.5" fill="#8B6508" />
      <circle cx="38" cy="28" r="1.5" fill="#8B6508" />
    </svg>`,

  // 7. Рижик (Lactarius deliciosus)
  "lactarius_deliciosus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-lact" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#FF8C00" />
          <stop offset="100%" stop-color="#D2691E" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="9" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M27 38 Q26 52 28 58 L36 58 Q38 52 37 38 Z" fill="#FF8C00" />
      <circle cx="30" cy="48" r="1" fill="#228B22" />
      <circle cx="35" cy="52" r="1" fill="#228B22" />
      <path d="M12 28 C12 16 52 16 52 28 C52 36 42 40 32 40 C22 40 12 36 12 28 Z" fill="url(#cap-lact)" />
      <ellipse cx="32" cy="26" rx="8" ry="3" fill="#A0522D" opacity="0.6" />
      <path d="M18 30 Q32 34 46 30" stroke="#D2691E" stroke-width="1.5" fill="none" opacity="0.5"/>
    </svg>`,

  // 8. Груздь (Lactarius resimus)
  "lactarius_resimus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-gruz" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#FFFFFF" />
          <stop offset="100%" stop-color="#E8E8E8" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="12" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M25 38 Q22 55 26 58 L38 58 Q42 55 39 38 Z" fill="#FFF" />
      <path d="M12 32 C12 18 52 18 52 32 C52 38 46 42 32 42 C18 42 12 38 12 32 Z" fill="url(#cap-gruz)" stroke="#CCC" stroke-width="1" />
      <ellipse cx="32" cy="30" rx="14" ry="6" fill="none" stroke="#DDD" stroke-width="1.5" />
      <ellipse cx="32" cy="30" rx="8" ry="3" fill="none" stroke="#DDD" stroke-width="1.5" />
    </svg>`,

  // 9. Сироїжка (Russula vesca)
  "russula_vesca": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-russ" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#E32636" />
          <stop offset="100%" stop-color="#8B0000" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="8" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M27 38 L26 58 L38 58 L37 38 Z" fill="#FFFFFF" />
      <path d="M14 34 C14 20 50 20 50 34 C50 38 42 40 32 40 C22 40 14 38 14 34 Z" fill="url(#cap-russ)" />
      <path d="M22 28 Q32 24 42 28" stroke="#FFF" stroke-width="1.5" fill="none" opacity="0.4" stroke-linecap="round"/>
    </svg>`,

  // 10. Печериця (Agaricus campestris)
  "agaricus_campestris": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-agar" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#F5F5F5" />
          <stop offset="100%" stop-color="#D3D3D3" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="9" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M27 38 L25 58 L39 58 L37 38 Z" fill="#FFF" />
      <path d="M24 42 Q32 46 40 42 Q36 40 32 40 Q28 40 24 42 Z" fill="#F5F5F5" stroke="#CCC" stroke-width="1"/>
      <path d="M14 34 C14 20 50 20 50 34 C50 38 42 40 32 40 C22 40 14 38 14 34 Z" fill="url(#cap-agar)" />
    </svg>`,

  // 11. Сморчок (Morchella esculenta)
  "morchella_esculenta": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-mor" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#D2B48C" />
          <stop offset="100%" stop-color="#8B7355" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="8" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M28 40 L26 58 L38 58 L36 40 Z" fill="#FFF8DC" />
      <path d="M22 40 C22 20 42 20 42 40 C42 42 38 44 32 44 C26 44 22 42 22 40 Z" fill="url(#cap-mor)" />
      <path d="M26 36 L38 36 M24 30 L40 30 M28 24 L36 24 M30 18 L34 18" stroke="#5C4033" stroke-width="1.5" fill="none" />
      <path d="M32 38 L32 22 M28 34 L28 26 M36 34 L36 26" stroke="#5C4033" stroke-width="1.5" fill="none" />
    </svg>`,

  // 12. Дощовик (Lycoperdon perlatum)
  "lycoperdon_perlatum": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-lyco" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#FFFFFF" />
          <stop offset="100%" stop-color="#E0E0E0" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="10" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M22 40 C22 20 42 20 42 40 C42 52 38 58 32 58 C26 58 22 52 22 40 Z" fill="url(#cap-lyco)" />
      <circle cx="28" cy="30" r="1.5" fill="#CCC" />
      <circle cx="36" cy="32" r="1.5" fill="#CCC" />
      <circle cx="32" cy="24" r="1.5" fill="#CCC" />
      <circle cx="26" cy="38" r="1.5" fill="#CCC" />
      <circle cx="38" cy="42" r="1.5" fill="#CCC" />
      <circle cx="32" cy="46" r="1.5" fill="#CCC" />
      <circle cx="30" cy="52" r="1.5" fill="#CCC" />
      <circle cx="34" cy="36" r="1.5" fill="#CCC" />
    </svg>`,

  // 13. Дубовик (Boletus luridus)
  "boletus_luridus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-lur" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#8B8B00" />
          <stop offset="100%" stop-color="#556B2F" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="11" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M26 40 Q24 55 28 58 L36 58 Q40 55 38 40 Z" fill="#FFD700" />
      <path d="M26 44 L38 44 M27 48 L37 48 M28 52 L36 52 M28 46 L32 44 M36 46 L32 44" stroke="#FF0000" stroke-width="1.5" fill="none" />
      <path d="M12 34 C12 22 52 22 52 34 C52 40 42 44 32 44 C22 44 12 40 12 34 Z" fill="url(#cap-lur)" />
      <path d="M20 28 Q32 24 44 28" stroke="rgba(255,255,255,0.2)" stroke-width="2" fill="none" stroke-linecap="round"/>
    </svg>`,

  // 14. Моховик (Xerocomus subtomentosus)
  "xerocomus_subtomentosus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-xero" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#A08B5C" />
          <stop offset="100%" stop-color="#6B5B3E" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="10" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M26 40 Q24 55 28 58 L36 58 Q40 55 38 40 Z" fill="#DAA520" />
      <path d="M12 34 C12 24 52 24 52 34 C52 40 42 42 32 42 C22 42 12 40 12 34 Z" fill="url(#cap-xero)" />
      <path d="M20 28 Q32 25 44 28" stroke="rgba(255,255,255,0.15)" stroke-width="2" fill="none" stroke-linecap="round"/>
    </svg>`,

  // 15. Вовнянка (Lactarius torminosus)
  "lactarius_torminosus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-vovn" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#FFB6C1" />
          <stop offset="100%" stop-color="#DB7093" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="9" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M27 38 Q26 52 28 58 L36 58 Q38 52 37 38 Z" fill="#FFC0CB" />
      <path d="M14 30 C14 18 50 18 50 30 C50 36 42 40 32 40 C22 40 14 36 14 30 Z" fill="url(#cap-vovn)" />
      <path d="M14 30 L12 32 M17 32 L16 35 M20 34 L19 37 M24 37 L24 40 M28 38 L28 41 M36 38 L36 41 M40 37 L40 40 M44 34 L45 37 M47 32 L48 35 M50 30 L52 32" stroke="#FFB6C1" stroke-width="1.5" fill="none" stroke-linecap="round" />
      <path d="M20 28 Q32 32 44 28" stroke="#DB7093" stroke-width="1.5" fill="none" opacity="0.5"/>
    </svg>`,

  // 16. Глива (Pleurotus ostreatus)
  "pleurotus_ostreatus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-gliva" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#A9A9A9" />
          <stop offset="100%" stop-color="#696969" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="14" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M36 46 Q46 50 48 56 L40 56 Q36 52 34 46 Z" fill="#F5F5F5" />
      <path d="M12 36 C12 16 46 20 44 36 C42 46 28 46 22 44 C16 42 12 36 12 36 Z" fill="url(#cap-gliva)" />
      <path d="M18 36 Q26 42 34 40 M22 32 Q28 38 36 36 M26 28 Q30 34 38 32" stroke="#555" stroke-width="1.5" fill="none" opacity="0.6"/>
    </svg>`,

  // 17. Їжовик (Hydnum repandum)
  "hydnum_repandum": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-hyd" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#FFDAB9" />
          <stop offset="100%" stop-color="#F4A460" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="10" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M26 38 Q24 55 28 58 L36 58 Q40 55 38 38 Z" fill="#F5DEB3" />
      <path d="M14 32 C14 22 50 22 50 32 C50 38 42 40 32 40 C22 40 14 38 14 32 Z" fill="url(#cap-hyd)" />
      <path d="M18 38 L18 42 M22 39 L22 43 M26 40 L26 44 M30 40 L30 44 M34 40 L34 44 M38 39 L38 43 M42 38 L42 42" stroke="#E8C396" stroke-width="1.5" fill="none" stroke-linecap="round" />
    </svg>`,

  // 18. Козляк (Suillus bovinus)
  "suillus_bovinus": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-koz" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#D2B48C" />
          <stop offset="100%" stop-color="#A0522D" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="8" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M28 38 Q26 55 28 58 L36 58 Q38 55 36 38 Z" fill="#D2B48C" />
      <path d="M16 32 C16 22 48 22 48 32 C48 36 42 40 32 40 C22 40 16 36 16 32 Z" fill="url(#cap-koz)" />
    </svg>`,

  // 19. Зимовий опеньок (Flammulina velutipes)
  "flammulina_velutipes": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-flam" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#FFA500" />
          <stop offset="100%" stop-color="#D2691E" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="8" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M28 38 Q25 50 26 58 L38 58 Q39 50 36 38 Z" fill="#5C4033" />
      <path d="M16 34 C16 22 48 22 48 34 C48 38 40 40 32 40 C24 40 16 38 16 34 Z" fill="url(#cap-flam)" />
      <path d="M22 28 Q32 24 42 28" stroke="#FFF" stroke-width="1.5" fill="none" opacity="0.4" stroke-linecap="round"/>
    </svg>`,

  // 20. Польський гриб (Imleria badia)
  "imleria_badia": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-pol" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#5C4033" />
          <stop offset="100%" stop-color="#2F1B14" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="10" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M26 40 Q24 55 28 58 L36 58 Q40 55 38 40 Z" fill="#8B4513" />
      <path d="M12 34 C12 22 52 22 52 34 C52 40 42 42 32 42 C22 42 12 40 12 34 Z" fill="url(#cap-pol)" />
      <path d="M20 28 Q32 25 44 28" stroke="rgba(255,255,255,0.1)" stroke-width="2" fill="none" stroke-linecap="round"/>
    </svg>`,

  // --- Ті, що на ваших скріншотах ---

  // Гриб-зонтик великий (Macrolepiota procera)
  "macrolepiota_procera": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-para" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#E8DCC4" />
          <stop offset="100%" stop-color="#D2B48C" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="8" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M29 32 L27 58 L37 58 L35 32 Z" fill="#D2B48C" />
      <path d="M24 38 Q32 42 40 38 Q36 36 32 36 Q28 36 24 38 Z" fill="#F5F5DC" stroke="#A0522D" stroke-width="1"/>
      <path d="M24 40 Q32 44 40 40" stroke="#A0522D" stroke-width="1" fill="none" />
      <path d="M8 30 C8 18 56 18 56 30 C56 32 44 34 32 34 C20 34 8 32 8 30 Z" fill="url(#cap-para)" />
      <circle cx="32" cy="24" r="4" fill="#A0522D" opacity="0.6" />
      <circle cx="20" cy="28" r="2" fill="#A0522D" opacity="0.4" />
      <circle cx="44" cy="28" r="2" fill="#A0522D" opacity="0.4" />
      <circle cx="14" cy="30" r="1.5" fill="#A0522D" opacity="0.4" />
      <circle cx="50" cy="30" r="1.5" fill="#A0522D" opacity="0.4" />
    </svg>`,

  // Зморшок степовий (Morchella steppicola)
  "morchella_steppicola": `
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="cap-step" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stop-color="#E8DCC4" />
          <stop offset="100%" stop-color="#A08B5C" />
        </linearGradient>
      </defs>
      <ellipse cx="32" cy="58" rx="8" ry="3" fill="rgba(0,0,0,0.15)" />
      <path d="M28 40 L26 58 L38 58 L36 40 Z" fill="#FFF8DC" />
      <path d="M18 40 C18 20 46 20 46 40 C46 44 38 46 32 46 C26 46 18 44 18 40 Z" fill="url(#cap-step)" />
      <path d="M24 36 L40 36 M22 32 L42 32 M26 28 L38 28 M30 24 L34 24" stroke="#5C4033" stroke-width="1.5" fill="none" />
      <path d="M30 42 L30 22 M34 42 L34 22" stroke="#5C4033" stroke-width="1.5" fill="none" />
      <path d="M26 38 L26 26 M38 38 L38 26" stroke="#5C4033" stroke-width="1.5" fill="none" />
    </svg>`
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

  // 1. Спочатку перевіряємо деталізовані SVG (з градієнтами, чіткими контурами)
  const detailed = DETAILED_SVGS[resolved];
  if (detailed) {
    return `<span style="display:inline-block; width:${size}px; height:${size}px; vertical-align:middle;">${detailed}</span>`;
  }

  // 2. Інакше — шаблонна іконка з MUSHROOM_VISUALS
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
